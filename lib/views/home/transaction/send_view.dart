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
  final TextEditingController _feeController = TextEditingController();

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
          walletProvider.balance ?? 0.0; // Balance aus dem WalletProvider holen
    });
  }

  void _setMaxAmount() {
    setState(() {
      _amountController.text = _balance.toString();
    });
  }

  void _setFee() {
    setState(() {
      _feeController.text = '0.00001';
    });
  }

  Future<void> _send() async {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final amount = double.tryParse(_amountController.text);
    final fee = double.tryParse(_feeController.text);

    if (amount == null || amount <= 0) {
      setState(() {
        _errorMessage = 'Invalid amount entered.';
      });
      return;
    }

    if (fee == null || fee <= 0) {
      setState(() {
        _errorMessage = 'Please enter a valid fee.';
      });
      return;
    }

    if (_isChecked) {
      if (_addressController.text.trim().isNotEmpty) {
        if (walletProvider.balance != null &&
            walletProvider.balance! >= amount) {
          // Add fee to the amount check
          if (walletProvider.utxos != null &&
              walletProvider.utxos!.isNotEmpty) {
            final result = await walletProvider.sendTransaction(
                _addressController.text, amount, fee);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result['message']),
                  backgroundColor:
                      result['success'] ? Colors.green : Colors.red,
                ),
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
          _errorMessage = 'Please enter the recipient address.';
        });
      }
    } else {
      setState(() {
        _errorMessage = 'Please check the checkbox to confirm the transaction.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const appBarColor = Color(0xFF333333); // Same color as the AppBar

    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            const Color(0xFF333333), // Same color as the background
        elevation: 0, // No shadow
        title: const Text(
          'Send',
          style: TextStyle(color: Colors.white, fontSize: 20), // White text
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white), // White icon
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        centerTitle: true, // Center the title
      ),
      body: Container(
        color: appBarColor, // Background color of the container
        constraints:
            const BoxConstraints.expand(), // Expand container to full height
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _addressController,
                decoration: InputDecoration(
                  labelText: 'Recipient Address',
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
                      backgroundColor: Colors.white, // Button background color
                    ),
                    child: const Text(
                      'Max',
                      style: TextStyle(color: appBarColor), // Button text color
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _feeController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Fee',
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
                    onPressed: _setFee,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white, // Button background color
                    ),
                    child: const Text(
                      'Recommended',
                      style: TextStyle(color: appBarColor), // Button text color
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
                'To send cryptocurrency, enter the recipient’s address and the amount you wish to transfer. Ensure you have enough balance to cover the transaction. After entering the details, confirm by checking the box below and press "Send".',
                style: TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: _isChecked,
                    onChanged: (bool? value) {
                      setState(() {
                        _isChecked = value ?? false;
                      });
                    },
                    checkColor: appBarColor, // Color of the checkmark
                    activeColor:
                        Colors.white, // Background color of the checkbox
                  ),
                  const Expanded(
                    child: Text(
                      'I confirm that the details are correct',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white, // Button background color
                ),
                child: const Text(
                  'Send',
                  style: TextStyle(color: appBarColor), // Button text color
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
