import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:bitcoinsilver_wallet/config.dart';

class TransactionProvider with ChangeNotifier {
  final List<dynamic> _transactions = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _startIndex = 0;
  final int _limit = 50;

  List get transactions => _transactions;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  Future<void> fetchTransactions(String address) async {
    if (_isLoading) return;
    _isLoading = true;

    final url =
        '${Config.baseUrl}${Config.getAddressTxsEndpoint}/$address/$_startIndex/$_limit';

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
