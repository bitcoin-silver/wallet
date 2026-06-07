import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:bip32/bip32.dart' as bip32;
import 'package:crypto/crypto.dart';
import 'package:bech32/bech32.dart';
import 'package:base_x/base_x.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:bitcoinsilver_wallet/config.dart';
import 'package:bitcoinsilver_wallet/services/rpc_config_service.dart';

class WalletService {
  final BaseXCodec base58 =
      BaseXCodec('123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz');
  final RpcConfigService _rpcConfig;

  WalletService(this._rpcConfig);

  RpcConfigService get rpcConfigService => _rpcConfig;

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

    final decoded = jsonDecode(response.body);
    //print('Response body: ${response.body}');

    return decoded; // ✅ Always return the parsed body
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
              'jsonrpc': '1.0',
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

    final List<Map<String, dynamic>> confirmedUtxos = [];
    if (result != null && result['result'] != null) {
      final unspents = result['result']['unspents'] as List<dynamic>? ?? [];
      for (var u in unspents) {
        confirmedUtxos.add({
          'txid': u['txid'],
          'vout': u['vout'],
          'amount': (u['amount'] as num).toDouble(),
          'height': u['height'],
          'confirmations': 1, // Will be updated if height is available
        });
      }
    }

    // 2. Get mempool txids
    final List<Map<String, dynamic>> decodedMempool = [];
    final mempoolResult = await rpcRequest('getrawmempool', [false]);
    
    if (mempoolResult != null && mempoolResult['result'] != null) {
      final List<dynamic> txids = mempoolResult['result'] as List<dynamic>;
      
      // Batch process mempool to find relevant transactions
      const batchSize = 25;
      for (int i = 0; i < txids.length; i += batchSize) {
        final chunk = txids.skip(i).take(batchSize).toList();
        final batchRequests = chunk.map((txid) => {
          'method': 'getrawtransaction',
          'params': [txid, true],
        }).toList();

        final batchResults = await batchRpcRequest(batchRequests);
        for (final res in batchResults) {
          if (res != null && res['result'] != null) {
            decodedMempool.add(res['result'] as Map<String, dynamic>);
          }
        }
      }
    }

    final List<Map<String, dynamic>> finalUtxos = [];
    bool hasMempoolActivity = false;

    // 3. Process Decoded Mempool (Detect spends and incoming)
    final spentInMempool = <String>{};
    final incomingFromMempool = <Map<String, dynamic>>[];

    for (var data in decodedMempool) {
      final String txid = data['txid'] ?? '';
      
      // Check inputs (detect our coins being spent)
      final vins = data['vin'] as List<dynamic>? ?? [];
      for (var vin in vins) {
        final String? vinTxid = vin['txid'];
        final dynamic vinVout = vin['vout'];
        if (vinTxid != null && vinVout != null) {
          spentInMempool.add('$vinTxid:$vinVout');
        }
      }

      // Check outputs (detect new funds or change)
      final vouts = data['vout'] as List<dynamic>? ?? [];
      for (var vout in vouts) {
        final scriptPubKey = vout['scriptPubKey'] as Map<String, dynamic>? ?? {};
        final String? singleAddr = scriptPubKey['address'];
        final List<dynamic> addresses = scriptPubKey['addresses'] as List<dynamic>? ?? [];
        
        if (singleAddr == address || addresses.contains(address)) {
          incomingFromMempool.add({
            'txid': txid,
            'vout': vout['n'] ?? 0,
            'amount': (vout['value'] as num? ?? 0.0).toDouble(),
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
}
