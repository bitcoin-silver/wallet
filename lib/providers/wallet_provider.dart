import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bitcoinsilver_wallet/services/wallet_service.dart';
import 'package:bitcoinsilver_wallet/services/notification_service.dart';

// Backend URL - HTTPS endpoint
const String backendUrl = 'https://btcs-vps13.duckdns.org';

class WalletProvider with ChangeNotifier {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final WalletService _ws = WalletService();
  late NotificationService _notificationService;
  Function(String address)? _onTransactionTapped;

  String? _privateKey;
  String? _address;
  double? _balance = 0.0;
  double? _pendingBalance = 0.0;
  List _utxos = [];
  bool _isLoading = false;
  String? _lastError;
  DateTime? _lastFetch;
  bool _isCurrentlySending = false;
  DateTime? _lastSendAttempt;

  // Pending transaction tracking
  final Set<String> _pendingTxids = {};
  final Map<String, DateTime> _pendingTimestamps = {};
  final Map<String, PendingTransaction> _pendingTransactions = {};

  // Getters
  String? get privateKey => _privateKey;
  String? get address => _address;
  double? get balance => _balance;
  double? get pendingBalance => _pendingBalance;
  List? get utxos => _utxos;
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;
  bool get hasPendingTransactions => _pendingTransactions.isNotEmpty;
  int get pendingTransactionsCount => _pendingTransactions.length;

  // Display balance - shows actual spendable balance considering consumed UTXOs
  double? get displayBalance {
    if (_pendingTransactions.isEmpty) {
      return _balance;
    }

    // Start with confirmed balance from available UTXOs
    double spendableBalance = _balance ?? 0.0;

    // Add expected change from pending transactions back to the wallet
    for (final tx in _pendingTransactions.values) {
      spendableBalance += tx.changeAmount;
    }

    return spendableBalance < 0 ? 0.0 : spendableBalance;
  }

  // Get list of pending transactions
  List<PendingTransaction> get pendingTransactionsList =>
      _pendingTransactions.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  WalletProvider() {
    _notificationService = NotificationService(
      backendUrl: backendUrl,
      onTransactionReceived: _handleTransactionReceived,
      onNotificationTapped: _handleNotificationTapped,
    );
  }

  /// Handle confirmed transaction notification - refresh balance
  void _handleTransactionReceived(String txid, String amount, String address) {
    debugPrint('✅ Transaction confirmed: $amount BTCS - Refreshing balance');
    // Safety check: only process if wallet is loaded
    if (_address == null) {
      debugPrint('⚠️ Wallet not loaded yet, skipping transaction notification');
      return;
    }
    // Refresh UTXOs to update balance (called only for confirmed transactions)
    fetchUtxos(force: true);
    notifyListeners();
  }

  /// Handle notification tap - refresh balance and transactions
  void _handleNotificationTapped(String txid) {
    debugPrint('👆 Notification tapped: $txid - Refreshing balance and transactions');
    // Safety check: only process if wallet is loaded
    if (_address == null) {
      debugPrint('⚠️ Wallet not loaded yet, skipping notification tap');
      return;
    }
    // Refresh balance when user taps notification
    fetchUtxos(force: true);
    // Trigger transaction refresh if callback is set
    if (_onTransactionTapped != null) {
      _onTransactionTapped!(_address!);
    }
    notifyListeners();
  }

  /// Set callback for transaction refresh (called from main.dart)
  void setTransactionRefreshCallback(Function(String address) callback) {
    _onTransactionTapped = callback;
  }

  Future<void> loadWallet() async {
    try {
      _isLoading = true;
      notifyListeners();

      _privateKey = await _storage.read(key: 'key');
      if (_privateKey != null) {
        _address = _ws.loadAddressFromKey(_privateKey!);

        // Initialize push notifications in the background (only if enabled)
        if (_address != null) {
          final prefs = await SharedPreferences.getInstance();
          final notificationsEnabled = prefs.getBool('notifications_enabled') ?? false;
          if (notificationsEnabled) {
            _initializeNotifications(_address!);
          }
        }

        // Don't fetch UTXOs here - let the caller decide when to fetch
        // This makes wallet loading instant (no network calls)
      }
    } catch (e) {
      _lastError = 'Failed to load wallet: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Initialize push notifications for the wallet address
  Future<void> _initializeNotifications(String address) async {
    try {
      await _notificationService.initialize(address);
      debugPrint('✓ Push notifications initialized for address');
    } catch (e) {
      debugPrint('✗ Failed to initialize push notifications: $e');
      // Don't fail the wallet loading if notifications fail
    }
  }

  /// Enable push notifications (called from settings)
  Future<void> enableNotifications(String address) async {
    try {
      await _notificationService.initialize(address);
      debugPrint('✓ Push notifications enabled');
    } catch (e) {
      debugPrint('✗ Failed to enable push notifications: $e');
      rethrow;
    }
  }

  /// Disable push notifications (called from settings)
  Future<void> disableNotifications(String address) async {
    try {
      await _notificationService.unregisterDevice(address);
      await _notificationService.deleteToken();
      debugPrint('✓ Push notifications disabled');
    } catch (e) {
      debugPrint('✗ Failed to disable push notifications: $e');
      rethrow;
    }
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
    _balance = 0.0;
    _pendingBalance = 0.0;
    _utxos = [];
    _pendingTxids.clear();
    _pendingTimestamps.clear();
    _pendingTransactions.clear();
    await _storage.delete(key: 'key');
    notifyListeners();
  }

  // Clean up old pending transactions (30 minutes timeout)
  void _cleanupPendingTransactions() {
    final now = DateTime.now();
    final toRemove = <String>[];

    _pendingTimestamps.forEach((txid, timestamp) {
      if (now.difference(timestamp).inMinutes > 30) {
        toRemove.add(txid);
      }
    });

    for (final txid in toRemove) {
      _pendingTxids.remove(txid);
      _pendingTimestamps.remove(txid);
      _pendingTransactions.remove(txid);
    }

    // Notify listeners if any pending transactions were removed
    if (toRemove.isNotEmpty) {
      notifyListeners();
    }
  }


  Future<void> fetchUtxos({bool force = false, bool silent = false}) async {
    if (_address == null) {
      _balance = 0.0;
      _pendingBalance = 0.0;
      _utxos = [];
      notifyListeners();
      return;
    }

    // Rate limiting
    if (!force && _lastFetch != null) {
      final timeSinceLastFetch = DateTime.now().difference(_lastFetch!);
      if (timeSinceLastFetch.inSeconds < 5) {
        return;
      }
    }

    try {
      if (!silent) {
        _isLoading = true;
        notifyListeners();
      }

      _cleanupPendingTransactions();

      // Scan for UTXOs
      final result = await _ws.rpcRequest('scantxoutset', [
        'start',
        [{'desc': 'addr($_address)'}]
      ]);

      if (result == null || result['result'] == null) {
        // Keep pending balance if we have pending transactions
        if (_pendingTransactions.isEmpty) {
          _balance = 0.0;
          _pendingBalance = 0.0;
          _utxos = [];
        }
        notifyListeners();
        return;
      }

      final utxos = result['result']['unspents'] as List<dynamic>? ?? [];

      if (utxos.isEmpty) {
        _balance = 0.0;
        _utxos = [];
        notifyListeners();
        return;
      }

      // Get blockchain height
      final blockchainInfo = await _ws.rpcRequest('getblockchaininfo');
      final currentHeight = blockchainInfo?['result']?['blocks'] ?? 0;

      if (currentHeight == 0) {
        _lastError = 'Could not get blockchain info';
        notifyListeners();
        return;
      }

      // Get mempool transactions
      final mempoolResult = await _ws.rpcRequest('getrawmempool', [false]);
      final mempoolTxIds = mempoolResult?['result'] as List<dynamic>? ?? [];
      final lockedUtxos = <String>{};

      // Batch check mempool transactions (process in chunks to avoid huge requests)
      const batchSize = 20;
      for (int i = 0; i < mempoolTxIds.length; i += batchSize) {
        final chunk = mempoolTxIds.skip(i).take(batchSize).toList();

        try {
          // Build batch request for getrawtransaction
          final batchRequests = chunk.map((txid) => {
            'method': 'getrawtransaction',
            'params': [txid, true],
          }).toList();

          final batchResults = await _ws.batchRpcRequest(batchRequests);

          // Process batch results
          for (final tx in batchResults) {
            if (tx != null && tx['result'] != null) {
              final vinList = tx['result']['vin'] as List<dynamic>? ?? [];
              for (final vin in vinList) {
                lockedUtxos.add('${vin['txid']}:${vin['vout']}');
              }
            }
          }
        } catch (e) {
          // Continue with next batch
        }
      }

      // Also lock UTXOs consumed by our pending transactions
      for (final pendingTx in _pendingTransactions.values) {
        for (final utxo in pendingTx.consumedUtxos) {
          lockedUtxos.add('${utxo['txid']}:${utxo['vout']}');
        }
      }

      // Check if pending transactions are confirmed (batch request)
      final confirmedTxs = <String>[];
      if (_pendingTxids.isNotEmpty) {
        try {
          final batchRequests = _pendingTxids.map((txid) => {
            'method': 'getrawtransaction',
            'params': [txid, true],
          }).toList();

          final batchResults = await _ws.batchRpcRequest(batchRequests);

          for (int i = 0; i < batchResults.length; i++) {
            final tx = batchResults[i];
            final pendingTxid = _pendingTxids.elementAt(i);

            if (tx != null && tx['result'] != null) {
              if (tx['result']['confirmations'] != null && tx['result']['confirmations'] > 0) {
                confirmedTxs.add(pendingTxid);
              } else {
                // Still pending - lock its inputs
                final vinList = tx['result']['vin'] as List<dynamic>? ?? [];
                for (final vin in vinList) {
                  lockedUtxos.add('${vin['txid']}:${vin['vout']}');
                }
              }
            }
          }
        } catch (e) {
          // Transactions might not be in mempool yet
        }
      }

      // Remove confirmed transactions
      for (final txid in confirmedTxs) {
        _pendingTxids.remove(txid);
        _pendingTimestamps.remove(txid);
        _pendingTransactions.remove(txid);
      }

      // Filter available UTXOs
      final availableUtxos = <Map<String, dynamic>>[];
      double totalBalance = 0.0;

      for (final utxo in utxos) {
        final utxoId = '${utxo['txid']}:${utxo['vout']}';

        int confirmations = 0;
        if (utxo['height'] != null && utxo['height'] > 0) {
          confirmations = currentHeight - utxo['height'] + 1;
        }

        // Only use confirmed UTXOs that are not locked
        if (confirmations > 0 && !lockedUtxos.contains(utxoId)) {
          availableUtxos.add({
            ...utxo,
            'confirmations': confirmations,
          });
          totalBalance += utxo['amount'] ?? 0.0;
        }
      }

      _utxos = availableUtxos;
      _balance = totalBalance;
      _lastFetch = DateTime.now();

    } catch (e) {
      _lastError = 'Failed to fetch UTXOs: $e';
    } finally {
      if (!silent) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> createTransaction(
      String address,
      double? amount, {
        double? feeRateOverride,
      }) async {

    if (amount == null || amount <= 0) {
      return {
        'success': false,
        'message': 'Invalid amount',
      };
    }

    // Fetch fresh UTXOs
    await fetchUtxos(force: true);

    if (_utxos.isEmpty) {
      return {
        'success': false,
        'message': 'No confirmed UTXOs available. Please wait for confirmations.',
      };
    }

    // Sort UTXOs by amount (largest first)
    _utxos.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));

    // Get fee rate
    double feeRate = feeRateOverride ?? 0.00001;
    if (feeRateOverride == null) {
      try {
        final feeResult = await _ws.rpcRequest('estimatesmartfee', [6]);
        feeRate = feeResult?['result']?['feerate'] ?? 0.00001;
        if (feeRate <= 0) feeRate = 0.00001;
      } catch (e) {
        feeRate = 0.00001;
      }
    }

    List<Map<String, dynamic>> selectedUtxos = [];
    double inputSum = 0.0;

    // Select UTXOs
    for (var utxo in _utxos) {
      selectedUtxos.add({
        'txid': utxo['txid'],
        'vout': utxo['vout'],
      });

      inputSum += utxo['amount'];

      // Calculate transaction size and fee
      final inputCount = selectedUtxos.length;
      final outputCount = 2; // Assume change output
      final txSize = 10 + (inputCount * 148) + (outputCount * 34);
      final fee = (feeRate * txSize / 1000);

      if (inputSum >= amount + fee) {
        final actualFee = double.parse(fee.toStringAsFixed(8));
        final change = double.parse((inputSum - amount - actualFee).toStringAsFixed(8));

        final outputs = <String, dynamic>{
          address: double.parse(amount.toStringAsFixed(8)),
        };

        // Add change output if above dust threshold
        if (change > 0.00000546) {
          outputs[_address!] = change;
        }

        final createRawResult = await _ws.rpcRequest('createrawtransaction', [selectedUtxos, outputs]);

        if (createRawResult == null || createRawResult['result'] == null) {
          return {
            'success': false,
            'message': 'Failed to create raw transaction',
          };
        }

        return {
          'success': true,
          'result': createRawResult['result'],
          'fee': actualFee,
          'toAddress': address,
          'consumedUtxos': selectedUtxos.map((utxo) {
            // Find the full UTXO data for tracking
            final fullUtxo = _utxos.firstWhere(
              (u) => u['txid'] == utxo['txid'] && u['vout'] == utxo['vout'],
              orElse: () => {'amount': 0.0},
            );
            return {
              'txid': utxo['txid'],
              'vout': utxo['vout'],
              'amount': fullUtxo['amount'] ?? 0.0,
            };
          }).toList(),
          'changeAmount': change,
        };
      }
    }

    return {
      'success': false,
      'message': 'Insufficient funds. Available: ${inputSum.toStringAsFixed(8)} BTCS',
    };
  }

  Future<Map<String, dynamic>> sendTransaction(
      String address,
      double amount,
      {double? feeRate}
      ) async {

    if (_privateKey == null || _address == null) {
      return {
        'success': false,
        'message': 'Wallet not initialized'
      };
    }

    // Prevent multiple simultaneous sends
    if (_isCurrentlySending) {
      return {
        'success': false,
        'message': 'Transaction already in progress. Please wait.'
      };
    }

    // Prevent rapid-fire sends (minimum 3 seconds between attempts)
    if (_lastSendAttempt != null) {
      final timeSinceLastSend = DateTime.now().difference(_lastSendAttempt!);
      if (timeSinceLastSend.inSeconds < 3) {
        return {
          'success': false,
          'message': 'Please wait a moment before sending another transaction.'
        };
      }
    }

    _isCurrentlySending = true;
    _lastSendAttempt = DateTime.now();

    // Create transaction
    final createResult = await createTransaction(
        address,
        amount,
        feeRateOverride: feeRate
    );

    if (!createResult['success']) {
      _isCurrentlySending = false;
      return createResult;
    }

    try {
      final rawTx = createResult['result'];

      // Sign transaction
      final signResult = await _ws.rpcRequest('signrawtransactionwithkey', [
        rawTx,
        [_privateKey]
      ]);

      if (signResult == null || signResult['result'] == null) {
        return {
          'success': false,
          'message': 'Failed to sign transaction'
        };
      }

      if (!signResult['result']['complete']) {
        return {
          'success': false,
          'message': 'Transaction signature incomplete'
        };
      }

      final signedTx = signResult['result']['hex'];

      // Send transaction
      final sendResult = await _ws.rpcRequest('sendrawtransaction', [signedTx, 0]);

      if (sendResult != null && sendResult['result'] != null) {
        final txid = sendResult['result'];

        // Track pending transaction with consumed UTXOs
        _pendingTxids.add(txid);
        _pendingTimestamps[txid] = DateTime.now();
        _pendingTransactions[txid] = PendingTransaction(
          txid: txid,
          amount: amount,
          fee: createResult['fee'],
          toAddress: address,
          timestamp: DateTime.now(),
          consumedUtxos: List<Map<String, dynamic>>.from(createResult['consumedUtxos'] ?? []),
          changeAmount: createResult['changeAmount'] ?? 0.0,
        );

        // Notify listeners to update UI with new pending state
        notifyListeners();

        // Start smart confirmation checking
        _startSmartConfirmationChecking(txid);

        return {
          'success': true,
          'txid': txid,
          'message': 'Transaction sent successfully',
          'fee': createResult['fee'],
        };
      }

      // Handle error
      final errorMessage = sendResult?['error']?['message'] ?? 'Unknown error';

      // Check for fee errors
      final feeRateMatch = RegExp(r'new feerate ([\d.]+) BTCS/kvB').firstMatch(errorMessage);
      if (feeRateMatch != null) {
        final suggestedFeeRate = double.parse(feeRateMatch.group(1)!);
        return {
          'success': false,
          'message': 'Fee too low',
          'suggestedFeeRate': suggestedFeeRate,
          'currentFeeRate': feeRate ?? 0.00001,
        };
      }

      return {
        'success': false,
        'message': errorMessage,
      };

    } catch (e) {
      return {
        'success': false,
        'message': 'Error: ${e.toString()}',
      };
    } finally {
      _isCurrentlySending = false;
    }
  }

  // Smart confirmation checking with exponential backoff
  void _startSmartConfirmationChecking(String txid) async {
    // Initial checks: 5s, 10s, 20s, 40s, 1m20s, 2m40s, 5m, 10m
    final checkIntervals = [5, 10, 20, 40, 80, 160, 300, 600];

    for (int i = 0; i < checkIntervals.length; i++) {
      if (!_pendingTxids.contains(txid)) break;

      await Future.delayed(Duration(seconds: checkIntervals[i]));

      if (_pendingTxids.contains(txid)) {
        await fetchUtxos(force: true, silent: true);
      }
    }

    // Then check every 5 minutes for up to 2 hours
    int additionalChecks = 0;
    while (additionalChecks < 24 && _pendingTxids.contains(txid)) {
      await Future.delayed(const Duration(minutes: 5));

      if (_pendingTxids.contains(txid)) {
        await fetchUtxos(force: true, silent: true);
      }
      additionalChecks++;
    }

    // Clean up after 2 hours
    if (_pendingTxids.contains(txid)) {
      _pendingTxids.remove(txid);
      _pendingTimestamps.remove(txid);
      _pendingTransactions.remove(txid);
      await fetchUtxos(force: true);
    }
  }

  // Helper method to refresh balance
  Future<void> refreshBalance() async {
    await fetchUtxos(force: true);
  }
}

// Pending transaction model
class PendingTransaction {
  final String txid;
  final double amount;
  final double fee;
  final String toAddress;
  final DateTime timestamp;
  final List<Map<String, dynamic>> consumedUtxos; // UTXOs used as inputs
  final double changeAmount; // Expected change back to wallet

  PendingTransaction({
    required this.txid,
    required this.amount,
    required this.fee,
    required this.toAddress,
    required this.timestamp,
    required this.consumedUtxos,
    required this.changeAmount,
  });
}