import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:bitcoinsilver_wallet/models/addressbook_entry.dart';
import 'package:bitcoinsilver_wallet/providers/addressbook_provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/services/payment_request.dart';
import 'package:bitcoinsilver_wallet/views/home/addressbook_view.dart';
import 'package:bitcoinsilver_wallet/views/home/scanner_view.dart';
import 'package:bitcoinsilver_wallet/widgets/button_widget.dart';

class SendView extends StatefulWidget {
  /// Recipient to start with, e.g. when opened from an address book contact.
  final String? initialRecipient;

  const SendView({super.key, this.initialRecipient});

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
  bool _subtractFeeFromAmount = false;
  String _errorMessage = '';
  bool _isSending = false;
  bool? _addressValid;
  bool _isValidatingAddress = false;
  Timer? _addressDebounce;

  // Payment request being paid (scanned or pasted bitcoinsilver: URI or
  // web payment link). Its note is only shown, never sent.
  PaymentRequest? _activeRequest;

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

  String _formatConfirmationsLabel(int confirmations) {
    if (confirmations <= 1) {
      return '$confirmations conf';
    }
    return '${_formatCompactConfirmationCount(confirmations)} conf';
  }

  String _formatCompactConfirmationCount(int confirmations) {
    if (confirmations < 1000) {
      return '$confirmations';
    }

    const suffixes = ['K', 'M', 'B', 'T'];
    double value = confirmations.toDouble();
    var suffixIndex = -1;

    while (value >= 1000 && suffixIndex < suffixes.length - 1) {
      value /= 1000;
      suffixIndex++;
    }

    var compact = value.toStringAsPrecision(3);
    if (compact.contains('.')) {
      compact = compact.replaceFirst(RegExp(r'0+$'), '');
      compact = compact.replaceFirst(RegExp(r'\.$'), '');
    }

    return '$compact${suffixes[suffixIndex]}';
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
    final initialRecipient = widget.initialRecipient?.trim();
    if (initialRecipient != null && initialRecipient.isNotEmpty) {
      _addressController.text = initialRecipient;
      // Validate once the screen is built (setState needs a mounted widget).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleAddressValidation(initialRecipient);
      });
    }
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

  // Recipient field changes: a pasted payment request is split into address
  // and amount; anything else is validated as an address.
  void _onAddressChanged(String value) {
    if (PaymentRequest.looksLikeUri(value)) {
      _applyScannedOrPasted(value);
      return;
    }
    _scheduleAddressValidation(value);
  }

  // Reads a scan or paste. Unreadable requests fall back to the address part,
  // as the scanner did before, and say why.
  void _applyScannedOrPasted(String raw) {
    try {
      _applyPaymentRequest(PaymentRequest.fromText(raw));
    } on FormatException catch (e) {
      final address = ScannerView.addressPart(raw);
      setState(() => _addressController.text = address);
      _scheduleAddressValidation(address);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade800,
      ));
    }
  }

  void _applyPaymentRequest(PaymentRequest request) {
    setState(() {
      _addressController.text = request.address;
      if (request.amountSats != null) {
        _amountController.text = PaymentRequest.formatAmount(request.amountSats!);
      }
    });
    _scheduleAddressValidation(request.address);
    setState(() => _activeRequest = request.isPlainAddress ? null : request);
  }

  static String _labelKey(String label) => PaymentRequest.sanitizeText(label).toLowerCase();

  // The label and note are written by whoever made the request, so they are
  // shown as unverified. Only the address book can vouch for a name: it is
  // shown when the address matches a saved contact, and a request that
  // borrows a saved contact's name for another address gets a warning.
  // Same rules as the web wallet.
  Widget _buildActiveRequestCard(PaymentRequest request) {
    final requested = request.amountSats;
    final entered = PaymentRequest.parseAmount(_amountController.text);
    final amountChanged = requested != null && entered != requested;
    final contacts = Provider.of<AddressbookProvider>(context).entries;
    AddressbookEntry? savedContact;
    AddressbookEntry? nameTwin;
    for (final c in contacts) {
      if (savedContact == null && _normalizeForMatch(c.address) == request.address) savedContact = c;
      if (nameTwin == null && request.label != null && _labelKey(c.label) == _labelKey(request.label!)) {
        nameTwin = c;
      }
    }
    final impersonates = nameTwin != null && _normalizeForMatch(nameTwin.address) != request.address;
    final showClaimedName = request.label != null && (savedContact == null || nameTwin != savedContact);
    final accent = impersonates ? Colors.redAccent : Colors.cyanAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: impersonates ? 0.8 : 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.request_quote, color: Colors.cyanAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  requested == null
                      ? 'Payment request'
                      : 'Payment request: ${PaymentRequest.formatAmount(requested)} BTCS',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
                if (savedContact != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.verified_user, size: 14, color: Colors.greenAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Saved contact: ${savedContact.label}',
                            style: const TextStyle(color: Colors.greenAccent)),
                      ),
                    ],
                  ),
                ],
                if (showClaimedName) ...[
                  const SizedBox(height: 4),
                  Text('Name given in the request (not verified): ${request.label}',
                      style: const TextStyle(color: Colors.white70)),
                ],
                if (impersonates) ...[
                  const SizedBox(height: 6),
                  Text(
                    '⚠ This request uses the name "${nameTwin.label}", but it is NOT the address you saved '
                    'for ${nameTwin.label}. Do not pay unless you are sure who sent it.',
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
                  ),
                ],
                if (request.message != null) ...[
                  const SizedBox(height: 4),
                  Text('Note from the requester: ${request.message}',
                      style: const TextStyle(color: Colors.white70)),
                ],
                const SizedBox(height: 6),
                Text(
                  amountChanged
                      ? 'The amount below differs from the requested amount.'
                      : 'Only pay requests from people you trust. Check the address and amount '
                          'before sending. The note is not sent.',
                  style: TextStyle(
                    fontSize: 12,
                    color: amountChanged ? Colors.amberAccent : Colors.white54,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: Colors.white54),
            tooltip: 'Dismiss request',
            onPressed: () => setState(() => _activeRequest = null),
          ),
        ],
      ),
    );
  }

  static String _normalizeForMatch(String address) {
    final lower = address.trim().toLowerCase();
    return lower.startsWith('bs1') ? lower : address.trim();
  }

  void _scheduleAddressValidation(String rawValue) {
    _addressDebounce?.cancel();
    final value = rawValue.trim();

    setState(() {
      _addressValid = null;
      _isValidatingAddress = value.isNotEmpty;
      _errorMessage = '';
      // The request card must never describe a different recipient.
      if (_activeRequest != null && _normalizeForMatch(value) != _activeRequest!.address) {
        _activeRequest = null;
      }
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
    final enteredAmount = double.parse(_amountController.text);
    final liveFeeSnapshot = _currentDisplayedFee(walletProvider);
    final amount = _effectiveSendAmount(
      provider: walletProvider,
      feeSnapshot: liveFeeSnapshot,
      enteredAmount: enteredAmount,
    );
    if (amount <= 0) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Amount must be greater than estimated fee.';
          _isSending = false;
        });
      }
      return;
    }
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

    var preferBatchSend = true;
    while (mounted) {
      final batchPreview = await walletProvider.assessBatchSendCandidate(
        address,
        amount,
        manualFeeRateCoinPerKb: sendFeeRate,
        preSelectedUtxos: selectedUtxos,
      );
      if (batchPreview['isCandidate'] != true) {
        break;
      }

      final decision = await _showBatchDecisionDialog(
        provider: walletProvider,
        amount: amount,
        preview: batchPreview,
      );
      if (decision == null || decision == 'cancel') {
        if (mounted) {
          setState(() {
            _isSending = false;
            _errorMessage = 'Transaction cancelled.';
          });
        }
        return;
      }

      if (decision == 'manual-fee') {
        final manualFeeRate = await _showManualFeeDialog(walletProvider);
        if (manualFeeRate == null) {
          if (mounted) {
            setState(() {
              _isSending = false;
              _errorMessage = 'Transaction cancelled. A valid fee rate is required.';
            });
          }
          return;
        }
        walletProvider.setManualFeeRate(manualFeeRate);
        sendFeeRate = manualFeeRate;
        continue;
      }

      preferBatchSend = decision == 'batch';
      break;
    }

    final agreed = await _showPreSendConfirmDialog(
      provider: walletProvider,
      toAddress: address,
      enteredAmount: enteredAmount,
      amount: amount,
      subtractFeeFromAmount: _subtractFeeFromAmount,
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
      final result = await walletProvider.sendTransaction(
        address,
        amount,
        feeRate: sendFeeRate,
        preSelectedUtxos: selectedUtxos,
        preferBatchSend: preferBatchSend,
      );

      if (result['success'] != true && result['requiresManualFee'] == true && mounted) {
        final manualFeeRate = await _showManualFeeDialog(walletProvider);
        if (manualFeeRate != null) {
          walletProvider.setManualFeeRate(manualFeeRate);
          final retryResult = await walletProvider.sendTransaction(
            address,
            amount,
            feeRate: manualFeeRate,
            preSelectedUtxos: selectedUtxos,
            preferBatchSend: preferBatchSend,
          );
          if (retryResult['success'] == true) {
            _resetSendForm(walletProvider);
            if (mounted) {
              await _showSendAckFromResult(retryResult, requestedAmount: amount);
            }
          } else if (mounted) {
            setState(() {
              _errorMessage = (retryResult['message'] as String?) ?? 'Transaction failed';
            });
          }
        } else if (mounted) {
          setState(() {
            _errorMessage = 'Transaction cancelled. A valid fee rate is required.';
          });
        }
        return;
      }

      if (result['success'] != true && !preferBatchSend && mounted) {
        final message = (result['message'] as String?) ?? 'Transaction failed.';
        if (_isLikelyBatchFailureMessage(message)) {
          final retryAsBatch = await _showRetryBatchDialog(message: message);
          if (retryAsBatch == true) {
            final retryResult = await walletProvider.sendTransaction(
              address,
              amount,
              feeRate: sendFeeRate,
              preSelectedUtxos: selectedUtxos,
              preferBatchSend: true,
            );
            if (retryResult['success'] == true) {
              _resetSendForm(walletProvider);
              if (mounted) {
                await _showSendAckFromResult(retryResult, requestedAmount: amount);
              }
              return;
            }

            if (mounted) {
              setState(() {
                _errorMessage = (retryResult['message'] as String?) ??
                    'Batch retry failed.';
              });
            }
            return;
          }
        }
      }

      if (result['success'] == true) {
        _resetSendForm(walletProvider);
        if (mounted) {
          await _showSendAckFromResult(result, requestedAmount: amount);
        }

        return;
      }

      // Handle insufficient fee error
      if (result['suggestedFeeRate'] != null) {
        final suggestedFeeRate = (result['suggestedFeeRate'] as num).toDouble();
        final currentFeeRate = (result['currentFeeRate'] as num?)?.toDouble() ?? 0.00001;

        if (mounted) {
          final shouldRetry = await _showFeeDialog(currentFeeRate, suggestedFeeRate);

          if (shouldRetry) {
            setState(() {
              _errorMessage = 'Retrying with higher fee...';
            });

            final retryResult = await walletProvider.sendTransaction(
              address,
              amount,
              feeRate: suggestedFeeRate + 0.00000001,
              preSelectedUtxos: selectedUtxos,
              preferBatchSend: preferBatchSend,
            );

            if (retryResult['success'] == true) {
              _resetSendForm(walletProvider);
              if (mounted) {
                await _showSendAckFromResult(retryResult, requestedAmount: amount);
              }

              return;
            }

            if (mounted) {
              setState(() {
                _errorMessage = retryResult['message'] ?? 'Transaction failed';
              });
            }
          } else {
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

  void _resetSendForm(WalletProvider provider) {
    if (mounted) {
      setState(() {
        _addressController.clear();
        _amountController.clear();
        _isChecked = false;
        _addressValid = null;
        _activeRequest = null;
        _errorMessage = '';
        _advancedSend = false;
        _subtractFeeFromAmount = false;
      });
    }

    provider.resetCoinControl();

    Future.delayed(const Duration(seconds: 3), () async {
      if (mounted) {
        await provider.fetchUtxos(force: true);
      }
    });
  }

  Future<String?> _showBatchDecisionDialog({
    required WalletProvider provider,
    required double amount,
    required Map<String, dynamic> preview,
  }) async {
    String reasonLabel(String reason) {
      switch (reason) {
        case 'sweep-too-large':
          return 'Large sweep detected';
        case 'input-count':
          return 'High input count detected';
        case 'tx-size':
          return 'Large transaction size detected';
        default:
          return 'Batch candidate detected';
      }
    }

    final reason = (preview['reason'] as String?) ?? 'none';
    final predictedInputs = (preview['predictedInputCount'] as int?) ?? 0;
    final predictedVbytes = (preview['predictedVbytes'] as int?) ?? 0;
    final estimatedBatchCount = (preview['estimatedBatchCount'] as int?) ?? 1;
    final estimatedSingleFee = (preview['estimatedSingleFee'] as num?)?.toDouble() ?? 0.0;
    final estimatedTotalBatchFee =
        (preview['estimatedTotalBatchFee'] as num?)?.toDouble() ?? 0.0;
    final estimatedNetDelivered =
        (preview['estimatedNetDelivered'] as num?)?.toDouble() ??
            (amount - estimatedTotalBatchFee);
    final usingManualFee = provider.feeRateSource == 'manual';

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color.fromARGB(255, 25, 25, 25),
          title: const Row(
            children: [
              Icon(Icons.layers_rounded, color: Colors.orangeAccent),
              SizedBox(width: 8),
              Text('Batch Send Suggested', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reasonLabel(reason),
                  style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This transfer may exceed safe single-transaction limits. '
                  'You can batch it into multiple broadcasts or continue with normal send.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Requested amount', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    Text('${amount.toStringAsFixed(8)} BTCS'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Predicted inputs', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    Text('$predictedInputs'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Predicted tx size', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    Text('$predictedVbytes vB'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Estimated batch count', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    Text('$estimatedBatchCount'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Est. single fee', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    Text('${estimatedSingleFee.toStringAsFixed(8)} BTCS'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Est. total batch fee', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    Text('${estimatedTotalBatchFee.toStringAsFixed(8)} BTCS'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Est. net delivered', style: TextStyle(color: Colors.white60, fontSize: 12)),
                    Text('${estimatedNetDelivered.toStringAsFixed(8)} BTCS'),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Estimates may vary depending on final input selection and mempool conditions.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                if (!usingManualFee) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'You are currently using node-estimated fee. For batch sends, consider setting a manual fee first for more predictable total cost.',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'cancel'),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            if (!usingManualFee)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, 'manual-fee'),
                child: const Text('Set Manual Fee'),
              ),
            OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, 'normal'),
              child: const Text('Normal Send'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, 'batch'),
              child: const Text('Batch Send'),
            ),
          ],
        );
      },
    );
  }

  bool _isLikelyBatchFailureMessage(String message) {
    final normalized = message.toLowerCase();
    return normalized.contains('too many') ||
        normalized.contains('tx-size') ||
        normalized.contains('tx size') ||
        normalized.contains('oversize') ||
        normalized.contains('too large') ||
        normalized.contains('too-long-mempool-chain') ||
        normalized.contains('mempool chain') ||
        normalized.contains('non-bip68-final') ||
        normalized.contains('insufficient fee') ||
        normalized.contains('rejecting replacement');
  }

  Future<bool?> _showRetryBatchDialog({required String message}) async {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color.fromARGB(255, 25, 25, 25),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
              SizedBox(width: 8),
              Text('Normal Send Failed', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This failure may be caused by single-transaction size or mempool constraints.',
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(message, style: const TextStyle(color: Colors.white, fontSize: 12)),
              ),
              const SizedBox(height: 10),
              const Text(
                'Retry now using Batch Send?',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
              child: const Text('Retry as Batch'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSendAckFromResult(
    Map<String, dynamic> result, {
    required double requestedAmount,
  }) async {
    final batchTxids = (result['batchTxids'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((txid) => txid.isNotEmpty)
        .toList();
    final batched = (result['batched'] == true) || batchTxids.isNotEmpty;

    if (batched) {
      await _showBatchSendAckDialog(
        txids: batchTxids,
        requestedAmount: requestedAmount,
        grossAmount: (result['grossAmount'] as num?)?.toDouble(),
        totalFee: (result['fee'] as num?)?.toDouble() ?? 0.0,
        netAmount: (result['netAmount'] as num?)?.toDouble(),
      );
      return;
    }

    await _showPostSendAckDialog(
      txid: (result['txid'] as String?) ?? '',
      amount: requestedAmount,
      fee: (result['fee'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Future<void> _showBatchSendAckDialog({
    required List<String> txids,
    required double requestedAmount,
    required double totalFee,
    double? grossAmount,
    double? netAmount,
  }) async {
    final displayedGross = grossAmount ?? requestedAmount;
    final displayedNet = netAmount ?? (displayedGross - totalFee);

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color.fromARGB(255, 25, 25, 25),
          title: const Row(
            children: [
              Icon(Icons.fact_check_rounded, color: Colors.greenAccent, size: 24),
              SizedBox(width: 8),
              Text('Batch Send Complete', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Broadcasted ${txids.length} transaction${txids.length == 1 ? '' : 's'}.',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Requested Amount', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    Text('${requestedAmount.toStringAsFixed(8)} BTCS', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Gross Sent', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    Text('${displayedGross.toStringAsFixed(8)} BTCS', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Fee Paid', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    Text('${totalFee.toStringAsFixed(8)} BTCS', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Estimated Net Delivered', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    Text('${displayedNet.toStringAsFixed(8)} BTCS', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ],
                ),
                if (txids.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Batch TXIDs', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 180),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        txids.join('\n'),
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.cyanAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: txids.join('\n')));
                        if (!mounted) return;
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(content: Text('Batch TXIDs copied')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy TXIDs'),
                    ),
                  ),
                ],
              ],
            ),
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

  double _satVbToBtcsKvB(double satVb) {
    return satVb * 0.00001;
  }

  Future<double?> _showManualFeeDialog(WalletProvider provider) async {
    bool useSatVb = true;

    const lowBTCSKvB = 0.00000226;
    const highBTCSKvB = 0.0004;
    final lowSatVb = lowBTCSKvB / 0.00001;
    final highSatVb = highBTCSKvB / 0.00001;

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
                          'Low traffic: ${_formatDecimal(lowSatVb, maxDecimals: 4)} sat/vB (${lowBTCSKvB.toStringAsFixed(8)} BTCS/kvB), slower confirmation',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'High traffic: ${_formatDecimal(highSatVb, maxDecimals: 4)} sat/vB (${highBTCSKvB.toStringAsFixed(8)} BTCS/kvB), faster confirmation',
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
                              : lowBTCSKvB.toStringAsFixed(8);
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
                              : highBTCSKvB.toStringAsFixed(8);
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

    final enteredAmount = double.tryParse(text);
    if (enteredAmount == null) return 'Invalid number';
    if (enteredAmount <= 0) return 'Amount must be greater than zero';

    final feeSnapshot = _currentDisplayedFee(provider);
    if (_subtractFeeFromAmount && feeSnapshot.fee <= 0) {
      return 'Fee estimate required for subtract-fee mode';
    }

    final effectiveSendAmount = _effectiveSendAmount(
      provider: provider,
      feeSnapshot: feeSnapshot,
      enteredAmount: enteredAmount,
    );

    if (_subtractFeeFromAmount && effectiveSendAmount <= 0) {
      return 'Amount must be greater than estimated fee';
    }
    if (effectiveSendAmount < 0.00000546) {
      return _subtractFeeFromAmount
          ? 'Recipient amount after fee is below dust threshold (0.00000546 BTCS)'
          : 'Amount below dust threshold (0.00000546 BTCS)';
    }

    final enteredAmountSats = _btcsToSats(enteredAmount);
    final spendableSats = _advancedSend && provider.selectedUtxoCount > 0
        ? _selectedUtxoTotalSats(provider)
      : _btcsToSats(provider.balance ?? 0.0);

    if (enteredAmountSats > spendableSats) {
      if (_advancedSend && provider.selectedUtxoCount > 0) {
        return 'Exceeds selected inputs (${_satsToBtcs(spendableSats).toStringAsFixed(8)} BTCS)';
      }
      return 'Exceeds available balance';
    }

    return null;
  }

  double _effectiveSendAmount({
    required WalletProvider provider,
    required ({double fee, bool hasExactCoinControlFee, ({double fee, int? inputCount, bool amountAware}) simpleEstimate})
        feeSnapshot,
    required double enteredAmount,
  }) {
    final value = _subtractFeeFromAmount ? (enteredAmount - feeSnapshot.fee) : enteredAmount;
    if (value <= 0) return 0.0;
    return double.parse(value.toStringAsFixed(8));
  }

  double _estimatedTotalSpendAmount({
    required WalletProvider provider,
    required ({double fee, bool hasExactCoinControlFee, ({double fee, int? inputCount, bool amountAware}) simpleEstimate})
        feeSnapshot,
    required double enteredAmount,
  }) {
    if (_subtractFeeFromAmount) {
      return double.parse(enteredAmount.toStringAsFixed(8));
    }
    final total = enteredAmount + feeSnapshot.fee;
    return double.parse(total.toStringAsFixed(8));
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
          if (provider.coinControlTruncatedCount > 0)
            Text(
              'Showing top ${provider.availableUtxos.length} inputs by amount. '
              '${provider.coinControlTruncatedCount} smaller input(s) are hidden for performance.',
              style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
            ),
          if (provider.coinControlTruncatedCount > 0)
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
                final confirmations = (utxo['confirmations'] as num?)?.toInt() ?? 0;
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
                      '#${globalIndex + 1} | Amount: ${(utxo['amount'] as num).toStringAsFixed(8)} BTCS | ${_formatConfirmationsLabel(confirmations)}',
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
    final enteredAmount = double.tryParse(_amountController.text.trim());
    final displayNetAfterFee = (hasExactCoinControlFee && enteredAmount != null && enteredAmount > 0)
      ? _effectiveSendAmount(
          provider: provider,
          feeSnapshot: feeSnapshot,
          enteredAmount: enteredAmount,
        )
      : provider.estimatedNetSend;
    final netRowLabel = _subtractFeeFromAmount ? 'Recipient After Fee' : 'Max Send After Fee';
    final netAfterFeeText = displayNetAfterFee > 0
      ? '${displayNetAfterFee.toStringAsFixed(8)} BTCS'
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
                Text(
                  netRowLabel,
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
    final enteredAmount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (enteredAmount <= 0) return const SizedBox.shrink();

    final hasSelectedInputs = feeSnapshot.hasExactCoinControlFee;
    final fee = feeSnapshot.fee;
    final sendAmount = _effectiveSendAmount(
      provider: provider,
      feeSnapshot: feeSnapshot,
      enteredAmount: enteredAmount,
    );
    final totalSpend = _estimatedTotalSpendAmount(
      provider: provider,
      feeSnapshot: feeSnapshot,
      enteredAmount: enteredAmount,
    );
    if (sendAmount <= 0) return const SizedBox.shrink();

    final selectedInputsSats = hasSelectedInputs ? _selectedUtxoTotalSats(provider) : 0;
    final autoSpendableSats = _btcsToSats(provider.balance ?? 0.0);
    final sendAmountSats = _btcsToSats(sendAmount);
    final totalSpendSats = _btcsToSats(totalSpend);
    final expectedChangeSats = hasSelectedInputs
      ? (selectedInputsSats - totalSpendSats)
      : (autoSpendableSats - totalSpendSats);

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
              const Text('Recipient Amount', style: TextStyle(color: Colors.white60, fontSize: 12)),
              Text(
                '${_satsToBtcs(sendAmountSats).toStringAsFixed(8)} BTCS',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
          if (_subtractFeeFromAmount) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Entered Total (includes fee)', style: TextStyle(color: Colors.white60, fontSize: 12)),
                Text(
                  '${enteredAmount.toStringAsFixed(8)} BTCS',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ],
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
              const Text('Total Spend (est.)', style: TextStyle(color: Colors.white60, fontSize: 12)),
              Text(
                '${_satsToBtcs(totalSpendSats).toStringAsFixed(8)} BTCS',
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

  Widget _buildSubtractFeeTicker(
    WalletProvider provider,
    ({double fee, bool hasExactCoinControlFee, ({double fee, int? inputCount, bool amountAware}) simpleEstimate})
        feeSnapshot,
  ) {
    final enteredAmount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final effectiveAmount = enteredAmount > 0
        ? _effectiveSendAmount(
            provider: provider,
            feeSnapshot: feeSnapshot,
            enteredAmount: enteredAmount,
          )
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Subtract Fee From Amount',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 2),
                Text(
                  'ON: entered amount is total spend cap. OFF: recipient gets full entered amount.',
                  style: TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: _subtractFeeFromAmount,
            onChanged: _isSending ? null : (value) => setState(() => _subtractFeeFromAmount = value),
          ),
          if (_subtractFeeFromAmount && enteredAmount > 0) ...[
            const SizedBox(width: 8),
            Text(
              'Net ${effectiveAmount > 0 ? effectiveAmount.toStringAsFixed(8) : '-'}',
              style: TextStyle(
                color: effectiveAmount > 0 ? Colors.greenAccent : Colors.redAccent,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
    required double enteredAmount,
    required double amount,
    required bool subtractFeeFromAmount,
  }) async {
    final hasSelectedInputs = _advancedSend && provider.selectedUtxoCount > 0;
    final simpleEstimate = _estimateSimpleModeFee(provider);
    final estimatedFee = hasSelectedInputs ? provider.estimatedFee : simpleEstimate.fee;
    final amountModeLabel = subtractFeeFromAmount
        ? 'Fee included in entered amount'
        : 'Fee added on top of entered amount';
    final totalSpend = subtractFeeFromAmount ? enteredAmount : enteredAmount + estimatedFee;

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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Amount Mode', style: TextStyle(color: Colors.white60, fontSize: 12)),
                  Text(
                    amountModeLabel,
                    style: TextStyle(
                      color: subtractFeeFromAmount ? Colors.amberAccent : Colors.greenAccent,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Entered amount: ${enteredAmount.toStringAsFixed(8)} BTCS', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              Text('Recipient amount: ${amount.toStringAsFixed(8)} BTCS', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              Text('Estimated fee: ${estimatedFee.toStringAsFixed(8)} BTCS', style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 4),
              Text('Total spend (est.): ${totalSpend.toStringAsFixed(8)} BTCS', style: const TextStyle(color: Colors.white70)),
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

                        if (_activeRequest != null) _buildActiveRequestCard(_activeRequest!),

                        // Recipient Address Field
                        TextField(
                          controller: _addressController,
                          onChanged: _onAddressChanged,
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
                                    final scanned = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const ScannerView(),
                                      ),
                                    );
                                    if (scanned is String && mounted) {
                                      _applyScannedOrPasted(scanned);
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

                        const SizedBox(height: 12),
                        _buildSubtractFeeTicker(walletProvider, feeSnapshot),

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
                          'To send BTCS, enter the recipient\'s bs1 or legacy address and the amount. Ensure you have enough balance to cover the transaction fee.',
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