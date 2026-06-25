import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:bip32/bip32.dart' as bip32;
import 'package:crypto/crypto.dart';
import 'package:bech32/bech32.dart';
import 'package:base_x/base_x.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:hex/hex.dart';
import 'package:bitcoinsilver_wallet/config.dart';
import 'package:bitcoinsilver_wallet/services/rpc_config_service.dart';
import 'package:bitcoinsilver_wallet/services/btcs_signer.dart';

class WalletService {
  final BaseXCodec base58 =
      BaseXCodec('123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz');
  final RpcConfigService _rpcConfig;

  WalletService(this._rpcConfig);

  String? generatePrivateKey() {
    final random = Random.secure();
    final privateKeyBytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      privateKeyBytes[i] = random.nextInt(256);
    }
    return _privateKeyToWif(privateKeyBytes);
  }

  // Generate a new Seed Phrase wallet
  Future<Map<String, String>> generateNewSeedWallet({int words = 12}) async {
    final int strength = words == 24 ? 256 : 128;
    final mnemonic = bip39.generateMnemonic(strength: strength);
    return (await getWalletFromMnemonic(mnemonic))!;
  }

  Future<Map<String, String>?> getWalletFromMnemonic(String mnemonic) async {
    if (!bip39.validateMnemonic(mnemonic)) return null;

    final seed = bip39.mnemonicToSeed(mnemonic);
    final root = bip32.BIP32.fromSeed(seed);

    // BIP44 path for BitcoinSilver
    final child = root.derivePath("m/44'/0'/0'/0/0");
    final privateKey = child.privateKey!;

    final wif = _privateKeyToWif(privateKey);
    final address = loadAddressFromKey(wif);

    return {
      'mnemonic': mnemonic,
      'privateKey': wif,
      'address': address ?? '',
    };
  }

  String? loadAddressFromKey(String wifPrivateKey) {
    try {
      final privateKey = _wifToPrivateKey(wifPrivateKey);
      final node = bip32.BIP32.fromPrivateKey(privateKey, Uint8List(32));
      final pubKey = node.publicKey;
      final pubKeyHash = _pubKeyToP2WPKH(pubKey);

      return _encodeBech32Address(Config.addressPrefix, 0, pubKeyHash);
    } catch (e) {
      //print('Error recovering address from WIF: $e');
      return null;
    }
  }

  String _privateKeyToWif(Uint8List privateKey) {
    final prefix = Uint8List.fromList([Config.networkPrefix]);
    final compressedKey =
        Uint8List.fromList(prefix + privateKey.toList() + [0x01]);
    final checksum = _calculateChecksum(compressedKey);
    final keyWithChecksum = Uint8List.fromList(compressedKey + checksum);

    return base58.encode(keyWithChecksum);
  }

  Uint8List _wifToPrivateKey(String wif) {
    final bytes = base58.decode(wif);
    final keyWithChecksum = bytes.sublist(0, bytes.length - 4);
    final checksum = bytes.sublist(bytes.length - 4);

    final calculatedChecksum = _calculateChecksum(keyWithChecksum);
    if (!_listEquals(checksum, calculatedChecksum)) {
      //print('Checksum mismatch: expected $checksum but got $calculatedChecksum');
      throw Exception('Invalid WIF checksum');
    }

    return Uint8List.fromList(keyWithChecksum.sublist(
        1, keyWithChecksum.length - (keyWithChecksum.length > 32 ? 1 : 0)));
  }

  Uint8List _calculateChecksum(Uint8List data) {
    final sha256_1 = sha256.convert(data).bytes;
    final sha256_2 = sha256.convert(Uint8List.fromList(sha256_1)).bytes;
    return Uint8List.fromList(sha256_2.sublist(0, 4));
  }

  Uint8List _pubKeyToP2WPKH(List<int> pubKey) {
    final sha256Hash = sha256.convert(pubKey).bytes;
    final ripemd160Hash =
        RIPEMD160Digest().process(Uint8List.fromList(sha256Hash));
    return Uint8List.fromList(ripemd160Hash);
  }

  String _encodeBech32Address(String hrp, int version, Uint8List program) {
    final converted = _convertBits(program, 8, 5, true);
    final data = [version] + converted;
    return const Bech32Codec().encode(Bech32(hrp, data));
  }

  List<int> _convertBits(List<int> data, int from, int to, bool pad) {
    int acc = 0, bits = 0;
    final ret = <int>[];
    final maxv = (1 << to) - 1;

    for (final value in data) {
      if (value < 0 || (value >> from) != 0) throw Exception('Invalid value');
      acc = (acc << from) | value;
      bits += from;
      while (bits >= to) {
        bits -= to;
        ret.add((acc >> bits) & maxv);
      }
    }

    if (pad && bits > 0) ret.add((acc << (to - bits)) & maxv);
    if (!pad && (bits >= from || ((acc << (to - bits)) & maxv) != 0)) {
      throw Exception('Invalid padding');
    }
    return ret;
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<Map<String, dynamic>?> rpcRequest(
    String method,
    [List<dynamic>? params,
  ]) async {
    final rpcUrl = _rpcConfig.getActiveRpcUrl();
    final rpcUser = _rpcConfig.getActiveRpcUser();
    final rpcPassword = _rpcConfig.getActiveRpcPassword();

    if (rpcUrl == null || rpcUrl.isEmpty) {
      throw Exception('Active RPC URL not set');
    }

    Map<String, String> headers = {'Content-Type': 'application/json'};
    if (rpcUser != null && rpcUser.isNotEmpty && rpcPassword != null && rpcPassword.isNotEmpty) {
      final auth = 'Basic ${base64Encode(utf8.encode('$rpcUser:$rpcPassword'))}';
      headers['Authorization'] = auth;
    }

    final body = jsonEncode({
      'jsonrpc': '1.0',
      'id': 'curltext',
      'method': method,
      'params': params ?? [],
    });

    try {
      final response = await http.post(
        Uri.parse(rpcUrl),
        headers: headers,
        body: body,
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw Exception('RPC request timed out after 30 seconds');
        },
      );

      if (response.statusCode != 200) {
        throw Exception('Server returned HTTP status code: ${response.statusCode}');
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      throw Exception('Invalid RPC response format received');
    } catch (_) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>?>> batchRpcRequest(
      List<Map<String, dynamic>> requests,
  ) async {
    final rpcUrl = _rpcConfig.getActiveRpcUrl();
    final rpcUser = _rpcConfig.getActiveRpcUser();
    final rpcPassword = _rpcConfig.getActiveRpcPassword();

    if (rpcUrl == null || rpcUrl.isEmpty) {
      throw Exception('Active RPC URL not set');
    }

    Map<String, String> headers = {'Content-Type': 'application/json'};
    if (rpcUser != null && rpcUser.isNotEmpty && rpcPassword != null && rpcPassword.isNotEmpty) {
      final auth = 'Basic ${base64Encode(utf8.encode('$rpcUser:$rpcPassword'))}';
      headers['Authorization'] = auth;
    }

    // Build batch request body
    final batchBody = requests
        .asMap()
        .entries
        .map((entry) => {
              'jsonrpc': '2.0',
              'id': entry.key,
              'method': entry.value['method'],
              'params': entry.value['params'] ?? [],
            })
        .toList();

    final response = await http.post(
      Uri.parse(rpcUrl),
      headers: headers,
      body: jsonEncode(batchBody),
    ).timeout(
      const Duration(seconds: 45),
      onTimeout: () {
        throw Exception('Batch RPC request timed out after 45 seconds');
      },
    );

    final decoded = jsonDecode(response.body);

    // Handle both single and batch responses
    if (decoded is List) {
      return decoded.cast<Map<String, dynamic>?>();
    } else {
      return [decoded as Map<String, dynamic>?];
    }
  }

  Future<Map<String, dynamic>?> getNetworkInfo() async {
    try {
      final blockchainInfo = await rpcRequest('getblockchaininfo');
      final networkInfo = await rpcRequest('getnetworkinfo');
      final mempoolInfo = await rpcRequest('getmempoolinfo');
      final miningInfo = await rpcRequest('getmininginfo');

      if (blockchainInfo == null) return null;

      return {
        'blocks': blockchainInfo['result']?['blocks'],
        'difficulty': blockchainInfo['result']?['difficulty'],
        'bestblockhash': blockchainInfo['result']?['bestblockhash'],
        'mediantime': blockchainInfo['result']?['mediantime'],
        'version': networkInfo?['result']?['version'],
        'subversion': networkInfo?['result']?['subversion'],
        'connections': networkInfo?['result']?['connections'],
        'mempool_size': mempoolInfo?['result']?['size'],
        'mempool_bytes': mempoolInfo?['result']?['bytes'],
        'networkhashps': miningInfo?['result']?['networkhashps'],
      };
    } catch (e) {
      return null;
    }
  }

  // Get UTXOs for address - ported from debug/lib/services/wallet_service.dart
  Future<List<Map<String, dynamic>>> getUtxos(String address) async {
    // 1. Get confirmed UTXOs from the chain
    final result = await rpcRequest('scantxoutset', [
      'start',
      [{'desc': 'addr($address)'}]
    ]);

    // Fetch current block height to compute real confirmations.
    int currentHeight = 0;
    final blockCountResult = await rpcRequest('getblockcount');
    if (blockCountResult != null && blockCountResult['result'] != null) {
      currentHeight = (blockCountResult['result'] as num).toInt();
    }

    final List<Map<String, dynamic>> confirmedUtxos = [];
    if (result != null && result['result'] != null) {
      final unspents = result['result']['unspents'] as List<dynamic>? ?? [];
      for (var u in unspents) {
        final int utxoHeight = (u['height'] as num?)?.toInt() ?? 0;
        final int conf = currentHeight > 0 && utxoHeight > 0
            ? currentHeight - utxoHeight + 1
            : 1;
        confirmedUtxos.add({
          'txid': u['txid'],
          'vout': u['vout'],
          'amount': (u['amount'] is num)
              ? (u['amount'] as num).toDouble()
              : double.tryParse(u['amount'].toString()) ?? 0.0,
          'height': utxoHeight,
          'confirmations': conf,
        });
      }
    }

    // 2. Get mempool txids
    final List<Map<String, dynamic>> decodedMempool = [];
    bool rpcMempoolSucceeded = false;
    final mempoolResult = await rpcRequest('getrawmempool', [false]);

    if (mempoolResult != null && mempoolResult['result'] != null) {
      rpcMempoolSucceeded = true;
      final List<dynamic> txids = mempoolResult['result'] as List<dynamic>;

      // Use individual calls as in the working debug implementation
      // but with Future.wait for better performance
      const maxConcurrent = 10;
      for (int i = 0; i < txids.length; i += maxConcurrent) {
        final chunk = txids.skip(i).take(maxConcurrent).toList();
        final tasks = chunk.map((txid) => rpcRequest('getrawtransaction', [txid, true]));
        final results = await Future.wait(tasks);
        
        for (final res in results) {
          if (res != null && res['result'] != null) {
            decodedMempool.add(res['result'] as Map<String, dynamic>);
          }
        }
      }
    }

    // Fallback: ONLY if RPC failed (not if mempool was just empty)
    if (!rpcMempoolSucceeded) {
      try {
        // Try to get mempool from explorer if RPC fails
        final explorerResponse = await http.get(Uri.parse('${Config.explorerUrl}/api/mempool')).timeout(const Duration(seconds: 10));
        if (explorerResponse.statusCode == 200) {
          final decoded = jsonDecode(explorerResponse.body);
          final List<dynamic> explorerTxs = (decoded is List) ? decoded : (decoded['transactions'] ?? []);
          for (var tx in explorerTxs) {
            decodedMempool.add(tx as Map<String, dynamic>);
          }
        }
      } catch (e) {
        debugPrint('Explorer mempool fallback failed: $e');
      }
    }

    final List<Map<String, dynamic>> finalUtxos = [];
    bool hasMempoolActivity = false;

    // 3. Process Decoded Mempool (Detect spends and incoming)
    final spentInMempool = <String>{};
    final incomingFromMempool = <Map<String, dynamic>>[];

    debugPrint('Processing ${decodedMempool.length} mempool transactions for $address');

    for (var data in decodedMempool) {
      final String txid = data['txid'] ?? '';

      // Check inputs (detect our coins being spent) Safely!
      final vins = data['vin'] as List<dynamic>? ?? [];
      for (var vin in vins) {
        final String? vinTxid = vin['txid'] ?? vin['prev_txid'];
        final dynamic vinVout = vin['vout'] ?? vin['prev_vout'];
        if (vinTxid != null && vinVout != null) {
          spentInMempool.add('$vinTxid:$vinVout');
        }
      }

      // Check outputs (detect new funds or change)
      final vouts = data['vout'] as List<dynamic>? ?? [];
      for (var vout in vouts) {
        final scriptPubKey = vout['scriptPubKey'] as Map<String, dynamic>? ?? {};
        final addresses = scriptPubKey['addresses'] as List<dynamic>? ?? [];
        final String? singleAddr = scriptPubKey['address'] as String?;

        if (addresses.contains(address) || (singleAddr != null && singleAddr == address)) {
          // Safe numeric parsing for RPC/Explorer variants (num or string).
          double parsedAmount = 0.0;
          final rawValue = vout['value'];
          if (rawValue is num) {
            parsedAmount = rawValue.toDouble();
          } else if (rawValue is String) {
            parsedAmount = double.tryParse(rawValue) ?? 0.0;
          }

          incomingFromMempool.add({
            'txid': txid,
            'vout': vout['n'] ?? 0,
            'amount': parsedAmount,
            'confirmations': 0,
          });
          hasMempoolActivity = true;
        }
      }
    }

    // 4. Merge Confirmed and Mempool
    for (var utxo in confirmedUtxos) {
      final outpoint = '${utxo['txid']}:${utxo['vout']}';
      if (spentInMempool.contains(outpoint)) {
        hasMempoolActivity = true; // Flag that a confirmed coin is being spent
      } else {
        finalUtxos.add(utxo);
      }
    }
    finalUtxos.addAll(incomingFromMempool);

    // 5. Final Force-Yellow logic
    if (hasMempoolActivity && !finalUtxos.any((u) => u['confirmations'] == 0)) {
      finalUtxos.add({
        'txid': 'pending_marker',
        'amount': 0.0,
        'confirmations': 0,
      });
    }

    return finalUtxos;
  }

  // Ported from debug folder
  double calculateBalance(List<Map<String, dynamic>> utxos) {
    return utxos
        .where((u) =>
            u['txid'] != 'pending_marker' &&
            (u['confirmations'] as int) > 0)
        .fold(0.0, (sum, u) => sum + (u['amount'] as double));
  }

  double calculateUnconfirmedBalance(List<Map<String, dynamic>> utxos) {
    return utxos
        .where((u) =>
            u['txid'] != 'pending_marker' &&
            (u['confirmations'] as int) == 0)
        .fold(0.0, (sum, u) => sum + (u['amount'] as double));
  }

  Future<Map<String, dynamic>> sendTransactionLocallySigned({
    required String privateKeyWif,
    required String fromAddress,
    required String toAddress,
    required double amount,
    List<Map<String, dynamic>>? preSelectedUtxos,
    double? feeRateOverride,
    bool isSweep = false,
  }) async {
    final allUtxos = await getUtxos(fromAddress);
    final utxos = (preSelectedUtxos != null && preSelectedUtxos.isNotEmpty)
        ? preSelectedUtxos.map((u) => Map<String, dynamic>.from(u)).toList()
        : allUtxos
            .where((u) =>
                u['txid'] != 'pending_marker' &&
                (u['confirmations'] as int) > 0)
            .map((u) => Map<String, dynamic>.from(u))
            .toList();

    if (utxos.isEmpty) {
      final hasPending = allUtxos.any(
        (u) => u['txid'] != 'pending_marker' && (u['confirmations'] as int) == 0,
      );
      return {
        'success': false,
        'message': hasPending
            ? 'Your funds are pending confirmation. Please wait approximately 10 minutes before sending again.'
            : 'No confirmed funds available. Please wait approximately 10 minutes for your deposit to confirm.',
      };
    }

    for (final utxo in utxos) {
      if (utxo['scriptPubKey'] == null || (utxo['scriptPubKey'] as String).isEmpty) {
        try {
          final txOut = await rpcRequest('gettxout', [utxo['txid'], utxo['vout']]);
          if (txOut?['result']?['scriptPubKey']?['hex'] != null) {
            utxo['scriptPubKey'] = txOut!['result']['scriptPubKey']['hex'] as String;
          }
        } catch (_) {}
      }

      if (utxo['scriptPubKey'] == null || (utxo['scriptPubKey'] as String).isEmpty) {
        try {
          final generatedScript = BTCSSigner.scriptFromAddress(fromAddress);
          utxo['scriptPubKey'] = HEX.encode(generatedScript);
        } catch (_) {
          return {
            'success': false,
            'message': 'Could not resolve scriptPubKey for UTXO ${utxo['txid']}.',
          };
        }
      }
    }

    final totalAvailable =
        utxos.fold(0.0, (sum, u) => sum + (u['amount'] as num).toDouble());
    final bool shouldSweep = isSweep || amount >= totalAvailable - 0.00001;

    utxos.sort((a, b) =>
        ((b['amount'] as num).toDouble()).compareTo((a['amount'] as num).toDouble()));

    double feeRate;
    if (feeRateOverride != null) {
      if (feeRateOverride <= 0) {
        return {
          'success': false,
          'message': 'Invalid manual fee rate provided.',
          'feeEstimateRequired': true,
        };
      }
      feeRate = feeRateOverride;
    } else {
      try {
        final r = await rpcRequest('estimatesmartfee', [6]);

        if (r?['error'] != null) {
          final rpcMsg = r!['error']['message'] as String? ?? 'RPC fee estimation error';
          return {
            'success': false,
            'message': rpcMsg,
            'feeEstimateRequired': true,
            'feeEstimateError': rpcMsg,
          };
        }

        final result = r?['result'];
        if (result is! Map<String, dynamic>) {
          return {
            'success': false,
            'message': 'Fee estimation returned an invalid response.',
            'feeEstimateRequired': true,
          };
        }

        final feerateRaw = result['feerate'];
        if (feerateRaw is! num) {
          final errors = result['errors'];
          final details = (errors is List && errors.isNotEmpty)
              ? errors.join(', ')
              : 'No fee rate was returned by the node.';
          return {
            'success': false,
            'message': details,
            'feeEstimateRequired': true,
            'feeEstimateError': details,
          };
        }

        final estimatedFeeRate = feerateRaw.toDouble();
        if (estimatedFeeRate <= 0) {
          final errors = result['errors'];
          final details = (errors is List && errors.isNotEmpty)
              ? errors.join(', ')
              : 'Node could not estimate a valid fee rate.';
          return {
            'success': false,
            'message': details,
            'feeEstimateRequired': true,
            'feeEstimateError': details,
          };
        }

        feeRate = estimatedFeeRate;
      } catch (e) {
        return {
          'success': false,
          'message': 'RPC fee estimation failed: $e',
          'feeEstimateRequired': true,
          'feeEstimateError': 'RPC fee estimation failed: $e',
        };
      }
    }

    final selectedUtxos = <Map<String, dynamic>>[];
    double inputSum = 0.0;

    for (int i = 0; i < utxos.length; i++) {
      selectedUtxos.add(utxos[i]);
      inputSum += (utxos[i]['amount'] as num).toDouble();

      if (shouldSweep && i < utxos.length - 1) {
        continue;
      }

      final inputCount = selectedUtxos.length;
      final bool isDestLegacy = !toAddress.toLowerCase().startsWith(Config.addressPrefix);
      final int destOutputSize = isDestLegacy ? 34 : 31;
      const int changeOutputSize = 31;

      int txSize = 11 + (inputCount * 68);
      if (shouldSweep) {
        txSize += destOutputSize;
      } else {
        txSize += destOutputSize + changeOutputSize;
      }

      final actualFee = double.parse((feeRate * txSize / 1000).toStringAsFixed(8));
      final needed = shouldSweep ? actualFee : amount + actualFee;
      if (inputSum < needed) {
        continue;
      }

      final inputs = selectedUtxos.map((u) {
        String? scriptHex = u['scriptPubKey'] as String?;
        if (scriptHex == null || scriptHex.isEmpty) {
          try {
            final computedScript = BTCSSigner.scriptFromAddress(fromAddress);
            scriptHex = HEX.encode(computedScript);
          } catch (_) {
            scriptHex = '';
          }
        }

        return BTCSTxInput(
          txid: u['txid'] as String,
          vout: u['vout'] as int,
          scriptPubKey: Uint8List.fromList(HEX.decode(scriptHex)),
          satoshis: ((u['amount'] as num).toDouble() * 1e8).round(),
        );
      }).toList();

      final outputs = <BTCSTxOutput>[];
      int changeSats = 0;
      int sendSats = 0;
      try {
        if (shouldSweep) {
          final sweepSats = ((inputSum - actualFee) * 1e8).round();
          if (sweepSats <= 546) {
            return {'success': false, 'message': 'Balance too low to cover fees.'};
          }
          sendSats = sweepSats;
          outputs.add(BTCSTxOutput(
            scriptPubKey: BTCSSigner.scriptFromAddress(toAddress),
            satoshis: sweepSats,
          ));
        } else {
          sendSats = (amount * 1e8).round();
          outputs.add(BTCSTxOutput(
            scriptPubKey: BTCSSigner.scriptFromAddress(toAddress),
            satoshis: sendSats,
          ));

          changeSats = ((inputSum - amount - actualFee) * 1e8).round();
          if (changeSats > 546) {
            outputs.add(BTCSTxOutput(
              scriptPubKey: BTCSSigner.scriptFromAddress(fromAddress),
              satoshis: changeSats,
            ));
          }
        }
      } catch (_) {
        return {'success': false, 'message': 'Invalid destination address provided.'};
      }

      String signedHex;
      try {
        signedHex = BTCSSigner.signTransaction(
          inputs: inputs,
          outputs: outputs,
          wif: privateKeyWif,
        );
      } catch (e) {
        return {'success': false, 'message': 'Signing failed: $e'};
      }

      final sendResult = await rpcRequest('sendrawtransaction', [signedHex, 0]);

      if (sendResult?['result'] != null) {
        return {
          'success': true,
          'txid': sendResult!['result'],
          'fee': actualFee,
          'consumedUtxos': selectedUtxos
              .map((u) => {
                    'txid': u['txid'],
                    'vout': u['vout'],
                    'amount': (u['amount'] as num).toDouble(),
                  })
              .toList(),
          'changeAmount': changeSats > 0 ? changeSats / 1e8 : 0.0,
          'sentAmount': sendSats / 1e8,
        };
      }

      final errMsg = sendResult?['error']?['message'] as String? ?? 'Unknown error';
      final feeRateMatch = RegExp(r'new feerate ([\d.]+) BTCS/kvB').firstMatch(errMsg);
      if (feeRateMatch != null) {
        final suggestedFeeRate = double.parse(feeRateMatch.group(1)!);
        return {
          'success': false,
          'message': 'Fee too low',
          'suggestedFeeRate': suggestedFeeRate,
          'currentFeeRate': feeRate,
        };
      }

      if (errMsg.contains('insufficient fee') || errMsg.contains('rejecting replacement')) {
        return {
          'success': false,
          'message': 'You have a pending transaction. Please wait approximately 20 minutes before sending another.',
        };
      }

      return {'success': false, 'message': errMsg};
    }

    return {
      'success': false,
      'message': 'Insufficient funds. Available: ${inputSum.toStringAsFixed(8)} BTCS.',
    };
  }
}
