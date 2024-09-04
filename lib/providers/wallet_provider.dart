import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:bitcoinsilver_wallet/config.dart';
import 'package:bitcoinsilver_wallet/services/wallet_service.dart';

class WalletProvider with ChangeNotifier {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final WalletService _walletService = WalletService();

  final String rpcUrl = Config.rpcUrl;
  final String rpcUser = Config.rpcUser;
  final String rpcPassword = Config.rpcPassword;

  String? _privateKey;
  String? _address;
  double? _balance = 0.0;
  List _utxos = [];

  String? get privateKey => _privateKey;
  String? get address => _address;
  double? get balance => _balance;
  List? get utxos => _utxos;

  WalletProvider() {
    loadWallet();
  }

  Future<void> loadWallet() async {
    _privateKey = await _storage.read(key: 'key');
    if (_privateKey != null) {
      _address = _walletService.loadAddressFromKey(_privateKey!);
    }
    notifyListeners();
  }

  Future<void> saveWallet(String address, String privateKey) async {
    _privateKey = privateKey;
    _address = address;
    await _storage.write(key: 'key', value: privateKey);
    notifyListeners();
  }

  Future<void> deleteWallet() async {
    _privateKey = null;
    _address = null;
    await _storage.delete(key: 'key');
    notifyListeners();
  }

  Future<Map<String, dynamic>?> _rpcRequest(String method,
      [List<dynamic>? params]) async {
    final auth = 'Basic ${base64Encode(utf8.encode('$rpcUser:$rpcPassword'))}';
    final headers = {'Content-Type': 'application/json', 'Authorization': auth};

    final body = jsonEncode({
      'jsonrpc': '1.0',
      'id': 'curltext',
      'method': method,
      'params': params ?? [],
    });

    final response = await http.post(
      Uri.parse(rpcUrl),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      print('RPC Call Error: ${response.statusCode} ${response.reasonPhrase}');
      print(
          'Response body: ${response.body}'); // Dies gibt den genauen Fehler aus, den die Node zurückgibt.
      return null;
    }
  }

  Future<void> fetchUtxos() async {
    if (_address == null) {
      return;
    }

    final result = await _rpcRequest('scantxoutset', [
      'start',
      [
        {'desc': 'addr($_address)'}
      ]
    ]);

    if (result != null && result['result'] != null) {
      final utxos = result['result']['unspents'] as List;
      _utxos = utxos;
      double totalBalance = 0.0;
      for (var utxo in utxos) {
        totalBalance += utxo['amount'];
      }
      _balance = totalBalance;
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> sendTransaction(
      String toAddress, double amount, double fee) async {
    await fetchUtxos();

    if (_privateKey == null || _address == null) {
      return {'success': false, 'message': 'Private key or address is missing'};
    }

    double roundedAmount = (amount * pow(10, 8)).round() / pow(10, 8);
    double roundedFee = (fee * pow(10, 8)).round() / pow(10, 8);
    double totalAmount = roundedAmount + roundedFee;

    List<Map<String, dynamic>> selectedUtxos = [];
    double accumulatedAmount = 0.0;

    for (var utxo in _utxos) {
      selectedUtxos.add({
        'txid': utxo['txid'],
        'vout': utxo['vout'],
      });
      accumulatedAmount += utxo['amount'];
      if (accumulatedAmount >= totalAmount) break;
    }

    if (accumulatedAmount < totalAmount) {
      return {'success': false, 'message': 'Not enough funds'};
    }

    double changeAmount = accumulatedAmount - totalAmount;
    if (changeAmount < 0) {
      return {'success': false, 'message': 'Calculated change is negative'};
    }

    final createRawResult = await _rpcRequest('createrawtransaction', [
      selectedUtxos,
      [
        {toAddress: totalAmount},
        {_address: changeAmount}
      ]
    ]);

    if (createRawResult == null) {
      return {'success': false, 'message': 'Error creating raw transaction'};
    }

    final rawTx = createRawResult['result'];

    final signRawResult = await _rpcRequest('signrawtransactionwithkey', [
      rawTx,
      [_privateKey]
    ]);

    if (signRawResult == null) {
      return {'success': false, 'message': 'Error signing raw transaction'};
    }

    final signedTx = signRawResult['result']['hex'];
    if (!signRawResult['result']['complete']) {
      return {'success': false, 'message': 'Transaction is not fully signed'};
    }

    final sendRawResult = await _rpcRequest('sendrawtransaction', [signedTx]);

    if (sendRawResult == null || sendRawResult['result'] == null) {
      return {'success': false, 'message': 'Error sending transaction'};
    }

    return {'success': true, 'message': 'Transaction sent successfully'};
  }
}
