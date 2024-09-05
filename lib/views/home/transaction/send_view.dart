import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/views/home/transaction/scanner_view.dart';
import 'package:bitcoinsilver_wallet/widgets/button_widget.dart';

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

  Future<void> _fetchBalance() async {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    await walletProvider.fetchUtxos();
    setState(() {
      _balance = walletProvider.balance ?? 0.0;
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Send',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        centerTitle: true,
      ),
      body: Container(
        color: Colors.black,
        constraints: const BoxConstraints.expand(),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(top: 32.0, left: 16.0, right: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _addressController,
                  decoration: InputDecoration(
                    labelText: 'Recipient Address',
                    labelStyle: const TextStyle(color: Colors.white),
                    filled: true,
                    fillColor: Colors.black,
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
                      icon: const Icon(Icons.qr_code_scanner,
                          color: Colors.white),
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
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Amount',
                          labelStyle: const TextStyle(color: Colors.white),
                          filled: true,
                          fillColor: Colors.black,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: const BorderSide(
                                color: Colors.white, width: 1.0),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: const BorderSide(
                                color: Colors.white, width: 1.0),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ButtonWidget(
                      text: 'Max',
                      isPrimary: true,
                      onPressed: _setMaxAmount,
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
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: 'Fee',
                          labelStyle: const TextStyle(color: Colors.white),
                          filled: true,
                          fillColor: Colors.black,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: const BorderSide(
                                color: Colors.white, width: 1.0),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8.0),
                            borderSide: const BorderSide(
                                color: Colors.white, width: 1.0),
                          ),
                        ),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ButtonWidget(
                      text: 'Auto',
                      isPrimary: true,
                      onPressed: _setFee,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (_errorMessage.isNotEmpty)
                  Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 20),
                const Text(
                  'To send cryptocurrency, enter the recipient’s address and the amount you wish to transfer. Ensure you have enough balance to cover the transaction. After entering the details, confirm by checking the box below and press "Send".',
                  style: TextStyle(color: Colors.white54),
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
                      checkColor: Colors.black,
                      activeColor: Colors.white,
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
                ButtonWidget(
                  text: 'Send',
                  isPrimary: true,
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
