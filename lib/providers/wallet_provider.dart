import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

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
    _privateKey = await _storage.read(key: 'wifPrivateKey');
    if (_privateKey == null) {
      final result = _walletService.generateAddresses();
      _privateKey = result['wifPrivateKey'];
      _address = result['address'];
      await _storage.write(key: 'wifPrivateKey', value: _privateKey);
    } else {
      _address = _walletService.recoverAddressFromWif(_privateKey!);
    }
    await fetchUtxos();
    notifyListeners();
  }

  Future<Map<String, dynamic>> _rpcRequest(String method,
      [List<dynamic>? params]) async {
    final auth = 'Basic ${base64Encode(utf8.encode('$rpcUser:$rpcPassword'))}';
    final headers = {'Content-Type': 'application/json', 'Authorization': auth};

    final body = jsonEncode({
      'jsonrpc': '1.0',
      'id': 'curltext',
      'method': method,
      'params': params ?? [],
    });

    try {
      final response = await http.post(
        Uri.parse(rpcUrl),
        headers: headers,
        body: body,
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception(
            'RPC Call Error: ${response.statusCode} ${response.reasonPhrase}');
      }
    } catch (e) {
      throw Exception('Exception: $e');
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

    if (result['result'] != null) {
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

  Future<void> sendTransaction(String toAddress, double amount) async {
    await fetchUtxos();
    if (_privateKey == null || _address == null) {
      return;
    }
    // Erstellen der Transaktion
    final createRawResult = await _rpcRequest('createrawtransaction', [
      _utxos
          .map((utxo) => {
                'txid': utxo['txid'],
                'vout': utxo['vout'],
                // Entferne scriptPubKey, da es nicht in den Eingaben erwartet wird
              })
          .toList(),
      [
        {toAddress: amount},
        // Hier wird das Senden der Gebühren für das Change-Address berücksichtigt, falls vorhanden
        if (_balance! - amount - 0.00001 > 0)
          {_address: _balance! - amount - 0.00001},
      ]
    ]);

    final rawTx = createRawResult['result'];

    // Signieren der Transaktion
    final signRawResult = await _rpcRequest('signrawtransactionwithkey', [
      rawTx,
      [_privateKey]
    ]);

    final signedTx = signRawResult['result']['hex'];

    // Überprüfen, ob die Transaktion vollständig signiert ist
    if (!signRawResult['result']['complete']) {
      return;
    }

    // Senden der Transaktion
    await _rpcRequest('sendrawtransaction', [signedTx]);
    notifyListeners();
  }
}
