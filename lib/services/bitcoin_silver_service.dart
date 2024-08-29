// bitcoin_silver_service.dart

import 'dart:math';
import 'dart:typed_data';
import 'package:bech32/bech32.dart';
import 'package:bip32/bip32.dart' as bip32;
import 'package:hex/hex.dart';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/digests/ripemd160.dart';

class BitcoinSilverService {
  // Generiere zwei Bech32-Adressen und gebe den privaten Schlüssel zurück
  Map<String, String> generateAddresses() {
    final randomSeed =
        List<int>.generate(32, (i) => Random.secure().nextInt(256));
    final root = bip32.BIP32.fromSeed(Uint8List.fromList(randomSeed));

    final child1 = root.derivePath("m/0/0");
    final child2 = root.derivePath("m/0/1");
    final privateKey = child1.privateKey!;

    final pubKey1 = child1.publicKey;
    final pubKey2 = child2.publicKey;

    final pubKeyHash1 = _pubKeyToP2WPKH(pubKey1);
    final pubKeyHash2 = _pubKeyToP2WPKH(pubKey2);

    final witnessVersion = 0;
    final bech32Addr1 = _encodeBech32Address('bs', witnessVersion, pubKeyHash1);
    final bech32Addr2 = _encodeBech32Address('bs', witnessVersion, pubKeyHash2);

    return {
      'address1': bech32Addr1,
      'address2': bech32Addr2,
      'privateKey': HEX.encode(privateKey),
    };
  }

  // Stelle eine Bech32-Adresse aus einem privaten Schlüssel wieder her
  String? recoverAddress(String privateKeyHex) {
    try {
      final privateKey = Uint8List.fromList(HEX.decode(privateKeyHex));

      final node = bip32.BIP32.fromPrivateKey(privateKey, Uint8List(32));
      final pubKey = node.publicKey;
      final pubKeyHash = _pubKeyToP2WPKH(pubKey);

      final witnessVersion = 0;
      return _encodeBech32Address('bs', witnessVersion, pubKeyHash);
    } catch (e) {
      return null;
    }
  }

  // Hilfsfunktionen
  Uint8List _pubKeyToP2WPKH(List<int> pubKey) {
    var sha256Hash = sha256.convert(pubKey).bytes;

    var ripemd160Digest = RIPEMD160Digest();
    var ripemd160Hash = ripemd160Digest.process(Uint8List.fromList(sha256Hash));

    return Uint8List.fromList(ripemd160Hash);
  }

  String _encodeBech32Address(String hrp, int version, Uint8List program) {
    List<int> converted = _convertBits(program, 8, 5, true);

    List<int> data = [version] + converted;

    final bech32 = Bech32(hrp, data);

    return Bech32Codec().encode(bech32);
  }

  List<int> _convertBits(List<int> data, int from, int to, bool pad) {
    int acc = 0;
    int bits = 0;
    List<int> ret = [];
    int maxv = (1 << to) - 1;
    for (final value in data) {
      if (value < 0 || (value >> from) != 0) {
        throw Exception('Invalid value');
      }
      acc = (acc << from) | value;
      bits += from;
      while (bits >= to) {
        bits -= to;
        ret.add((acc >> bits) & maxv);
      }
    }
    if (pad) {
      if (bits > 0) {
        ret.add((acc << (to - bits)) & maxv);
      }
    } else if (bits >= from || ((acc << (to - bits)) & maxv) != 0) {
      throw Exception('Invalid padding');
    }
    return ret;
  }
}
