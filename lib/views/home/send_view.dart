import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/views/home/scanner_view.dart';
import 'package:bitcoinsilver_wallet/views/home/addressbook_view.dart';
import 'package:bitcoinsilver_wallet/widgets/button_widget.dart';

class SendView extends StatefulWidget {
  const SendView({super.key});

  @override
  State<SendView> createState() => _SendViewState();
}

class _SendViewState extends State<SendView> {
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  bool _isChecked = false;
  String _errorMessage = '';
  bool _isSending = false;
  double _estimatedFee = 0.00001; // Default fee estimate

  @override
  void initState() {
    super.initState();
    // Fetch fresh balance on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshBalance();
    });
  }

  @override
  void dispose() {
    _addressController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _refreshBalance() async {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    await walletProvider.fetchUtxos(force: true);
  }

  void _setMaxAmount() {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final balance = walletProvider.balance ?? 0.0;

    // Leave some for fees (rough estimate)
    final maxAmount = balance > _estimatedFee ? balance - _estimatedFee : 0.0;

    setState(() {
      _amountController.text = maxAmount.toStringAsFixed(8);
      _errorMessage = '';
    });
  }

  bool _isValidBitcoinSilverAddress(String address) {
    // Bitcoin Silver uses Bech32 addresses starting with 'bs1'
    if (!address.startsWith('bs1')) {
      return false;
    }

    // Check length (Bech32 addresses are typically between 42-62 chars)
    if (address.length < 42 || address.length > 62) {
      return false;
    }

    // Check for valid Bech32 characters (lowercase alphanumeric, excluding 1, b, i, o)
    final validChars = RegExp(r'^bs1[ac-hj-np-z02-9]+$');
    if (!validChars.hasMatch(address.toLowerCase())) {
      return false;
    }

    return true;
  }

  bool _validateInputs() {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);

    // Check address
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter the recipient address.';
      });
      return false;
    }

    // Bitcoin Silver address validation
    if (!_isValidBitcoinSilverAddress(address)) {
      setState(() {
        _errorMessage = 'Invalid address format. Bitcoin Silver addresses should start with "bs1".';
      });
      return false;
    }

    // Check amount
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      setState(() {
        _errorMessage = 'Please enter a valid amount.';
      });
      return false;
    }

    // Check balance
    final balance = walletProvider.balance ?? 0.0;
    if (amount > balance) {
      setState(() {
        _errorMessage = 'Insufficient balance. Available: ${balance.toStringAsFixed(8)} BTCS';
      });
      return false;
    }

    // Check for minimum amount (dust threshold)
    if (amount < 0.00000546) {
      setState(() {
        _errorMessage = 'Amount is below minimum (0.00000546 BTCS).';
      });
      return false;
    }

    // Check if there are pending transactions
    if (walletProvider.hasPendingTransactions) {
      setState(() {
        _errorMessage = 'Please wait for pending transactions to confirm.';
      });
      return false;
    }

    // Check UTXOs
    if (walletProvider.utxos == null || walletProvider.utxos!.isEmpty) {
      setState(() {
        _errorMessage = 'No confirmed UTXOs available. Please wait for confirmations.';
      });
      return false;
    }

    // Check confirmation checkbox
    if (!_isChecked) {
      setState(() {
        _errorMessage = 'Please confirm the transaction details.';
      });
      return false;
    }

    setState(() {
      _errorMessage = '';
    });
    return true;
  }

  Future<void> _send() async {
    if (!_validateInputs()) {
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = '';
    });

    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final address = _addressController.text.trim();
    final amount = double.parse(_amountController.text);

    try {
      // First attempt to send
      final result = await walletProvider.sendTransaction(address, amount);

      if (result['success'] == true) {
        // Success!
        if (mounted) {
          _showSuccessDialog(result['txid'] ?? '', result['fee'] ?? 0.0);
        }

        // Clear form
        setState(() {
          _addressController.clear();
          _amountController.clear();
          _isChecked = false;
          _errorMessage = '';
        });

        // Refresh balance after a delay
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            _refreshBalance();
          }
        });

        return;
      }

      // Handle insufficient fee error
      if (result['suggestedFeeRate'] != null) {
        final suggestedFeeRate = result['suggestedFeeRate'] as double;
        final currentFeeRate = result['currentFeeRate'] ?? 0.00001;

        if (mounted) {
          final shouldRetry = await _showFeeDialog(currentFeeRate, suggestedFeeRate);

          if (shouldRetry) {
            // Retry with suggested fee rate
            setState(() {
              _errorMessage = 'Retrying with higher fee...';
            });

            final retryResult = await walletProvider.sendTransaction(
              address,
              amount,
              feeRate: suggestedFeeRate + 0.00000001, // Add small bump to ensure acceptance
            );

            if (retryResult['success'] == true) {
              if (mounted) {
                _showSuccessDialog(retryResult['txid'] ?? '', retryResult['fee'] ?? 0.0);
              }

              // Clear form
              setState(() {
                _addressController.clear();
                _amountController.clear();
                _isChecked = false;
                _errorMessage = '';
              });

              return;
            } else {
              // Retry failed
              setState(() {
                _errorMessage = retryResult['message'] ?? 'Transaction failed';
              });
            }
          } else {
            // User declined to retry
            setState(() {
              _errorMessage = 'Transaction cancelled. The network requires a higher fee.';
            });
          }
        }
      } else {
        // Other error
        setState(() {
          _errorMessage = result['message'] ?? 'Transaction failed';
        });
      }

    } catch (e) {
      setState(() {
        _errorMessage = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  Future<bool> _showFeeDialog(double currentFee, double suggestedFee) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color.fromARGB(255, 25, 25, 25),
          title: const Text(
            'Network Fee Required',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The network requires a higher fee for this transaction.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Text(
                'Current fee rate: ${currentFee.toStringAsFixed(8)} BTCS/kvB',
                style: const TextStyle(color: Colors.white60),
              ),
              Text(
                'Required fee rate: ${suggestedFee.toStringAsFixed(8)} BTCS/kvB',
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 16),
              const Text(
                'You can either:',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('• Retry with the higher fee (recommended)', style: TextStyle(color: Colors.white60)),
              const Text('• Wait 20-30 minutes for network conditions to improve', style: TextStyle(color: Colors.white60)),
              const Text('• Cancel and try again later', style: TextStyle(color: Colors.white60)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
              ),
              child: const Text('Retry with Higher Fee'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  void _showSuccessDialog(String txid, double fee) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color.fromARGB(255, 25, 25, 25),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text('Transaction Sent!', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your transaction has been broadcast to the network.',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              if (txid.isNotEmpty) ...[
                const Text('Transaction ID:', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                SelectableText(
                  txid,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.cyanAccent),
                ),
                const SizedBox(height: 16),
              ],
              Text('Network fee: ${fee.toStringAsFixed(8)} BTCS', style: const TextStyle(color: Colors.white60)),
              const SizedBox(height: 8),
              const Text(
                'Please wait for network confirmations.',
                style: TextStyle(fontStyle: FontStyle.italic, color: Colors.white54),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Go back to home
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
              ),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Send BTCS',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _isSending ? null : _refreshBalance,
            tooltip: 'Refresh Balance',
          ),
        ],
      ),
      body: Container(
        color: Colors.black,
        constraints: const BoxConstraints.expand(),
        child: Consumer<WalletProvider>(
          builder: (context, walletProvider, child) {
            return Stack(
              children: [
                SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 32.0, left: 16.0, right: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Balance Card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Available Balance',
                                style: TextStyle(color: Colors.white70, fontSize: 14),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${walletProvider.balance?.toStringAsFixed(8) ?? '0.00000000'} BTCS',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (walletProvider.hasPendingTransactions) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.access_time, color: Colors.orange, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${walletProvider.pendingTransactionsCount} pending',
                                        style: const TextStyle(color: Colors.orange, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Recipient Address Field
                        TextField(
                          controller: _addressController,
                          enabled: !_isSending,
                          decoration: InputDecoration(
                            labelText: 'Recipient Address (bs1...)',
                            labelStyle: const TextStyle(color: Colors.white70),
                            hintText: 'bs1q...',
                            hintStyle: const TextStyle(color: Colors.white30),
                            filled: true,
                            fillColor: Colors.black,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: const BorderSide(color: Colors.white, width: 1.0),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.0),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.0),
                              borderSide: const BorderSide(color: Colors.white24, width: 1.0),
                            ),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.contacts, color: Colors.cyanAccent),
                                  onPressed: _isSending ? null : () async {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => AddressbookView(
                                          selectionMode: true,
                                          onAddressSelected: (address, username) {
                                            setState(() {
                                              _addressController.text = address;
                                              _errorMessage = '';
                                            });
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Selected @$username'),
                                                backgroundColor: const Color(0xFF2A2A2A),
                                                duration: const Duration(seconds: 2),
                                                behavior: SnackBarBehavior.floating,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.qr_code_scanner, color: Colors.white),
                                  onPressed: _isSending ? null : () async {
                                    final scannedAddress = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const ScannerView(),
                                      ),
                                    );
                                    if (scannedAddress != null) {
                                      setState(() {
                                        _addressController.text = scannedAddress;
                                        _errorMessage = '';
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                          style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                        ),
                        const SizedBox(height: 20),

                        // Amount Field
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _amountController,
                                enabled: !_isSending,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: 'Amount (BTCS)',
                                  labelStyle: const TextStyle(color: Colors.white70),
                                  filled: true,
                                  fillColor: Colors.black,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                    borderSide: const BorderSide(color: Colors.white, width: 1.0),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                    borderSide: const BorderSide(color: Colors.cyanAccent, width: 1.0),
                                  ),
                                  disabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8.0),
                                    borderSide: const BorderSide(color: Colors.white24, width: 1.0),
                                  ),
                                ),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ButtonWidget(
                              text: 'Max',
                              isPrimary: false,
                              onPressed: _isSending ? null : _setMaxAmount,
                            ),
                          ],
                        ),

                        // Error Message
                        if (_errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: Colors.red, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),

                        // Information Text
                        const Text(
                          'To send Bitcoin Silver, enter the recipient\'s bs1 address and the amount. Ensure you have enough balance to cover the transaction fee.',
                          style: TextStyle(color: Colors.white54),
                        ),

                        const SizedBox(height: 20),

                        // Confirmation Checkbox
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: _isChecked,
                              onChanged: _isSending ? null : (bool? value) {
                                setState(() {
                                  _isChecked = value ?? false;
                                  if (_isChecked) {
                                    _errorMessage = '';
                                  }
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

                        // Send Button
                        ButtonWidget(
                          text: _isSending ? 'Sending...' : 'Send Transaction',
                          isPrimary: true,
                          onPressed: _isSending ? null : _send,
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),

                // Loading Overlay
                if (walletProvider.isLoading || _isSending)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.cyanAccent),
                          SizedBox(height: 16),
                          Text(
                            'Processing...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}