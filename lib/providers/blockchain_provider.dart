import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:bitcoinsilver_wallet/config.dart';

class BlockchainProvider with ChangeNotifier {
  String _timestamp = '';
  final List<dynamic> _transactions = [];
  double _price = 0.0;
  bool _isLoading = false;
  bool _isFetchingTransactions = false;
  bool _pendingSilentRefresh = false;
  bool _hasMore = true;
  int _startIndex = 0;
  final int _limit = 50;
  final int _maxTransactions = 200; // Server-side limit to reduce load

  String get timestamp => _timestamp;
  List get transactions => _transactions;
  double get price => _price;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  Future<void> loadBlockchain(String? address, {bool silent = false}) async {
    if (address == null) return;

    final DateTime now = DateTime.now();
    final String formattedDate = DateFormat('HH:mm:ss').format(now);

    if (!silent) {
      // Clear existing transactions and reset pagination to fetch latest
      _transactions.clear();
      _startIndex = 0;
      _hasMore = true;
      notifyListeners();
    }
    // A silent refresh (app resume, timer, notification) keeps the current
    // list on screen; fetchTransactions replaces it only once fresh data has
    // arrived. Clearing here made the wallet show "No Transactions Yet"
    // until the explorer answered, and kept it empty if the request failed.

    await fetchTransactions(address, silent: silent);
    _timestamp = formattedDate;
    notifyListeners();
  }

  Future<void> fetchPrice({bool silent = false}) async {
    const url = Config.liveCoinWatchUrl;
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'content-type': 'application/json',
          'x-api-key': Config.liveCoinWatchApiKey,
        },
        body: json.encode({
          'currency': 'USD',
          'code': Config.btcsCode,
          'meta': true,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('Price fetch request timed out after 30 seconds');
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // LiveCoinWatch returns the price in 'rate' field
        if (data['rate'] != null) {
          _price = (data['rate'] as num).toDouble();
        } else {
          debugPrint('LiveCoinWatch: Price data not in response');
        }
      } else {
        debugPrint('LiveCoinWatch failed with status: ${response.statusCode}');
      }
    } catch (e) {
      // Keep previous price if fetch fails - only log in debug mode
      debugPrint('Price fetch failed (keeping previous): $e');
    } finally {
      if (!silent) notifyListeners();
    }
  }

  Future<void> fetchTransactions(String address, {bool silent = false}) async {
    if (_isFetchingTransactions) {
      if (!silent) return;

      // Queue the refresh so resume/background sync is retried once the
      // active load finishes instead of being dropped.
      _pendingSilentRefresh = true;
      return;
    }

    _isFetchingTransactions = true;
    
    if (!silent) {
      _isLoading = true;
      notifyListeners();
    }

    final url =
        '${Config.explorerUrl}${Config.getAddressTxsEndpoint}?address=$address&limit=$_maxTransactions';

    try {
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Transaction fetch request timed out after 15 seconds');
        },
      );

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);

        // New API returns an object with 'transactions' array
        if (data is Map && data.containsKey('transactions')) {
          final List<dynamic> txsList = data['transactions'] ?? [];

          // Implement client-side pagination. A silent refresh always takes
          // the newest page and replaces the list in one step.
          final start = silent ? 0 : _startIndex;
          List<dynamic> paginatedTxs = txsList.skip(start).take(_limit).toList();

          if (silent) {
            _transactions.clear();
            _startIndex = 0;
            _hasMore = true;
          }

          if (paginatedTxs.isEmpty) {
            _hasMore = false;
          } else {
            List<Map<String, dynamic>> castedData =
                paginatedTxs.whereType<Map<String, dynamic>>().toList();
            List<Map<String, dynamic>> transactions =
                convertNewApiFormat(castedData);

            _transactions.addAll(transactions);
            _startIndex = start + _limit;

            // Check if we've reached the end
            if (_startIndex >= txsList.length) {
              _hasMore = false;
            }
          }
        } else {
          _hasMore = false;
        }
      } else {
        throw Exception('Failed to load transactions');
      }
    } catch (e) {
      debugPrint('Error fetching transactions: $e');
    } finally {
      await fetchPrice(silent: silent);
      _isFetchingTransactions = false;
      if (!silent) {
        _isLoading = false;
      }
      notifyListeners();

      if (_pendingSilentRefresh && !_isFetchingTransactions) {
        _pendingSilentRefresh = false;
        Future.delayed(const Duration(milliseconds: 250), () {
          loadBlockchain(address, silent: true);
        });
      }
    }
  }

  // Convert new API format to UI-compatible format
  List<Map<String, dynamic>> convertNewApiFormat(
      List<Map<String, dynamic>> transactions) {
    List<Map<String, dynamic>> convertedTxs = [];

    for (var tx in transactions) {
      // New API format: {txid, timestamp, amount, type: "received"/"sent"}
      double amount = (tx['amount'] is int)
          ? (tx['amount'] as int).toDouble()
          : (tx['amount'] as num).toDouble();

      // If type is "sent", make amount negative
      if (tx['type'] == 'sent') {
        amount = -amount;
      }

      convertedTxs.add({
        'timestamp': tx['timestamp'],
        'txid': tx['txid'],
        'amount': amount,
        'balance': 0, // New API doesn't provide balance per transaction
      });
    }

    return convertedTxs;
  }

  // Legacy function for old API format (kept for compatibility)
  List<Map<String, dynamic>> splitTransactions(
      List<Map<String, dynamic>> transactions) {
    List<Map<String, dynamic>> splitTxs = [];

    for (var tx in transactions) {
      if (tx['sent'] != 0 && tx['received'] != 0) {
        splitTxs.add({
          'timestamp': tx['timestamp'],
          'txid': tx['txid'],
          'amount': -(tx['received'] - tx['sent']),
          'balance': tx['balance'],
        });
      } else {
        splitTxs.add({
          'timestamp': tx['timestamp'],
          'txid': tx['txid'],
          'amount': tx['sent'],
          'balance': tx['balance'],
        });
      }
    }

    return splitTxs;
  }

  void clearTransactions() {
    _transactions.clear();
    _startIndex = 0;
    _hasMore = true;
    notifyListeners();
  }
}
