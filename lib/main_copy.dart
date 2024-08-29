import 'package:flutter/material.dart';
import 'package:bitcoinsilver_wallet/services/wallet_service.dart';
import 'package:bitcoinsilver_wallet/services/transaction_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bitcoin Silver Wallet',
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Bitcoin Silver Wallet'),
        ),
        body: const AddressGenerator(),
      ),
    );
  }
}

class AddressGenerator extends StatefulWidget {
  const AddressGenerator({super.key});

  @override
  _AddressGeneratorState createState() => _AddressGeneratorState();
}

class _AddressGeneratorState extends State<AddressGenerator> {
  final TextEditingController _address1Controller = TextEditingController();
  final TextEditingController _privateKeyController = TextEditingController();
  final TextEditingController _recoveryPrivateKeyController =
      TextEditingController();
  final TextEditingController _recoveredAddressController =
      TextEditingController();

  final TextEditingController _senderPrivateKeyController =
      TextEditingController();
  final TextEditingController _recipientAddressController =
      TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  final WalletService _walletService = WalletService();
  final TransactionService _transactionService = TransactionService();

  void _generateAddresses() {
    final result = _walletService.generateAddresses();
    setState(() {
      _address1Controller.text = result['address1']!;
      _privateKeyController.text = result['privateKey']!;
    });
  }

  void _recoverAddress() {
    final recoveredAddress = _walletService
        .recoverAddress(_recoveryPrivateKeyController.text.trim());
    setState(() {
      _recoveredAddressController.text =
          recoveredAddress ?? 'Fehler: Ungültiger privater Schlüssel';
    });
  }

  void _createTransaction() async {
    final senderPrivateKey = _senderPrivateKeyController.text.trim();
    final recipientAddress = _recipientAddressController.text.trim();
    final amountBTC = double.tryParse(_amountController.text.trim());

    if (senderPrivateKey.isEmpty ||
        recipientAddress.isEmpty ||
        amountBTC == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte alle Felder ausfüllen.')),
      );
      return;
    }

    // Umrechnung von BTC in Satoshis
    final amountSatoshis = (amountBTC * 1e8).toInt();

    try {
      final txid = await _transactionService.createAndSendTransaction(
        privateKeyHex: senderPrivateKey,
        toAddress: recipientAddress,
        amount: amountSatoshis,
        fee: 1000, // Setze hier deine gewünschte Gebühr
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transaktion gesendet: $txid')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Senden der Transaktion: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          TextField(
            controller: _address1Controller,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Address',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _privateKeyController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Private Key',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _generateAddresses,
            child: const Text('Generate Address'),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _recoveryPrivateKeyController,
            decoration: const InputDecoration(
              labelText: 'Private Key for Recovery',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _recoveredAddressController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Recovered Address',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: _recoverAddress,
            child: const Text('Recover Address'),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _senderPrivateKeyController,
            decoration: const InputDecoration(
              labelText: 'Sender Private Key',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _recipientAddressController,
            decoration: const InputDecoration(
              labelText: 'Recipient Address',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount (in BTCS)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _createTransaction,
            child: const Text('Create Transaction'),
          ),
        ],
      ),
    );
  }
}
