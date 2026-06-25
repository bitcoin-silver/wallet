import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
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
  final TextEditingController _manualFeeController = TextEditingController();

  bool _isChecked = false;
  bool _advancedSend = false;
  String _errorMessage = '';
  bool _isSending = false;
  bool? _addressValid;
  bool _isValidatingAddress = false;
  Timer? _addressDebounce;

  @override
  void initState() {
    super.initState();
    // Fetch fresh balance on init
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _refreshBalance();
      if (!mounted) return;
      await Provider.of<WalletProvider>(context, listen: false).fetchFeeRate();
    });
  }

  @override
  void dispose() {
    _addressDebounce?.cancel();
    _addressController.dispose();
    _amountController.dispose();
    _manualFeeController.dispose();
    super.dispose();
  }

  Future<void> _refreshBalance() async {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    await walletProvider.fetchUtxos(force: true);
  }

  void _scheduleAddressValidation(String rawValue) {
    _addressDebounce?.cancel();
    final value = rawValue.trim();

    setState(() {
      _addressValid = null;
      _isValidatingAddress = value.isNotEmpty;
      _errorMessage = '';
    });

    if (value.isEmpty) {
      return;
    }

    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    _addressDebounce = Timer(const Duration(milliseconds: 700), () async {
      final valid = await walletProvider.validateAddress(value);
      if (!mounted) return;
      setState(() {
        _addressValid = valid;
        _isValidatingAddress = false;
      });
    });
  }

  void _setMaxAmount() {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final balance = _advancedSend && walletProvider.selectedUtxoCount > 0
        ? walletProvider.selectedUtxoTotal
        : (walletProvider.balance ?? 0.0);

    // Leave some for fees (rough estimate)
    final fallbackFee = walletProvider.feeEstimateAvailable
      ? walletProvider.estimatedSimpleFee
      : 0.00001;
    final maxAmount = balance > fallbackFee ? balance - fallbackFee : 0.0;

    setState(() {
      _amountController.text = maxAmount.toStringAsFixed(8);
      _errorMessage = '';
    });
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

    // Address validation from RPC checker
    if (_addressValid == false) {
      setState(() {
        _errorMessage = 'Invalid address.';
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
    walletProvider.clearMessage();
    final address = _addressController.text.trim();
    final amount = double.parse(_amountController.text);
    final selectedUtxos = _advancedSend && walletProvider.selectedUtxoCount > 0
      ? walletProvider.selectedUtxoList
      : null;

    final bool initialFeeEstablishedByEstimator = walletProvider.feeEstimateAvailable;
    double? sendFeeRate;

    if (initialFeeEstablishedByEstimator) {
      sendFeeRate = walletProvider.feeRate;
    } else {
      final manualFeeRate = await _showManualFeeDialog(walletProvider);
      if (manualFeeRate == null) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Transaction cancelled. A valid fee rate is required.';
            _isSending = false;
          });
        }
        return;
      }
      sendFeeRate = manualFeeRate;
    }

    try {
      // First attempt to send
      final result = await walletProvider.sendTransaction(
        address,
        amount,
        feeRate: sendFeeRate,
        preSelectedUtxos: selectedUtxos,
      );

      if (result['success'] == true) {
        // Success!
        if (mounted) {
          _showSuccessDialog(result['txid'] ?? '', result['fee'] ?? 0.0);
        }

        // Clear form
        if (mounted) {
          setState(() {
            _addressController.clear();
            _amountController.clear();
            _isChecked = false;
            _addressValid = null;
            _errorMessage = '';
          });
        }

        walletProvider.resetCoinControl();
        if (mounted) {
          setState(() {
            _advancedSend = false;
          });
        }

        // Refresh balance after a delay - capture provider reference before delay
        final provider = walletProvider;
        Future.delayed(const Duration(seconds: 3), () async {
          if (mounted) {
            await provider.fetchUtxos(force: true);
          }
        });

        return;
      }

      // Handle insufficient fee error
      if (initialFeeEstablishedByEstimator && result['suggestedFeeRate'] != null) {
        final suggestedFeeRate = (result['suggestedFeeRate'] as num).toDouble();
        final currentFeeRate = (result['currentFeeRate'] as num?)?.toDouble() ?? 0.00001;

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
              preSelectedUtxos: selectedUtxos,
            );

            if (retryResult['success'] == true) {
              if (mounted) {
                _showSuccessDialog(retryResult['txid'] ?? '', retryResult['fee'] ?? 0.0);
              }

              // Clear form
              if (mounted) {
                setState(() {
                  _addressController.clear();
                  _amountController.clear();
                  _isChecked = false;
                  _addressValid = null;
                  _errorMessage = '';
                });
              }

              walletProvider.resetCoinControl();
              if (mounted) {
                setState(() {
                  _advancedSend = false;
                });
              }

              return;
            } else {
              // Retry failed
              if (mounted) {
                setState(() {
                  _errorMessage = retryResult['message'] ?? 'Transaction failed';
                });
              }
            }
          } else {
            // User declined to retry
            if (mounted) {
              setState(() {
                _errorMessage = 'Transaction cancelled. The network requires a higher fee.';
              });
            }
          }
        }
      } else {
        // Other error
        if (mounted) {
          setState(() {
            _errorMessage = result['message'] ?? 'Transaction failed';
          });
        }
      }

    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error: ${e.toString()}';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  double _satVbToBtcsKvB(double satVb) {
    return satVb * 0.00001;
  }

  Future<double?> _showManualFeeDialog(WalletProvider provider) async {
    bool useSatVb = true;

    final lowBtcsKvB = 0.085;
    final highBtcsKvB = 0.10;
    final lowSatVb = lowBtcsKvB / 0.00001;
    final highSatVb = highBtcsKvB / 0.00001;

    _manualFeeController.text = lowSatVb.toStringAsFixed(2);

    final feeRate = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String? validationError;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color.fromARGB(255, 25, 25, 25),
              title: const Text('Manual Network Fee Required', style: TextStyle(color: Colors.white)),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.65,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          provider.feeEstimateError ??
                              'Automatic fee estimation is currently unavailable.',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Choose based on network conditions:',
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Low traffic: $lowSatVb sat/vB (${lowBtcsKvB.toStringAsFixed(8)} BTCS/kvB), slower confirmation',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'High traffic: $highSatVb sat/vB (${highBtcsKvB.toStringAsFixed(8)} BTCS/kvB), faster confirmation',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(value: true, label: Text('sat/vB')),
                      ButtonSegment<bool>(value: false, label: Text('BTCS/kvB')),
                    ],
                    selected: {useSatVb},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      final next = selection.first;
                      if (next == useSatVb) return;

                      final parsed = double.tryParse(_manualFeeController.text.trim());
                      if (parsed != null && parsed > 0) {
                        final converted = next
                            ? parsed / 0.00001
                            : _satVbToBtcsKvB(parsed);
                        _manualFeeController.text = next
                            ? converted.toStringAsFixed(2)
                            : converted.toStringAsFixed(8);
                      }

                      setDialogState(() {
                        useSatVb = next;
                        validationError = null;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _manualFeeController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: useSatVb ? 'Fee rate (sat/vB)' : 'Fee rate (BTCS/kvB)',
                      labelStyle: const TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Colors.black,
                      errorText: validationError,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: const BorderSide(color: Colors.cyanAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          _manualFeeController.text = useSatVb
                              ? lowSatVb.toStringAsFixed(2)
                              : lowBtcsKvB.toStringAsFixed(8);
                          setDialogState(() {
                            validationError = null;
                          });
                        },
                        child: const Text('Use Low'),
                      ),
                      TextButton(
                        onPressed: () {
                          _manualFeeController.text = useSatVb
                              ? highSatVb.toStringAsFixed(2)
                              : highBtcsKvB.toStringAsFixed(8);
                          setDialogState(() {
                            validationError = null;
                          });
                        },
                        child: const Text('Use High'),
                      ),
                    ],
                  ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final parsed = double.tryParse(_manualFeeController.text.trim());
                    if (parsed == null || parsed <= 0) {
                      setDialogState(() {
                        validationError = 'Enter a valid positive fee rate.';
                      });
                      return;
                    }

                    final btcsKvB = useSatVb ? _satVbToBtcsKvB(parsed) : parsed;
                    if (btcsKvB <= 0) {
                      setDialogState(() {
                        validationError = 'Fee rate must be greater than zero.';
                      });
                      return;
                    }

                    Navigator.of(context).pop(btcsKvB);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyanAccent,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('Use This Fee'),
                ),
              ],
            );
          },
        );
      },
    );
    return feeRate;
  }

  String? _amountError(WalletProvider provider) {
    final text = _amountController.text.trim();
    if (text.isEmpty) return null;

    final value = double.tryParse(text);
    if (value == null) return 'Invalid number';
    if (value <= 0) return 'Amount must be greater than zero';
    if (value < 0.00000546) return 'Amount below dust threshold (0.00000546 BTCS)';

    if (_advancedSend && provider.selectedUtxoCount > 0 && value > provider.selectedUtxoTotal) {
      return 'Exceeds selected inputs (${provider.selectedUtxoTotal.toStringAsFixed(8)} BTCS)';
    }

    if (!_advancedSend && value > (provider.balance ?? 0.0)) {
      return 'Exceeds available balance';
    }

    return null;
  }

  void _syncAmountToSelection(WalletProvider provider) {
    if (!_advancedSend) return;
    final total = provider.selectedUtxoTotal;
    _amountController.text = total > 0 ? total.toStringAsFixed(8) : '';
  }

  Widget _buildUtxoSelector(WalletProvider provider) {
    if (provider.isLoadingUtxos) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: CircularProgressIndicator(color: Colors.cyanAccent),
        ),
      );
    }

    if (provider.availableUtxos.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No confirmed UTXOs found.', style: TextStyle(color: Colors.white54)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select Inputs (${provider.availableUtxos.length} total)',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      provider.selectAllUtxos();
                      _syncAmountToSelection(provider);
                    },
                    child: const Text('All'),
                  ),
                  TextButton(
                    onPressed: () {
                      provider.clearUtxoSelection();
                      _syncAmountToSelection(provider);
                    },
                    child: const Text('None'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (provider.selectedUtxoCount > 0)
            Text(
              '${provider.selectedUtxoCount} selected, total ${provider.selectedUtxoTotal.toStringAsFixed(8)} BTCS',
              style: const TextStyle(color: Colors.amber, fontSize: 12),
            ),
          const SizedBox(height: 8),
          SizedBox(
            height: 240,
            child: ListView.builder(
              itemCount: provider.currentPageUtxos.length,
              itemBuilder: (context, index) {
                final globalIndex = (provider.utxoPage * 15) + index;
                final utxo = provider.currentPageUtxos[index];
                final key = '${utxo['txid']}:${utxo['vout']}';
                final isSelected = provider.selectedUtxoKeys.contains(key);
                final txid = utxo['txid'] as String;
                final short = '${txid.substring(0, 8)}...${txid.substring(txid.length - 6)}:${utxo['vout']}';

                return Material(
                  type: MaterialType.transparency,
                  child: CheckboxListTile(
                    dense: true,
                    value: isSelected,
                    onChanged: (_) {
                      provider.toggleUtxo(key);
                      _syncAmountToSelection(provider);
                    },
                    title: Text(short, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12)),
                    subtitle: Text(
                      '#${globalIndex + 1} | Amount: ${(utxo['amount'] as num).toStringAsFixed(8)} BTCS | Conf: ${utxo['confirmations']}',
                      style: const TextStyle(color: Colors.white60, fontSize: 11),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: Colors.cyanAccent,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          if (provider.utxoPageCount > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: provider.utxoPage > 0
                      ? () => provider.setUtxoPage(provider.utxoPage - 1)
                      : null,
                  child: const Text('Prev'),
                ),
                Text(
                  'Page ${provider.utxoPage + 1} / ${provider.utxoPageCount}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                TextButton(
                  onPressed: provider.utxoPage < provider.utxoPageCount - 1
                      ? () => provider.setUtxoPage(provider.utxoPage + 1)
                      : null,
                  child: const Text('Next'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildFeeEstimate(WalletProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Est. fee: ${provider.estimatedFee.toStringAsFixed(8)} BTCS',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          Text('Net send: ${provider.estimatedNetSend.toStringAsFixed(8)} BTCS',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
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
            final amountErr = _amountError(walletProvider);
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
                            color: Colors.white.withValues(alpha: 0.1),
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
                                    color: Colors.orange.withValues(alpha: 0.2),
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

                        if (walletProvider.message.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: walletProvider.message.contains('❌')
                                  ? Colors.red.withValues(alpha: 0.12)
                                  : walletProvider.message.contains('⚠️')
                                      ? Colors.orange.withValues(alpha: 0.12)
                                      : Colors.green.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: walletProvider.message.contains('❌')
                                    ? Colors.red.withValues(alpha: 0.35)
                                    : walletProvider.message.contains('⚠️')
                                        ? Colors.orange.withValues(alpha: 0.35)
                                        : Colors.green.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              walletProvider.message,
                              style: const TextStyle(color: Colors.white),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Send Mode', style: TextStyle(color: Colors.white70)),
                            ToggleButtons(
                              isSelected: [!_advancedSend, _advancedSend],
                              onPressed: _isSending
                                  ? null
                                  : (index) async {
                                      final goAdvanced = index == 1;
                                      setState(() {
                                        _advancedSend = goAdvanced;
                                        _errorMessage = '';
                                      });

                                      if (goAdvanced) {
                                        await walletProvider.fetchUtxosForCoinControl();
                                      } else {
                                        walletProvider.resetCoinControl();
                                      }
                                    },
                              borderRadius: BorderRadius.circular(8),
                              children: const [
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('Simple'),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Text('Advanced'),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Recipient Address Field
                        TextField(
                          controller: _addressController,
                          onChanged: _scheduleAddressValidation,
                          enabled: !_isSending,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.visiblePassword,
                          textCapitalization: TextCapitalization.none,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Za-z]')),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Recipient Address (bs1...)',
                            errorText: _addressValid == false ? 'Invalid address' : null,
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
                                            });
                                            _scheduleAddressValidation(address);
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
                                      });
                                      _scheduleAddressValidation(scannedAddress);
                                    }
                                  },
                                ),
                                if (_isValidatingAddress)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 12),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  )
                                else if (_addressValid != null)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Icon(
                                      _addressValid! ? Icons.check_circle : Icons.cancel,
                                      color: _addressValid! ? Colors.green : Colors.red,
                                    ),
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
                                  errorText: amountErr,
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

                        const SizedBox(height: 8),

                        Builder(
                          builder: (context) {
                            final fee = _advancedSend && walletProvider.selectedUtxoCount > 0
                                ? walletProvider.estimatedFee
                                : walletProvider.estimatedSimpleFee;
                            final label = _advancedSend && walletProvider.selectedUtxoCount > 0
                                ? 'Est. fee'
                                : 'Est. fee (typical tx)';
                            if (fee <= 0) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$label: ${fee.toStringAsFixed(8)} BTCS',
                                    style: const TextStyle(fontSize: 12, color: Colors.white60),
                                  ),
                                  if (walletProvider.isFeeEstimateLoading)
                                    const Padding(
                                      padding: EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white38,
                                            ),
                                          ),
                                          SizedBox(width: 6),
                                          Text(
                                            'Checking network fee estimate...',
                                            style: TextStyle(fontSize: 11, color: Colors.white54),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (!walletProvider.isFeeEstimateLoading &&
                                      !walletProvider.feeEstimateAvailable)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.warning_amber_rounded,
                                            color: Colors.amberAccent,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Automatic fee estimate unavailable. You will be asked to enter low/high manual fee on send.',
                                              style: const TextStyle(fontSize: 11, color: Colors.amberAccent),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),

                        if (_advancedSend) ...[
                          const SizedBox(height: 16),
                          _buildUtxoSelector(walletProvider),
                        ],

                        if (_advancedSend && walletProvider.selectedUtxoCount > 0) ...[
                          const SizedBox(height: 12),
                          _buildFeeEstimate(walletProvider),
                        ],

                        // Error Message
                        if (_errorMessage.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
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
                          onPressed: _isSending || amountErr != null || _isValidatingAddress || _addressController.text.trim().isEmpty || _addressValid == false
                              ? null
                              : _send,
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