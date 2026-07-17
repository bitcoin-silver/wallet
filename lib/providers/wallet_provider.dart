import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bitcoinsilver_wallet/services/wallet_service.dart';
import 'package:bitcoinsilver_wallet/services/notification_service.dart';
import 'package:bitcoinsilver_wallet/services/btcs_signer.dart';

// Backend URL - HTTPS endpoint
const String backendUrl = 'https://bitcoinsilver.eu';

class WalletProvider with ChangeNotifier {
  static const String rpcUnavailableWarning =
      'RPC is unreachable right now. Balance display is affected until connection is restored.';
  static const bool _enableFeeDebugLogs = false; // Set to true to enable debug logs for fee estimation

  // Use default storage (compatible with Play Store signing)
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final WalletService _ws;
  late NotificationService _notificationService;
  Function(String address)? _onTransactionTapped;

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
  bool _isFetchingFeeRate = false;
  bool _feeRateReady = false;
  bool _usingManualFeeRate = false;
  String _feeRateSource = 'unavailable';
  double? _feeBaselineRate;
  double? _feeEstimatedRate;
  double? _feeSanityCeiling;
  String _feeRateStatusMessage = 'Fee estimate not requested yet.';
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
  bool get isFetchingFeeRate => _isFetchingFeeRate;
  bool get feeRateReady => _feeRateReady;
  bool get usingManualFeeRate => _usingManualFeeRate;
  String get feeRateSource => _feeRateSource;
  double? get feeBaselineRate => _feeBaselineRate;
  double? get feeEstimatedRate => _feeEstimatedRate;
  double? get feeSanityCeiling => _feeSanityCeiling;
  String get feeRateStatusMessage => _feeRateStatusMessage;

  // Backward-compatible aliases for existing debug UI paths.
  bool get feeEstimateAvailable => _feeRateReady;
  bool get isFeeEstimateLoading => _isFetchingFeeRate;
  String? get feeEstimateError => _feeRateReady ? null : _feeEstimateError;

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

  bool _looksLikeRpcFailureText(String text) {
    final normalized = text.toLowerCase();
    return normalized.contains('rpc') ||
        normalized.contains('timed out') ||
        normalized.contains('connection') ||
        normalized.contains('socketexception') ||
        normalized.contains('http status code') ||
        normalized.contains('not configured');
  }

  void _setRpcUnavailableWarning() {
    _rpcError = rpcUnavailableWarning;
    _message = '⚠️ $rpcUnavailableWarning';
  }

  void _clearRpcUnavailableWarningIfPresent() {
    if (_rpcError != null) {
      _rpcError = null;
    }
    if (_message.contains(rpcUnavailableWarning)) {
      _message = '';
    }
  }

  Future<bool> fetchFeeRate() async {
    _isFetchingFeeRate = true;
    _feeRateReady = false;
    _usingManualFeeRate = false;
    _feeRateSource = 'fetching';
    _feeBaselineRate = null;
    _feeEstimatedRate = null;
    _feeSanityCeiling = null;
    _feeRateStatusMessage = 'Fetching fee estimate from node...';
    _feeEstimateError = null;
    notifyListeners();

    try {
      final feeResult = await _ws.resolveFeeRate();

      if (feeResult['success'] == true) {
        _feeRate = (feeResult['feeRate'] as num).toDouble();
        _feeRateReady = true;
        _feeRateSource = (feeResult['source'] as String?) ?? 'estimated';
        _feeBaselineRate = (feeResult['baselineFeeRate'] as num?)?.toDouble();
        _feeEstimatedRate = (feeResult['estimatedFeeRate'] as num?)?.toDouble();
        _feeSanityCeiling = (feeResult['sanityCeiling'] as num?)?.toDouble();

        switch (_feeRateSource) {
          case 'clamped':
            if (_enableFeeDebugLogs) {
              debugPrint(
                '[fee] clamped estimator -> baseline '
                'est=${_feeEstimatedRate?.toStringAsFixed(8)} '
                'base=${_feeBaselineRate?.toStringAsFixed(8)} '
                'ceil=${_feeSanityCeiling?.toStringAsFixed(8)}',
              );
            }
            _feeRateStatusMessage =
                (feeResult['message'] as String?) ??
                'Smart fee outlier detected. Using node baseline fee.';
            break;
          case 'baseline':
            _feeRateStatusMessage =
                (feeResult['message'] as String?) ?? 'Using node baseline fee.';
            break;
          case 'manual':
            _feeRateStatusMessage =
                'Using manual fee rate (${_feeRate.toStringAsFixed(8)} BTCS/kvB).';
            break;
          case 'estimated':
          default:
            _feeRateStatusMessage = 'Fee estimate ready from node.';
            break;
        }

        _feeEstimateError = null;
        _clearRpcUnavailableWarningIfPresent();
        return true;
      }

      _feeRate = 0.0;
      _feeRateReady = false;
      _feeRateSource = 'unavailable';
      _feeBaselineRate = null;
      _feeEstimatedRate = null;
      _feeSanityCeiling = null;
      _feeRateStatusMessage =
          (feeResult['message'] as String?) ?? 'Fee estimation unavailable. Manual fee required.';
      _feeEstimateError = _feeRateStatusMessage;
      return false;
    } catch (_) {
      _feeRate = 0.0;
      _feeRateReady = false;
      _feeRateSource = 'unavailable';
      _feeBaselineRate = null;
      _feeEstimatedRate = null;
      _feeSanityCeiling = null;
      _feeRateStatusMessage = 'Fee estimation unavailable. Enter a manual fee when sending.';
      _feeEstimateError = _feeRateStatusMessage;
      _setRpcUnavailableWarning();
      return false;
    } finally {
      _isFetchingFeeRate = false;
      notifyListeners();
    }
  }

  void setManualFeeRate(double feeRateCoinPerKb) {
    _feeRate = feeRateCoinPerKb;
    _feeRateReady = true;
    _usingManualFeeRate = true;
    _feeRateSource = 'manual';
    _feeBaselineRate = null;
    _feeEstimatedRate = null;
    _feeSanityCeiling = null;
    _feeRateStatusMessage =
        'Using manual fee rate (${feeRateCoinPerKb.toStringAsFixed(8)} BTCS/kvB).';
    _feeEstimateError = null;
    notifyListeners();
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
  int get outgoingPendingCount => _pendingTransactions.length;
  int get incomingPendingCount => _utxos
      .where((u) =>
          u['confirmations'] == 0 &&
          !_pendingTransactions.containsKey(u['txid']) &&
          u['txid'] != 'pending_marker')
      .map((u) => u['txid'] as String)
      .toSet()
      .length;
  bool get hasOutgoingPendingTransactions => outgoingPendingCount > 0;
  bool get hasIncomingPendingTransactions => incomingPendingCount > 0;
  bool get hasPendingTransactions =>
      _isPending || hasOutgoingPendingTransactions || hasIncomingPendingTransactions;
  int get pendingTransactionsCount {
    final outgoing = outgoingPendingCount;
    final incoming = incomingPendingCount;

    // Ensure we at least show 1 if _isPending is true but UTXOs aren't visible yet
    final count = outgoing + incoming;
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

  WalletProvider() : _ws = WalletService() {
    _notificationService = NotificationService(
      backendUrl: backendUrl,
      onTransactionReceived: _handleTransactionReceived,
      onNotificationTapped: _handleNotificationTapped,
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

  /// Set callback for transaction refresh (called from main.dart)
  void setTransactionRefreshCallback(Function(String address) callback) {
    _onTransactionTapped = callback;
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
    final previousPrivateKey = _privateKey;
    final previousAddress = _address;
    final previousMnemonic = _mnemonic;

    try {
      await _storage.write(key: 'key', value: privateKey);
      if (mnemonic != null) {
        await _storage.write(key: 'mnemonic', value: mnemonic);
      } else {
        await _storage.delete(key: 'mnemonic');
      }

      _privateKey = privateKey;
      _address = address;
      _mnemonic = mnemonic;

      // Switching wallet identity must also reset transient balance/pending state
      // so previous wallet activity does not leak into the new wallet UI.
      _balance = 0.0;
      _pendingBalance = 0.0;
      _isPending = false;
      _utxos = [];
      _pendingTxids.clear();
      _pendingTimestamps.clear();
      _pendingTransactions.clear();
      _availableUtxos = [];
      _selectedUtxoKeys.clear();
      _isLoadingUtxos = false;
      _utxoPage = 0;
      _lastFetch = null;

      notifyListeners();
    } catch (_) {
      // Attempt to restore previously persisted wallet data on partial writes.
      try {
        if (previousPrivateKey != null) {
          await _storage.write(key: 'key', value: previousPrivateKey);
        } else {
          await _storage.delete(key: 'key');
        }

        if (previousMnemonic != null) {
          await _storage.write(key: 'mnemonic', value: previousMnemonic);
        } else {
          await _storage.delete(key: 'mnemonic');
        }
      } catch (_) {
        // Keep original failure as the surfaced error.
      }

      _privateKey = previousPrivateKey;
      _address = previousAddress;
      _mnemonic = previousMnemonic;
      notifyListeners();
      rethrow;
    }
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

  Future<void> fetchUtxos({
    bool force = false,
    bool silent = false,
    bool allowRpcRecoveryRetry = true,
  }) async {
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

      // Check if any of our locally tracked pending transactions are now confirmed or dropped
      final mempoolTxidsInUtxos = allUtxos
          .where((u) => u['confirmations'] == 0 && u['txid'] != 'pending_marker')
          .map((u) => u['txid'] as String)
          .toSet();

      final confirmedTxs = <String>[];
      for (final txid in _pendingTxids) {
        bool inConfirmedUtxos = allUtxos.any((u) => u['txid'] == txid && u['confirmations'] > 0);
        bool inMempool = mempoolTxidsInUtxos.contains(txid);
        bool rpcConfirmed = false;

        if (!inConfirmedUtxos) {
          try {
            final txResult = await _ws.rpcRequest('getrawtransaction', [txid, true]);
            final confirmations = (txResult?['result']?['confirmations'] as num?)?.toInt() ?? 0;
            rpcConfirmed = confirmations > 0;
          } catch (_) {
            // Ignore RPC lookup failures here and fall back to mempool/timeout logic.
          }
        }
        
        if (inConfirmedUtxos || rpcConfirmed) {
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

      // Recompute pending state after local pending transaction cleanup so
      // confirmed sends do not leave the UI stuck in a pending state.
      _isPending = allUtxos.any((u) =>
              u['confirmations'] == 0 || u['txid'] == 'pending_marker') ||
          _pendingTransactions.isNotEmpty;

      debugPrint('💰 Wallet sync: ${_utxos.length} total UTXOs, Pending: $_isPending, Balance: $_balance');

      _lastFetch = DateTime.now();
      _lastError = null;
      _clearRpcUnavailableWarningIfPresent();
      if (_message.contains('Connection lost')) {
        _message = '';
      }

    } catch (e) {
      debugPrint('Error in fetchUtxos: $e');

      if (allowRpcRecoveryRetry) {
        final recovered = await _attemptRpcRecovery();
        if (recovered) {
          return fetchUtxos(
            force: true,
            silent: silent,
            allowRpcRecoveryRetry: false,
          );
        }
      }

      _lastError = 'Failed to fetch UTXOs: $e';
      _setRpcUnavailableWarning();
    } finally {
      if (!silent) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

    Future<bool> _attemptRpcRecovery() async {
      for (final delay in [
        const Duration(milliseconds: 500),
        const Duration(seconds: 1, milliseconds: 500),
      ]) {
        await Future.delayed(delay);
        try {
          await _ws.rpcRequest('getblockchaininfo');
          _clearRpcUnavailableWarningIfPresent();
          return true;
        } catch (_) {
          // try next delay
        }
      }
      _setRpcUnavailableWarning();
      return false;
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

    try {
      await _ws.rpcRequest('getblockchaininfo');
      _clearRpcUnavailableWarningIfPresent();
    } catch (_) {
      _setRpcUnavailableWarning();
      notifyListeners();
      _isCurrentlySending = false;
      return {
        'success': false,
        'message': rpcUnavailableWarning,
      };
    }

    Map<String, dynamic> sendResult;
    try {
      sendResult = await _ws.sendTransactionLocallySigned(
        privateKeyWif: _privateKey!,
        fromAddress: _address!,
        toAddress: address,
        amount: amount,
        feeRateOverride: feeRate,
        isSweep: isSweep,
        preSelectedUtxos: preSelectedUtxos,
      );
    } catch (e) {
      _setRpcUnavailableWarning();
      notifyListeners();
      _isCurrentlySending = false;
      return {
        'success': false,
        'message': rpcUnavailableWarning,
      };
    }

    if (!sendResult['success']) {
      final sendMessage = (sendResult['message'] ?? 'Transaction failed').toString();
      if ((sendResult['rpcUnavailable'] == true) || _looksLikeRpcFailureText(sendMessage)) {
        _setRpcUnavailableWarning();
      } else if (_rpcError != null) {
        _clearRpcUnavailableWarningIfPresent();
      }
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

  Future<bool> runMigrationStoragePreflight() async {
    try {
      await _storage.write(
        key: 'migration_preflight',
        value: DateTime.now().toIso8601String(),
      );
      await _storage.delete(key: 'migration_preflight');
      return true;
    } catch (e) {
      _lastError = 'Migration failed: secure storage is unavailable. $e';
      return false;
    }
  }

  @Deprecated('Legacy direct migration path. Use staged migration flow in SettingsView._showMigrationDialog.')
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

      // Ensure secure storage is writable before any irreversible sweep step.
      try {
        await _storage.write(key: 'migration_preflight', value: DateTime.now().toIso8601String());
        await _storage.delete(key: 'migration_preflight');
      } catch (e) {
        _lastError = 'Migration failed: secure storage is unavailable. $e';
        _message = '❌ Migration failed: secure storage unavailable.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (currentBalance > 0.00001) {
        final migrationUtxos = _utxos
            .where((u) =>
                u['txid'] != 'pending_marker' &&
                (u['confirmations'] as int? ?? 0) > 0)
            .map((u) => Map<String, dynamic>.from(u as Map))
            .toList();
        if (migrationUtxos.isEmpty) {
          _lastError = 'Migration failed: no confirmed UTXOs available to sweep.';
          _message = '❌ Migration failed: no confirmed UTXOs available to sweep.';
          _isLoading = false;
          notifyListeners();
          return false;
        }

        // Resolve fee once and pass it explicitly to sweep send for deterministic behavior.
        final migrationFeeResolution = await _ws.resolveFeeRate();
        if (migrationFeeResolution['success'] != true) {
          final reason = (migrationFeeResolution['message'] as String?) ??
              'Could not establish a safe fee rate.';
          _lastError = 'Migration failed: $reason';
          _message = '❌ Migration failed: $reason';
          _isLoading = false;
          notifyListeners();
          return false;
        }

        final migrationFeeRate =
            (migrationFeeResolution['feeRate'] as num).toDouble();
        _feeRate = migrationFeeRate;
        _feeRateReady = true;
        _usingManualFeeRate = (migrationFeeResolution['source'] as String?) == 'manual';
        _feeRateSource = (migrationFeeResolution['source'] as String?) ?? 'estimated';
        _feeBaselineRate =
            (migrationFeeResolution['baselineFeeRate'] as num?)?.toDouble();
        _feeEstimatedRate =
            (migrationFeeResolution['estimatedFeeRate'] as num?)?.toDouble();
        _feeSanityCeiling =
            (migrationFeeResolution['sanityCeiling'] as num?)?.toDouble();

        final estimatedSweepVbytes = 11 + (migrationUtxos.length * 68) + 31;
        final estimatedFee =
            double.parse((migrationFeeRate * estimatedSweepVbytes / 1000).toStringAsFixed(8));
        if (currentBalance <= estimatedFee + 0.00000546) {
          _lastError =
              'Migration failed: insufficient balance after fees. '
              'Estimated fee is ${estimatedFee.toStringAsFixed(8)} BTCS.';
          _message =
              '❌ Migration failed: insufficient balance after fees. '
              'Estimated fee is ${estimatedFee.toStringAsFixed(8)} BTCS.';
          _isLoading = false;
          notifyListeners();
          return false;
        }

        // 2. Sweep funds
        _message = '⏳ Sweeping funds to new address...';
        notifyListeners();
        final result = await sendTransaction(
          newAddress,
          currentBalance,
          feeRate: migrationFeeRate,
          isSweep: true,
          preSelectedUtxos: migrationUtxos,
        );

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