import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:bitcoinsilver_wallet/models/addressbook_entry.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/views/home/addressbook_view.dart';
import 'package:bitcoinsilver_wallet/views/home/scanner_view.dart';
import 'package:bitcoinsilver_wallet/widgets/button_widget.dart';

class SendView extends StatefulWidget {
  const SendView({super.key});

  @override
  State<SendView> createState() => _SendViewState();
}

class _SendViewState extends State<SendView> {
  static const int _satsPerBtcs = 100000000;

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

  int _btcsToSats(double amount) => (amount * _satsPerBtcs).round();
  double _satsToBtcs(int sats) => sats / _satsPerBtcs;
  double _btcsKvBToSatVb(double btcsKvB) => btcsKvB / 0.00001;

  String _formatDecimal(double value, {int maxDecimals = 8}) {
    final fixed = value.toStringAsFixed(maxDecimals);
    final trimmed = fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return trimmed.isEmpty ? '0' : trimmed;
  }

  String _formatSatVb(double btcsKvB) =>
      _formatDecimal(_btcsKvBToSatVb(btcsKvB), maxDecimals: 6);

  String _feeSourceLabel(WalletProvider provider) {
    switch (provider.feeRateSource) {
      case 'manual':
        return 'Manual';
      case 'clamped':
        return 'Clamped to Baseline';
      case 'baseline':
        return 'Node Baseline';
      case 'estimated':
        return 'Node Estimate';
      default:
        return 'Not Ready';
    }
  }

  int _selectedUtxoTotalSats(WalletProvider provider) {
    return provider.selectedUtxoList.fold(
      0,
      (sum, u) => sum + _btcsToSats((u['amount'] as num).toDouble()),
    );
  }

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

  Future<void> _pickAddressFromAddressbook() async {
    if (_isSending) return;

    final selected = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddressbookView(selectionMode: true),
      ),
    );

    if (!mounted || selected == null || selected is! AddressbookEntry) {
      return;
    }

    setState(() {
      _addressController.text = selected.address;
      _errorMessage = '';
    });
    _scheduleAddressValidation(selected.address);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Selected ${selected.label}'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2A2A2A),
      ),
    );
  }

  void _setMaxAmount() {
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    // Use full spendable amount in satoshis so the send service enters sweep
    // mode and computes the exact final sendable value after fee.
    final maxSats = _advancedSend && walletProvider.selectedUtxoCount > 0
        ? _selectedUtxoTotalSats(walletProvider)
        : _btcsToSats(walletProvider.balance ?? 0.0);
    final maxAmount = _satsToBtcs(maxSats > 0 ? maxSats : 0);

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

    // Use the same amount rules shown in the inline amount validator.
    final amountError = _amountError(walletProvider);
    if (amountError != null) {
      setState(() {
        _errorMessage = amountError;
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

    double? sendFeeRate;

    if (walletProvider.feeRateReady) {
      sendFeeRate = walletProvider.feeRate;
    } else {
      await walletProvider.fetchFeeRate();
      if (walletProvider.feeRateReady) {
        sendFeeRate = walletProvider.feeRate;
      }
    }

    if (sendFeeRate == null) {
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
      walletProvider.setManualFeeRate(manualFeeRate);
      sendFeeRate = manualFeeRate;
    }

    final agreed = await _showPreSendConfirmDialog(
      provider: walletProvider,
      toAddress: address,
      amount: amount,
    );
    if (!agreed) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _errorMessage = 'Transaction cancelled.';
        });
      }
      return;
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
          await _showPostSendAckDialog(
            txid: result['txid'] ?? '',
            amount: amount,
            fee: (result['fee'] as num?)?.toDouble() ?? 0.0,
          );
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
      if (result['suggestedFeeRate'] != null) {
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
                await _showPostSendAckDialog(
                  txid: retryResult['txid'] ?? '',
                  amount: amount,
                  fee: (retryResult['fee'] as num?)?.toDouble() ?? 0.0,
                );
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

    const lowBtcsKvB = 0.00000226;
    const highBtcsKvB = 0.0004;
    final lowSatVb = lowBtcsKvB / 0.00001;
    final highSatVb = highBtcsKvB / 0.00001;

    _manualFeeController.text = _formatDecimal(lowSatVb, maxDecimals: 4);

    final feeRate = await showDialog<double>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String? validationError;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color.fromARGB(255, 25, 25, 25),
              title: const Text('Manual Network Fee', style: TextStyle(color: Colors.white)),
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
                              'A too low fee may result in the transaction being rejected by the network.',
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
                          'Low traffic: ${_formatDecimal(lowSatVb, maxDecimals: 4)} sat/vB (${lowBtcsKvB.toStringAsFixed(8)} BTCS/kvB), slower confirmation',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'High traffic: ${_formatDecimal(highSatVb, maxDecimals: 4)} sat/vB (${highBtcsKvB.toStringAsFixed(8)} BTCS/kvB), faster confirmation',
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
                          ? _formatDecimal(converted, maxDecimals: 4)
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
                              ? _formatDecimal(lowSatVb, maxDecimals: 4)
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
                              ? _formatDecimal(highSatVb, maxDecimals: 4)
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

    final valueSats = _btcsToSats(value);
    final spendableSats = _advancedSend && provider.selectedUtxoCount > 0
        ? _selectedUtxoTotalSats(provider)
        : _btcsToSats(provider.balance ?? 0.0);

    if (valueSats > spendableSats) {
      if (_advancedSend && provider.selectedUtxoCount > 0) {
        return 'Exceeds selected inputs (${_satsToBtcs(spendableSats).toStringAsFixed(8)} BTCS)';
      }
      return 'Exceeds available balance';
    }

    return null;
  }

  void _syncAmountToSelection(WalletProvider provider) {
    if (!_advancedSend) return;
    final total = _satsToBtcs(_selectedUtxoTotalSats(provider));
    _amountController.text = total > 0 ? total.toStringAsFixed(8) : '';
  }

  ({double fee, int? inputCount, bool amountAware}) _estimateSimpleModeFee(
    WalletProvider provider,
  ) {
    final feeRate = provider.feeRate;
    if (feeRate <= 0) {
      return (fee: 0.0, inputCount: null, amountAware: false);
    }

    final confirmedUtxos = (provider.utxos ?? const [])
        .whereType<Map>()
        .where((u) {
          final txid = u['txid'];
          final confirmations = u['confirmations'] as int? ?? 0;
          return txid != 'pending_marker' && confirmations > 0;
        })
        .map((u) => (u['amount'] as num?)?.toDouble() ?? 0.0)
        .where((a) => a > 0)
        .toList()
      ..sort((a, b) => b.compareTo(a));

    final enteredAmount = double.tryParse(_amountController.text.trim());
    final hasAmount = enteredAmount != null && enteredAmount > 0;

    int txSizeForInputs(int inputs) => 11 + (inputs * 68) + 31 + 31;
    double feeForInputs(int inputs) =>
        double.parse((feeRate * txSizeForInputs(inputs) / 1000).toStringAsFixed(8));

    if (!hasAmount || confirmedUtxos.isEmpty) {
      final fallbackInputs = confirmedUtxos.isEmpty
          ? 2
          : (confirmedUtxos.length >= 2 ? 2 : 1);
      return (
        fee: feeForInputs(fallbackInputs),
        inputCount: fallbackInputs,
        amountAware: false,
      );
    }

    int inputsNeededFor(double requiredTotal) {
      double total = 0.0;
      int used = 0;
      for (final amount in confirmedUtxos) {
        total += amount;
        used += 1;
        if (total >= requiredTotal) {
          return used;
        }
      }
      return -1;
    }

    var guessInputs = 1;
    for (var i = 0; i < 8; i++) {
      final fee = feeForInputs(guessInputs);
      final needed = inputsNeededFor(enteredAmount + fee);

      if (needed <= 0) {
        final fallbackInputs = confirmedUtxos.length >= 2 ? 2 : 1;
        return (
          fee: feeForInputs(fallbackInputs),
          inputCount: fallbackInputs,
          amountAware: false,
        );
      }

      if (needed == guessInputs) {
        return (fee: fee, inputCount: guessInputs, amountAware: true);
      }

      guessInputs = needed;
    }

    return (
      fee: feeForInputs(guessInputs),
      inputCount: guessInputs,
      amountAware: true,
    );
  }

  ({double fee, bool hasExactCoinControlFee, ({double fee, int? inputCount, bool amountAware}) simpleEstimate})
      _currentDisplayedFee(WalletProvider provider) {
    final hasExactCoinControlFee = _advancedSend && provider.selectedUtxoCount > 0;
    final simpleEstimate = _estimateSimpleModeFee(provider);
    final fee = hasExactCoinControlFee ? provider.estimatedFee : simpleEstimate.fee;
    return (
      fee: fee,
      hasExactCoinControlFee: hasExactCoinControlFee,
      simpleEstimate: simpleEstimate,
    );
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
              '${provider.selectedUtxoCount} selected, total ${_satsToBtcs(_selectedUtxoTotalSats(provider)).toStringAsFixed(8)} BTCS',
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

  Widget _buildFeeEstimate(
    WalletProvider provider,
    ({double fee, bool hasExactCoinControlFee, ({double fee, int? inputCount, bool amountAware}) simpleEstimate})
        feeSnapshot,
  ) {
    final hasExactCoinControlFee = feeSnapshot.hasExactCoinControlFee;
    final simpleEstimate = feeSnapshot.simpleEstimate;
    final fee = feeSnapshot.fee;
    final detailsLabel = hasExactCoinControlFee
        ? 'Size-aware estimate for ${provider.selectedUtxoCount} selected input(s)'
        : _advancedSend
            ? 'Typical fee fallback until inputs are selected'
        : simpleEstimate.amountAware
          ? 'Amount-aware estimate using ~${simpleEstimate.inputCount ?? 1} input(s)'
          : 'Simple mode estimate using ~${simpleEstimate.inputCount ?? 2} input(s)';
    final detailsColor = hasExactCoinControlFee
      ? Colors.greenAccent
      : _advancedSend
        ? Colors.amberAccent
      : simpleEstimate.amountAware
        ? Colors.white70
        : Colors.white54;
    if (fee <= 0) return const SizedBox.shrink();

    final sourceText = _feeSourceLabel(provider);
    final sourceColor = _feeSourceColor(provider);
    final rateColor = sourceColor.withValues(alpha: 0.85);
    final rateText =
        '${provider.feeRate.toStringAsFixed(8)} BTCS/kvB (${_formatSatVb(provider.feeRate)} sat/vB)';
    final netAfterFeeText = provider.estimatedNetSend > 0
        ? '${provider.estimatedNetSend.toStringAsFixed(8)} BTCS'
        : '-';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Estimated Network Fee',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            '${fee.toStringAsFixed(8)} BTCS',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Fee Source',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              Text(
                sourceText,
                style: TextStyle(
                  color: sourceColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Fee Rate',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              Expanded(
                child: Text(
                  rateText,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: rateColor, fontSize: 12),
                ),
              ),
            ],
          ),
          if (hasExactCoinControlFee) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Net Send After Fee',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                Text(
                  netAfterFeeText,
                  style: const TextStyle(color: Colors.greenAccent, fontSize: 12),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 8),
          Text(
            detailsLabel,
            style: TextStyle(color: detailsColor, fontSize: 11),
          ),
        ],
      ),
    );
  }

  bool _isNodeFeeSource(WalletProvider provider) {
    return provider.feeRateReady &&
        (provider.feeRateSource == 'estimated' ||
            provider.feeRateSource == 'baseline' ||
            provider.feeRateSource == 'clamped');
  }

  Color _feeSourceColor(WalletProvider provider) {
    if (provider.feeRateSource == 'manual') {
      return Colors.cyanAccent;
    }
    if (_isNodeFeeSource(provider)) {
      return Colors.greenAccent;
    }
    return Colors.amberAccent;
  }

  Widget _buildFeeSourceSelector(WalletProvider provider) {
    final manualSelected = provider.feeRateSource == 'manual';
    final nodeSelected = _isNodeFeeSource(provider);
    final currentColor = _feeSourceColor(provider);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Fee Source',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              Text(
                _feeSourceLabel(provider),
                style: TextStyle(color: currentColor, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSending
                      ? null
                      : () async {
                          final manualFeeRate = await _showManualFeeDialog(provider);
                          if (manualFeeRate != null) {
                            provider.setManualFeeRate(manualFeeRate);
                          }
                        },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: manualSelected ? Colors.cyanAccent : Colors.white30,
                      width: manualSelected ? 1.6 : 1.0,
                    ),
                    backgroundColor: manualSelected
                        ? Colors.cyanAccent.withValues(alpha: 0.16)
                        : Colors.transparent,
                    foregroundColor: manualSelected ? Colors.cyanAccent : Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Manual'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSending || provider.isFeeEstimateLoading
                      ? null
                      : () => provider.fetchFeeRate(),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: nodeSelected ? Colors.greenAccent : Colors.white30,
                      width: nodeSelected ? 1.6 : 1.0,
                    ),
                    backgroundColor: nodeSelected
                        ? Colors.greenAccent.withValues(alpha: 0.14)
                        : Colors.transparent,
                    foregroundColor: nodeSelected ? Colors.greenAccent : Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text('Auto (Node Fee)'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSendPreview(
    WalletProvider provider,
    ({double fee, bool hasExactCoinControlFee, ({double fee, int? inputCount, bool amountAware}) simpleEstimate})
        feeSnapshot,
  ) {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) return const SizedBox.shrink();

    final hasSelectedInputs = feeSnapshot.hasExactCoinControlFee;
    final fee = feeSnapshot.fee;

    final selectedInputsSats = hasSelectedInputs ? _selectedUtxoTotalSats(provider) : 0;
    final autoSpendableSats = _btcsToSats(provider.balance ?? 0.0);
    final amountSats = _btcsToSats(amount);
    final feeSats = _btcsToSats(fee);
    final expectedChangeSats = hasSelectedInputs
      ? (selectedInputsSats - amountSats - feeSats)
      : (autoSpendableSats - amountSats - feeSats);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Transaction Preview',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Selected Inputs', style: TextStyle(color: Colors.white60, fontSize: 12)),
              Text(
                hasSelectedInputs
                    ? '${_satsToBtcs(selectedInputsSats).toStringAsFixed(8)} BTCS'
                    : 'Auto',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Send Amount', style: TextStyle(color: Colors.white60, fontSize: 12)),
              Text(
                '${_satsToBtcs(amountSats).toStringAsFixed(8)} BTCS',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Estimated Fee', style: TextStyle(color: Colors.white60, fontSize: 12)),
              Text(
                '${fee.toStringAsFixed(8)} BTCS',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Fee Source', style: TextStyle(color: Colors.white60, fontSize: 12)),
              Text(
                _feeSourceLabel(provider),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Fee Rate', style: TextStyle(color: Colors.white60, fontSize: 12)),
              Text(
                '${provider.feeRate.toStringAsFixed(8)} BTCS/kvB (${_formatSatVb(provider.feeRate)} sat/vB)',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Expected Change', style: TextStyle(color: Colors.white60, fontSize: 12)),
              Text(
                '${_satsToBtcs(expectedChangeSats > 0 ? expectedChangeSats : 0).toStringAsFixed(8)} BTCS',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
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

  Future<bool> _showPreSendConfirmDialog({
    required WalletProvider provider,
    required String toAddress,
    required double amount,
  }) async {
    final hasSelectedInputs = _advancedSend && provider.selectedUtxoCount > 0;
    final simpleEstimate = _estimateSimpleModeFee(provider);
    final estimatedFee = hasSelectedInputs ? provider.estimatedFee : simpleEstimate.fee;

    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color.fromARGB(255, 25, 25, 25),
          title: const Text('Confirm Transaction', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('To: $toAddress', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(height: 8),
              Text('Amount: ${amount.toStringAsFixed(8)} BTCS', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              Text('Estimated fee: ${estimatedFee.toStringAsFixed(8)} BTCS', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              Text('Fee source: ${_feeSourceLabel(provider)}', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              Text(
                'Fee rate: ${provider.feeRate.toStringAsFixed(8)} BTCS/kvB (${_formatSatVb(provider.feeRate)} sat/vB)',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Agree & Send'),
            ),
          ],
        );
      },
    );

    return agreed ?? false;
  }

  Future<void> _showPostSendAckDialog({
    required String txid,
    required double amount,
    required double fee,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color.fromARGB(255, 25, 25, 25),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.greenAccent, size: 24),
              SizedBox(width: 8),
              Text('Transaction Sent', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
                ),
                child: const Text(
                  'Broadcasted to network',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Amount Sent', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  Text(
                    '${amount.toStringAsFixed(8)} BTCS',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Network Fee Paid', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  Text(
                    '${fee.toStringAsFixed(8)} BTCS',
                    style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              if (txid.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('TXID', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: SelectableText(
                    txid,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.cyanAccent),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: txid));
                      if (!mounted) return;
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        const SnackBar(content: Text('TXID copied')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy TXID'),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Acknowledge'),
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
      body: SafeArea(
        top: false,
        bottom: true,
        minimum: const EdgeInsets.only(bottom: 8),
        child: Container(
          color: Colors.black,
          constraints: const BoxConstraints.expand(),
          child: Consumer<WalletProvider>(
          builder: (context, walletProvider, child) {
            final amountErr = _amountError(walletProvider);
            final feeSnapshot = _currentDisplayedFee(walletProvider);
            return Stack(
              children: [
                SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: 32.0,
                      left: 16.0,
                      right: 16.0,
                      bottom: 24.0 + MediaQuery.of(context).viewPadding.bottom,
                    ),
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
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.done,
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
                                  icon: const Icon(
                                    Icons.contact_page_rounded,
                                    color: Colors.cyanAccent,
                                  ),
                                  tooltip: 'Choose from Address Book',
                                  onPressed: _isSending ? null : _pickAddressFromAddressbook,
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
                                onChanged: (_) {
                                  setState(() {
                                    _errorMessage = '';
                                  });
                                },
                                enabled: !_isSending,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,8}$')),
                                ],
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

                        const SizedBox(height: 10),
                        _buildFeeSourceSelector(walletProvider),

                        const SizedBox(height: 10),
                        _buildFeeEstimate(walletProvider, feeSnapshot),

                        const SizedBox(height: 8),
                        if (walletProvider.isFeeEstimateLoading)
                          const Padding(
                            padding: EdgeInsets.only(top: 4, left: 4),
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
                            padding: EdgeInsets.only(top: 4, left: 4),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.amberAccent,
                                  size: 14,
                                ),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    walletProvider.feeRateStatusMessage,
                                    style: TextStyle(fontSize: 11, color: Colors.amberAccent),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        if (_advancedSend) ...[
                          const SizedBox(height: 16),
                          _buildUtxoSelector(walletProvider),
                        ],

                        const SizedBox(height: 12),
                        _buildSendPreview(walletProvider, feeSnapshot),

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
                          'To send Bitcoin Silver, enter the recipient\'s bs1 or legacy address and the amount. Ensure you have enough balance to cover the transaction fee.',
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
      ),
    );
  }
}