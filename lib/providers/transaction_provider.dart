import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'package:bitcoinsilver_wallet/config.dart';
import 'package:bitcoinsilver_wallet/models/transaction.dart';

class TransactionProvider with ChangeNotifier {
  final List<Transaction> _transactions = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _startIndex = 0;
  final int _limit = 50;

  List<Transaction> get transactions => _transactions;
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
          final List<Transaction> loadedTransactions =
              data.map((tx) => Transaction.fromJson(tx)).toList();
          _transactions.addAll(loadedTransactions);
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

  void clearTransactions() {
    _transactions.clear();
    _startIndex = 0;
    _hasMore = true;
    notifyListeners();
  }
}
