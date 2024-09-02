import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/views/home/transaction/scanner_view.dart'; // Importiere die ScannerView

class SendView extends StatefulWidget {
  const SendView({super.key});

  @override
  State<SendView> createState() => _SendViewState();
}

class _SendViewState extends State<SendView> {
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  double _balance = 0.0;
  bool _isChecked = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchBalance();
  }

  void _fetchBalance() {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    setState(() {
      _balance =
          walletProvider.balance!; // Balance aus dem WalletProvider holen
    });
  }

  void _setMaxAmount() {
    setState(() {
      _amountController.text =
          _balance.toStringAsFixed(2); // Balance als Text setzen
    });
  }

  Future<void> _send() async {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final amount = double.tryParse(_amountController.text);

    if (amount == null || amount <= 0) {
      setState(() {
        _errorMessage = 'Invalid amount entered.';
      });
      return;
    }

    if (_isChecked) {
      if (_addressController.text.trim() != '') {
        if (walletProvider.balance! >= amount) {
          if (walletProvider.utxos != null &&
              walletProvider.utxos!.isNotEmpty) {
            await walletProvider.sendTransaction(
                _addressController.text, amount);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Successful sent transaction')),
              );
            }
            setState(() {
              _errorMessage = '';
            });
          } else {
            setState(() {
              _errorMessage = 'No UTXOs found.';
            });
          }
        } else {
          setState(() {
            _errorMessage = 'Insufficient balance.';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Enter the address.';
        });
      }
    } else {
      setState(() {
        _errorMessage = 'Please check the checkbox to proceed.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const appBarColor = Color(0xFF333333); // Gleiche Farbe wie die AppBar

    return Scaffold(
      appBar: AppBar(
        backgroundColor: appBarColor, // Gleiche Farbe wie der Hintergrund
        elevation: 0, // Keine Schatten
        title: const Text(
          'Send',
          style: TextStyle(color: Colors.white, fontSize: 20), // Weißer Text
        ),
        leading: IconButton(
          icon:
              const Icon(Icons.arrow_back, color: Colors.white), // Weißes Icon
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        centerTitle: true, // Text zentrieren
      ),
      body: Container(
        color: appBarColor, // Hintergrundfarbe des Containers
        constraints:
            const BoxConstraints.expand(), // Container auf volle Höhe setzen
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _addressController,
                decoration: InputDecoration(
                  labelText: 'Address',
                  labelStyle: const TextStyle(color: Colors.white),
                  filled: true,
                  fillColor: appBarColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide:
                        const BorderSide(color: Colors.white, width: 1.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide:
                        const BorderSide(color: Colors.white, width: 1.0),
                  ),
                  suffixIcon: IconButton(
                    icon:
                        const Icon(Icons.qr_code_scanner, color: Colors.white),
                    onPressed: () async {
                      final scannedAddress = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ScannerView(),
                        ),
                      );
                      if (scannedAddress != null) {
                        setState(() {
                          _addressController.text = scannedAddress;
                        });
                      }
                    },
                  ),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Amount',
                        labelStyle: const TextStyle(color: Colors.white),
                        filled: true,
                        fillColor: appBarColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide:
                              const BorderSide(color: Colors.white, width: 1.0),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          borderSide:
                              const BorderSide(color: Colors.white, width: 1.0),
                        ),
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _setMaxAmount,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          appBarColor, // Hintergrundfarbe des Buttons
                    ),
                    child: const Text(
                      'Max.',
                      style: TextStyle(
                          color: Colors.white), // Textfarbe des Buttons
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_errorMessage.isNotEmpty)
                Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              const SizedBox(height: 20),
              const Text(
                'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.',
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _isChecked,
                        onChanged: (bool? value) {
                          setState(() {
                            _isChecked = value ?? false;
                          });
                        },
                        checkColor: Colors.white, // Farbe des Häkchens
                        activeColor:
                            appBarColor, // Hintergrundfarbe der Checkbox
                      ),
                      const Text(
                        'Lorem ipsum dolor sit amet',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: _send,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          Colors.white, // Hintergrundfarbe des Buttons
                    ),
                    child: const Text(
                      'Send',
                      style: TextStyle(
                          color: appBarColor), // Textfarbe des Buttons
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
