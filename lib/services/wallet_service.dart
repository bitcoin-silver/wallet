import 'dart:typed_data';
import 'dart:math';
import 'package:hex/hex.dart';
import 'package:crypto/crypto.dart';
import 'package:convert/convert.dart';
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:bech32/bech32.dart';
import 'package:bip32/bip32.dart' as bip32;

import 'package:bitcoinsilver_wallet/config.dart';

class WalletService {
  Map<String, String> generateAddresses() {
    final randomSeed =
        List<int>.generate(32, (i) => Random.secure().nextInt(256));
    final root = bip32.BIP32.fromSeed(Uint8List.fromList(randomSeed));
    final child = root.derivePath("m/0/0");

    final privateKey = child.privateKey!;
    final pubKey = child.publicKey;
    final pubKeyHash = _pubKeyToP2WPKH(pubKey);

    final bech32Addr = _encodeBech32Address(Config.prefix, 0, pubKeyHash);
    final wifPrivateKey = _privateKeyToWif(privateKey);
    return {
      'address': bech32Addr,
      'privateKey': HEX.encode(privateKey),
      'wifPrivateKey': wifPrivateKey,
    };
  }

  String? recoverAddressFromWif(String wifPrivateKey) {
    try {
      final privateKey = _wifToPrivateKey(wifPrivateKey);
      final node = bip32.BIP32.fromPrivateKey(privateKey, Uint8List(32));
      final pubKey = node.publicKey;
      final pubKeyHash = _pubKeyToP2WPKH(pubKey);

      return _encodeBech32Address(Config.prefix, 0, pubKeyHash);
    } catch (e) {
      return null;
    }
  }

  String _privateKeyToWif(Uint8List privateKey) {
    final prefix =
        Uint8List.fromList([Config.prefixMainnet]); // Prefix for mainnet
    final compressedKey =
        Uint8List.fromList(prefix + privateKey.toList() + [0x01]);
    final checksum = _calculateChecksum(compressedKey);
    final keyWithChecksum = Uint8List.fromList(compressedKey + checksum);

    return _base58Encode(keyWithChecksum);
  }

  Uint8List _wifToPrivateKey(String wif) {
    final bytes = _base58Decode(wif);
    final keyWithChecksum = bytes.sublist(0, bytes.length - 4);
    final checksum = bytes.sublist(bytes.length - 4);

    if (!_listEquals(checksum, _calculateChecksum(keyWithChecksum))) {
      throw Exception('Invalid WIF checksum');
    }

    // Remove prefix (0x80) and optional compression byte (0x01)
    return Uint8List.fromList(keyWithChecksum.sublist(
        1, keyWithChecksum.length - (keyWithChecksum.length > 32 ? 1 : 0)));
  }

  Uint8List _calculateChecksum(Uint8List data) {
    final sha256_1 = sha256.convert(data).bytes;
    final sha256_2 = sha256.convert(Uint8List.fromList(sha256_1)).bytes;
    return Uint8List.fromList(sha256_2.sublist(0, 4));
  }

  String _base58Encode(Uint8List bytes) {
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    BigInt x = BigInt.parse(hex.encode(bytes), radix: 16);
    String result = '';

    while (x > BigInt.zero) {
      final mod = x % BigInt.from(58);
      x = x ~/ BigInt.from(58);
      result = alphabet[mod.toInt()] + result;
    }

    // Add leading '1's for each leading 0 byte in the original data
    result = '1' * bytes.where((byte) => byte == 0).length + result;
    return result;
  }

  Uint8List _base58Decode(String str) {
    const alphabet =
        '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    BigInt x = BigInt.zero;

    for (final char in str.runes) {
      final index = alphabet.indexOf(String.fromCharCode(char));
      if (index == -1) {
        throw ArgumentError('Invalid character in Base58 string');
      }
      x = x * BigInt.from(58) + BigInt.from(index);
    }

    final bytes = <int>[];
    while (x > BigInt.zero) {
      final mod = x % BigInt.from(256);
      bytes.insert(0, mod.toInt());
      x = x ~/ BigInt.from(256);
    }

    // Add leading zeros for each leading '1' in the Base58 string
    bytes.insertAll(
        0,
        List<int>.filled(
            str.runes.where((char) => String.fromCharCode(char) == '1').length,
            0));
    return Uint8List.fromList(bytes);
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
}
