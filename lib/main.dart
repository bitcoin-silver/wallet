import 'package:flutter/material.dart';
import 'package:bitcoinsilver_wallet/services/bitcoin_silver_service.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Custom Bech32 Generator',
      home: Scaffold(
        appBar: AppBar(
          title: Text('Bech32 SegWit Generator'),
        ),
        body: Center(
          child: AddressGenerator(),
        ),
      ),
    );
  }
}

class AddressGenerator extends StatefulWidget {
  @override
  _AddressGeneratorState createState() => _AddressGeneratorState();
}

class _AddressGeneratorState extends State<AddressGenerator> {
  final TextEditingController _address1Controller = TextEditingController();
  final TextEditingController _address2Controller = TextEditingController();
  final TextEditingController _privateKeyController = TextEditingController();
  final TextEditingController _recoveryPrivateKeyController =
      TextEditingController();
  final TextEditingController _recoveredAddressController =
      TextEditingController();

  final BitcoinSilverService _service = BitcoinSilverService();

  void _generateAddresses() {
    final result = _service.generateAddresses();
    setState(() {
      _address1Controller.text = result['address1']!;
      _address2Controller.text = result['address2']!;
      _privateKeyController.text = result['privateKey']!;
    });
  }

  void _recoverAddress() {
    final recoveredAddress =
        _service.recoverAddress(_recoveryPrivateKeyController.text.trim());
    setState(() {
      _recoveredAddressController.text =
          recoveredAddress ?? 'Fehler: Ungültiger privater Schlüssel';
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextField(
              controller: _address1Controller,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Address 1',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 10),
            TextField(
              controller: _address2Controller,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Address 2',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _privateKeyController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Private Key',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _generateAddresses,
              child: Text('Generate Address'),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _recoveryPrivateKeyController,
              decoration: InputDecoration(
                labelText: 'Private Key for Recovery',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: _recoverAddress,
              child: Text('Recover Address'),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _recoveredAddressController,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Wiederhergestellte Adresse',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
