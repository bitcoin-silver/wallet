import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bitcoinsilver_wallet/services/wallet_service.dart';
import 'package:bitcoinsilver_wallet/services/notification_service.dart';
import 'package:bitcoinsilver_wallet/services/rpc_config_service.dart';
import 'package:bitcoinsilver_wallet/services/btcs_signer.dart';

// Backend URL - HTTPS endpoint
const String backendUrl = 'https://bitcoinsilver.eu';

class WalletProvider with ChangeNotifier {
  // Use default storage (compatible with Play Store signing)
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final WalletService _ws;
  late NotificationService _notificationService;
  Function(String address)? _onTransactionTapped;
  Function()? _onChatMessageTapped;

  String? _privateKey;
  String? _mnemonic;
  String? _address;
  double? _balance = 0.0;
  double? _pendingBalance = 0.0;
  List _utxos = [];
  bool _isLoading = false;
  bool _isPending = false;
  String? _lastError;
  DateTime? _lastFetch;
  bool _isCurrentlySending = false;
  DateTime? _lastSendAttempt;
  String? _rpcError; // New field to store RPC connection errors
  String _message = '';
  double _feeRate = 0.00001;
  bool _feeEstimateAvailable = false;
  bool _isFeeEstimateLoading = false;
  String? _feeEstimateError;

  // Advanced send coin-control state
  List<Map<String, dynamic>> _availableUtxos = [];
  final Set<String> _selectedUtxoKeys = {};
  bool _isLoadingUtxos = false;
  int _utxoPage = 0;
  static const int _utxosPerPage = 15;

  // Getter for RPC error
  String? get rpcError => _rpcError;
  String get message => _message;
  double get feeRate => _feeRate;
  bool get feeEstimateAvailable => _feeEstimateAvailable;
  bool get isFeeEstimateLoading => _isFeeEstimateLoading;
  String? get feeEstimateError => _feeEstimateError;

  List<Map<String, dynamic>> get availableUtxos => _availableUtxos;
  Set<String> get selectedUtxoKeys => _selectedUtxoKeys;
  bool get isLoadingUtxos => _isLoadingUtxos;
  int get utxoPage => _utxoPage;
  int get utxoPageCount =>
      _availableUtxos.isEmpty ? 1 : (_availableUtxos.length / _utxosPerPage).ceil();
  int get selectedUtxoCount => _selectedUtxoKeys.length;

  // Typical 1-input, 2-output transaction size estimate
  double get estimatedSimpleFee =>
      double.parse((_feeRate * 226 / 1000).toStringAsFixed(8));

  double get selectedUtxoTotal => _availableUtxos
      .where((u) => _selectedUtxoKeys.contains('${u['txid']}:${u['vout']}'))
      .fold(0.0, (sum, u) => sum + (u['amount'] as num).toDouble());

  List<Map<String, dynamic>> get selectedUtxoList => _availableUtxos
      .where((u) => _selectedUtxoKeys.contains('${u['txid']}:${u['vout']}'))
      .toList();

  List<Map<String, dynamic>> get currentPageUtxos {
    final start = _utxoPage * _utxosPerPage;
    final end = (start + _utxosPerPage).clamp(0, _availableUtxos.length);
    return _availableUtxos.sublist(start, end);
  }

  double get estimatedFee {
    if (_selectedUtxoKeys.isEmpty) return 0.0;
    final inputCount = _selectedUtxoKeys.length;
    final txSize = 11 + (inputCount * 68) + 31 + 31;
    return double.parse((_feeRate * txSize / 1000).toStringAsFixed(8));
  }

  double get estimatedNetSend {
    final net = selectedUtxoTotal - estimatedFee;
    return net > 0 ? net : 0.0;
  }

  // Setter for RPC error
  void setRpcError(String? error) {
    _rpcError = error;
    notifyListeners();
  }

  void clearMessage() {
    _message = '';
    notifyListeners();
  }

  Future<bool> fetchFeeRate() async {
    _isFeeEstimateLoading = true;
    notifyListeners();

    try {
      final feeResult = await _ws.rpcRequest('estimatesmartfee', [6]);

      if (feeResult?['error'] != null) {
        _feeEstimateAvailable = false;
        _feeEstimateError = feeResult!['error']['message'] as String? ??
            'Fee estimation failed';
        return false;
      }

      final result = feeResult?['result'];
      if (result is! Map<String, dynamic>) {
        _feeEstimateAvailable = false;
        _feeEstimateError = 'Fee estimation returned an invalid response.';
        return false;
      }

      final feerateRaw = result['feerate'];
      if (feerateRaw is num) {
        final feerate = feerateRaw.toDouble();
        if (feerate > 0) {
          _feeRate = feerate;
          _feeEstimateAvailable = true;
          _feeEstimateError = null;
          return true;
        }

        if (feerate == -1) {
          _feeEstimateAvailable = false;
          final errors = result['errors'];
          if (errors is List && errors.isNotEmpty) {
            _feeEstimateError = errors.join(', ');
          } else {
            _feeEstimateError =
                'Node could not estimate a network fee at this time.';
          }
          return false;
        }
      }

      final errors = result['errors'];
      _feeEstimateAvailable = false;
      if (errors is List && errors.isNotEmpty) {
        _feeEstimateError = errors.join(', ');
      } else {
        _feeEstimateError =
            'No fee rate was returned by the node for this target.';
      }
      return false;
    } catch (e) {
      _feeEstimateAvailable = false;
      _feeEstimateError = 'RPC fee estimation failed: $e';
      return false;
    } finally {
      _isFeeEstimateLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchUtxosForCoinControl() async {
    if (_address == null) return;

    _isLoadingUtxos = true;
    _availableUtxos = [];
    _selectedUtxoKeys.clear();
    _utxoPage = 0;
    notifyListeners();

    try {
      await fetchUtxos(force: true, silent: true);

      _availableUtxos = _utxos
          .where((u) =>
              u['txid'] != 'pending_marker' &&
              (u['confirmations'] as int? ?? 0) > 0)
          .map((u) => Map<String, dynamic>.from(u))
          .toList();

      _availableUtxos.sort((a, b) =>
          ((b['amount'] as num).toDouble()).compareTo((a['amount'] as num).toDouble()));

      await fetchFeeRate();
    } finally {
      _isLoadingUtxos = false;
      notifyListeners();
    }
  }

  void toggleUtxo(String key) {
    if (_selectedUtxoKeys.contains(key)) {
      _selectedUtxoKeys.remove(key);
    } else {
      _selectedUtxoKeys.add(key);
    }
    notifyListeners();
  }

  void selectAllUtxos() {
    _selectedUtxoKeys
      ..clear()
      ..addAll(_availableUtxos.map((u) => '${u['txid']}:${u['vout']}'));
    notifyListeners();
  }

  void clearUtxoSelection() {
    _selectedUtxoKeys.clear();
    notifyListeners();
  }

  void resetCoinControl() {
    _availableUtxos = [];
    _selectedUtxoKeys.clear();
    _isLoadingUtxos = false;
    _utxoPage = 0;
    notifyListeners();
  }

  void setUtxoPage(int page) {
    if (page < 0 || page >= utxoPageCount) return;
    _utxoPage = page;
    notifyListeners();
  }

  Future<bool> validateAddress(String address) async {
    final candidate = address.trim();
    if (candidate.isEmpty) return false;

    try {
      final result = await _ws.rpcRequest('validateaddress', [candidate]);
      final bool rpcValid = result != null &&
          result['result'] != null &&
          result['result']['isvalid'] == true;

      debugPrint(
        'Address validation via RPC for $candidate => $rpcValid, raw: ${result?['result']}',
      );

      if (rpcValid) return true;
    } catch (_) {
      debugPrint('Address validation RPC call failed for $candidate; trying local fallback.');
      // Fall through to local parser check.
    }

    // Fallback for BTCS networks where RPC validateaddress can reject
    // otherwise valid BTCS legacy/bech32 formats.
    try {
      BTCSSigner.scriptFromAddress(candidate);
      debugPrint('Address validation local fallback accepted $candidate.');
      return true;
    } catch (_) {
      debugPrint('Address validation local fallback rejected $candidate.');
      return false;
    }
  }

  // Pending transaction tracking
  final Set<String> _pendingTxids = {};
  final Map<String, DateTime> _pendingTimestamps = {};
  final Map<String, PendingTransaction> _pendingTransactions = {};

  // Getters
  String? get privateKey => _privateKey;
  String? get mnemonic => _mnemonic;
  String? get address => _address;
  double? get balance => _balance;
  double? get pendingBalance => _pendingBalance;
  List? get utxos => _utxos;
  bool get isLoading => _isLoading;
  bool get isPending => _isPending;
  String? get lastError => _lastError;
  bool get hasPendingTransactions => _isPending || _pendingTransactions.isNotEmpty || (_pendingBalance != null && _pendingBalance! > 0);
  int get pendingTransactionsCount {
    // Locally tracked outgoing transactions
    int outgoing = _pendingTransactions.length;

    // Incoming unconfirmed UTXOs (filtering out our own change to avoid double counting)
    int incoming = _utxos.where((u) =>
      u['confirmations'] == 0 &&
      !_pendingTransactions.containsKey(u['txid']) &&
      u['txid'] != 'pending_marker'
    ).length;

    // Ensure we at least show 1 if _isPending is true but UTXOs aren't visible yet
    int count = outgoing + incoming;
    if (count == 0 && _isPending) return 1;
    return count;
  }

  WalletService get walletService => _ws; // Public getter for WalletService

  // Display balance - shows actual spendable balance considering consumed UTXOs and incoming funds
  double? get displayBalance {
    // 1. Sum up all UTXOs in our filtered list (_utxos).
    // This list contains:
    // - All confirmed UTXOs EXCEPT those spent by our pending transactions.
    // - All unconfirmed UTXOs from the network (incoming funds).
    // - Our change outputs IF they are already visible in the mempool.
    double total = _utxos.fold(0.0, (sum, u) => sum + (u['amount'] as num).toDouble());

    // 2. Add expected change from pending transactions that are NOT yet visible in _utxos
    // (e.g., just sent, not yet in mempool or not yet detected by the node)
    for (final tx in _pendingTransactions.values) {
      bool changeAlreadyInUtxos = _utxos.any((u) => u['txid'] == tx.txid);
      if (!changeAlreadyInUtxos) {
        total += tx.changeAmount;
      }
    }

    return total < 0 ? 0.0 : total;
  }

  // Get list of pending transactions
  List<PendingTransaction> get pendingTransactionsList =>
      _pendingTransactions.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  WalletProvider(RpcConfigService rpcConfigService) : _ws = WalletService(rpcConfigService) {
    _notificationService = NotificationService(
      backendUrl: backendUrl,
      onTransactionReceived: _handleTransactionReceived,
      onNotificationTapped: _handleNotificationTapped,
      onChatMessageReceived: _handleChatMessageReceived,
    );
  }

  /// Handle transaction notification - refresh balance and pending state
  void _handleTransactionReceived(String txid, String amount, String address) {
    debugPrint('🔔 Transaction activity detected: $amount BTCS - Refreshing...');
    // Safety check: only process if wallet is loaded
    if (_address == null) {
      debugPrint('⚠️ Wallet not loaded yet, skipping transaction notification');
      return;
    }
    // Refresh UTXOs to update balance and pending state
    fetchUtxos(force: true, silent: true);
    
    // Also trigger blockchain provider to refresh transaction list and chart
    if (_onTransactionTapped != null) {
      _onTransactionTapped!(_address!);
    }

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

  /// Handle chat message notification tap
  void _handleChatMessageReceived(Map<String, dynamic> data) {
    debugPrint('💬 Chat message notification received in WalletProvider');
    if (_onChatMessageTapped != null) {
      _onChatMessageTapped!();
    }
    notifyListeners();
  }

  /// Set callback for transaction refresh (called from main.dart)
  void setTransactionRefreshCallback(Function(String address) callback) {
    _onTransactionTapped = callback;
  }

  /// Set callback for chat message tap (called from main.dart)
  void setChatMessageRefreshCallback(Function() callback) {
    _onChatMessageTapped = callback;
  }

  Future<void> loadWallet() async {
    try {
      _isLoading = true;
      notifyListeners();

      // Read with timeout to prevent hang on corrupted keystore
      _privateKey = await _storage.read(key: 'key').timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );

      _mnemonic = await _storage.read(key: 'mnemonic').timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );

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

  Future<void> saveWallet(String address, String privateKey, {String? mnemonic}) async {
    _privateKey = privateKey;
    _address = address;
    _mnemonic = mnemonic;
    await _storage.write(key: 'key', value: privateKey);
    if (mnemonic != null) {
      await _storage.write(key: 'mnemonic', value: mnemonic);
    }
    notifyListeners();
  }

  Future<void> deleteWallet() async {
    _privateKey = null;
    _address = null;
    _mnemonic = null;
    _balance = 0.0;
    _pendingBalance = 0.0;
    _isPending = false;
    _utxos = [];
    _pendingTxids.clear();
    _pendingTimestamps.clear();
    _pendingTransactions.clear();
    await _storage.delete(key: 'key');
    await _storage.delete(key: 'mnemonic');
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
      _isPending = false;
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

      // 1. Get all UTXOs (Confirmed + Mempool)
      // Note: In this project, _ws already handles RPC configuration internally
      final allUtxos = await _ws.getUtxos(_address!);

      // 2. Calculate confirmed balance
      _balance = _ws.calculateBalance(allUtxos);
      
      // 3. Calculate unconfirmed balance
      _pendingBalance = _ws.calculateUnconfirmedBalance(allUtxos);
      
      // Track if any mempool activity is going on
        _isPending = allUtxos.any((u) => u['confirmations'] == 0 || u['txid'] == 'pending_marker') ||
          _pendingTransactions.isNotEmpty;

      // Check if any of our locally tracked pending transactions are now confirmed or dropped
      final mempoolTxidsInUtxos = allUtxos
          .where((u) => u['confirmations'] == 0 && u['txid'] != 'pending_marker')
          .map((u) => u['txid'] as String)
          .toSet();

      final confirmedTxs = <String>[];
      for (final txid in _pendingTxids) {
        bool inConfirmedUtxos = allUtxos.any((u) => u['txid'] == txid && u['confirmations'] > 0);
        bool inMempool = mempoolTxidsInUtxos.contains(txid);
        
        if (inConfirmedUtxos) {
          confirmedTxs.add(txid);
        } else if (!inMempool) {
          // If it's not in mempool and not in confirmed UTXOs, it might be dropped.
          // We check the timestamp to give it some time to propagate before removing.
          final timestamp = _pendingTimestamps[txid];
          if (timestamp != null && DateTime.now().difference(timestamp).inMinutes > 30) {
            confirmedTxs.add(txid); // Mark for removal from local tracking
          }
        }
      }

      for (final txid in confirmedTxs) {
        _pendingTxids.remove(txid);
        _pendingTimestamps.remove(txid);
        _pendingTransactions.remove(txid);
      }

      // Also lock UTXOs consumed by our local pending transactions to prevent double-spending
      final lockedUtxos = <String>{};
      for (final pendingTx in _pendingTransactions.values) {
        for (final utxo in pendingTx.consumedUtxos) {
          lockedUtxos.add('${utxo['txid']}:${utxo['vout']}');
        }
      }

      // Filter out locally locked UTXOs and pending markers for internal storage
      // This list will be used by displayBalance
      _utxos = allUtxos.where((utxo) {
        final utxoId = '${utxo['txid']}:${utxo['vout']}';
        return utxo['txid'] != 'pending_marker' && !lockedUtxos.contains(utxoId);
      }).toList();

      debugPrint('💰 Wallet sync: ${_utxos.length} total UTXOs, Pending: $_isPending, Balance: $_balance');

      _lastFetch = DateTime.now();
      _lastError = null;
      if (_message.contains('Connection lost')) {
        _message = '';
      }

    } catch (e) {
      debugPrint('Error in fetchUtxos: $e');
      _lastError = 'Failed to fetch UTXOs: $e';
      _message = '⚠️ Connection lost. Displaying cached balances.';
    } finally {
      if (!silent) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

    Future<Map<String, dynamic>> sendTransaction(
      String address,
      double amount,
      {double? feeRate, bool isSweep = false, List<Map<String, dynamic>>? preSelectedUtxos}
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
    _message = '⏳ Sending transaction...';
    notifyListeners();

    final sendResult = await _ws.sendTransactionLocallySigned(
      privateKeyWif: _privateKey!,
      fromAddress: _address!,
      toAddress: address,
      amount: amount,
      feeRateOverride: feeRate,
      isSweep: isSweep,
      preSelectedUtxos: preSelectedUtxos,
    );

    if (!sendResult['success']) {
      _message = '❌ ${sendResult['message'] ?? 'Transaction failed'}';
      notifyListeners();
      _isCurrentlySending = false;
      return sendResult;
    }

    bool sentSuccessfully = false;
    try {
      if (sendResult['txid'] != null) {
        final txid = sendResult['txid'] as String;

        // Track pending transaction with consumed UTXOs
        _pendingTxids.add(txid);
        _pendingTimestamps[txid] = DateTime.now();
        _pendingTransactions[txid] = PendingTransaction(
          txid: txid,
          amount: amount,
          fee: sendResult['fee'],
          toAddress: address,
          timestamp: DateTime.now(),
          consumedUtxos: List<Map<String, dynamic>>.from(sendResult['consumedUtxos'] ?? []),
          changeAmount: sendResult['changeAmount'] ?? 0.0,
        );

        // Update local UTXOs immediately to reflect spent inputs and pending state
        await fetchUtxos(force: true, silent: true);

        // Notify listeners to update UI with new pending state
        notifyListeners();

        // Start smart confirmation checking
        _startSmartConfirmationChecking(txid);
        sentSuccessfully = true;

        return {
          'success': true,
          'txid': txid,
          'message': 'Transaction sent successfully',
          'fee': sendResult['fee'],
        };
      }

      // Handle error
      final errorMessage = sendResult['error']?['message'] ?? 'Unknown error';

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
      if (sentSuccessfully && sendResult['txid'] != null) {
        _message = '✅ Sent! TXID: ${sendResult['txid']}';
        notifyListeners();
        Future.delayed(const Duration(seconds: 5), () {
          if (_message.contains('✅')) {
            _message = '';
            notifyListeners();
          }
        });
      }
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

  Future<Map<String, dynamic>?> getNetworkInfo() async {
    return await _ws.getNetworkInfo();
  }

  Future<bool> migrateToSeed({int words = 12}) async {
    if (_privateKey == null || _address == null) return false;

    _isLoading = true;
    _message = '⏳ Generating new seed phrase...';
    notifyListeners();

    try {
      // 1. Generate new seed wallet

      // Refresh balance first
      await refreshBalance();
      final currentBalance = _balance ?? 0.0;

      final walletData = await _ws.generateNewSeedWallet(words: words);
      final mnemonic = walletData['mnemonic']!;
      final newAddress = walletData['address']!;
      final newWif = walletData['privateKey']!;

      if (currentBalance > 0.00001) {
        // 2. Sweep funds
        _message = '⏳ Sweeping funds to new address...';
        notifyListeners();
        final result = await sendTransaction(newAddress, currentBalance, isSweep: true);

        if (!result['success']) {
          _lastError = 'Migration failed: ${result['message']}';
          _message = '❌ Migration failed: ${result['message']}';
          _isLoading = false;
          notifyListeners();
          return false;
        }
      }

      // Save new wallet
      await saveWallet(newAddress, newWif, mnemonic: mnemonic);

      _message = currentBalance > 0
          ? '✅ Migration successful! Funds swept.'
          : '✅ Migration successful! (Empty wallet)';
      
      _isLoading = false;
      notifyListeners();

      Future.delayed(const Duration(seconds: 5), () {
        if (_message.contains('✅')) {
          _message = '';
          notifyListeners();
        }
      });
      return true;
    } catch (e) {
      _lastError = 'Migration error: $e';
      _message = '❌ Migration error: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
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