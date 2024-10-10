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
  bool _hasMore = true;
  int _startIndex = 0;
  final int _limit = 50;

  String get timestamp => _timestamp;
  List get transactions => _transactions;
  double get price => _price;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  Future<void> loadBlockchain(address) async {
    final DateTime now = DateTime.now();
    final String formattedDate = DateFormat('HH:mm:ss').format(now);
    await fetchTransactions(address);
    _timestamp = formattedDate;
    notifyListeners();
  }

  Future<void> fetchPrice() async {
    const url = Config.priceUrl;
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _price = double.parse(data['data']['last']);
      } else {
        throw Exception('Failed to load price');
      }
    } finally {
      notifyListeners();
    }
  }

  Future<void> fetchTransactions(String address) async {
    if (_isLoading) return;
    _isLoading = true;

    final url =
        '${Config.explorerUrl}${Config.getAddressTxsEndpoint}/$address/$_startIndex/$_limit';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        if (data.isEmpty) {
          _hasMore = false;
        } else {
          List<Map<String, dynamic>> castedData =
              data.whereType<Map<String, dynamic>>().toList();
          List<Map<String, dynamic>> transactions =
              splitTransactions(castedData);
          _transactions.addAll(transactions);
          _startIndex += _limit;
        }
      } else {
        throw Exception('Failed to load transactions');
      }
    } finally {
      await fetchPrice();
      _isLoading = false;
      notifyListeners();
    }
  }

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
