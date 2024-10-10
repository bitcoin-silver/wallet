import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:bip32/bip32.dart' as bip32;
import 'package:crypto/crypto.dart';
import 'package:bech32/bech32.dart';
import 'package:base_x/base_x.dart';
import 'package:bitcoinsilver_wallet/config.dart';

class WalletService {
  final BaseXCodec base58 =
      BaseXCodec('123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz');

  String? generatePrivateKey() {
    String? key;
    final seed = List<int>.generate(32, (i) => Random.secure().nextInt(256));
    final root = bip32.BIP32.fromSeed(Uint8List.fromList(seed));
    final child = root.derivePath('m/0/0');
    key = _privateKeyToWif(child.privateKey!);
    return key;
  }

  String? loadAddressFromKey(String wifPrivateKey) {
    try {
      final privateKey = _wifToPrivateKey(wifPrivateKey);
      final node = bip32.BIP32.fromPrivateKey(privateKey, Uint8List(32));
      final pubKey = node.publicKey;
      final pubKeyHash = _pubKeyToP2WPKH(pubKey);

      return _encodeBech32Address(Config.addressPrefix, 0, pubKeyHash);
    } catch (e, stacktrace) {
      print('Error recovering address from WIF: $e');
      print(stacktrace);
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
      print(
          'Checksum mismatch: expected $checksum but got $calculatedChecksum');
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

  Future<Map<String, dynamic>?> rpcRequest(String method,
      [List<dynamic>? params]) async {
    const rpcUrl = Config.rpcUrl;
    const rpcUser = Config.rpcUser;
    const rpcPassword = Config.rpcPassword;

    final auth = 'Basic ${base64Encode(utf8.encode('$rpcUser:$rpcPassword'))}';
    final headers = {'Content-Type': 'application/json', 'Authorization': auth};

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
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      print('RPC Call Error: ${response.statusCode} ${response.reasonPhrase}');
      print('Response body: ${response.body}');
      return null;
    }
  }
}
