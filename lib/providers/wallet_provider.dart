import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:bitcoinsilver_wallet/config.dart';
import 'package:bitcoinsilver_wallet/services/wallet_service.dart';

class WalletProvider with ChangeNotifier {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final WalletService _ws = WalletService();

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
      _address = _ws.loadAddressFromKey(_privateKey!);
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

  Future<void> fetchUtxos() async {
    if (_address == null) {
      return;
    }

    final result = await _ws.rpcRequest('scantxoutset', [
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

  Future<Map<String, dynamic>?> createTransaction(
      String address, double? amount) async {
    await fetchUtxos();

    List<Map<String, dynamic>> selectedUtxos = [];
    double accumulatedAmount = 0.0;

    for (var utxo in _utxos) {
      selectedUtxos.add({
        'txid': utxo['txid'],
        'vout': utxo['vout'],
      });
      accumulatedAmount += utxo['amount'];
    }

    if (amount == null || amount >= accumulatedAmount) {
      amount = accumulatedAmount;
    }

    double feeInBitcoin = 0.0001;

    if (amount == accumulatedAmount) {
      if (accumulatedAmount <= feeInBitcoin) {
        throw Exception('Insufficient funds to cover the fee');
      }
      amount -= feeInBitcoin;
    } else {
      if (accumulatedAmount < amount + feeInBitcoin) {
        throw Exception('Insufficient UTXOs to cover the amount and the fee');
      }
    }

    double change = accumulatedAmount - amount - feeInBitcoin;
    amount = double.parse(amount.toStringAsFixed(8));
    change = double.parse(change.toStringAsFixed(8));

    print('Amount to send: $amount');
    print('Fee: $feeInBitcoin');
    print('Change: $change');

    if (change < 0) {
      throw Exception('Insufficient funds to cover the amount and the fee');
    }

    final createRawResult = await _ws.rpcRequest('createrawtransaction', [
      selectedUtxos,
      (change > 0)
          ? [
              {address: amount},
              {_address: change}
            ]
          : [
              {address: amount}
            ]
    ]);

    return createRawResult;
  }

  Future<Map<String, dynamic>> sendTransaction(
      String address, double amount) async {
    if (_privateKey == null || _address == null) {
      return {'success': false, 'message': 'Private key or address is missing'};
    }

    final createRawResult = await createTransaction(address, amount);

    if (createRawResult == null) {
      return {'success': false, 'message': 'Error creating raw transaction'};
    }

    final rawTx = createRawResult['result'];

    final signRawResult = await _ws.rpcRequest('signrawtransactionwithkey', [
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

    final sendRawResult =
        await _ws.rpcRequest('sendrawtransaction', [signedTx, 0]);

    if (sendRawResult == null || sendRawResult['result'] == null) {
      return {'success': false, 'message': 'Error sending transaction'};
    }

    return {'success': true, 'message': 'Transaction sent successfully'};
  }
}
