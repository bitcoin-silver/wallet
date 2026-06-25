import 'dart:typed_data';
import 'package:base_x/base_x.dart';
import 'package:bech32/bech32.dart';
import 'package:bip32/bip32.dart' as bip32;
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import 'package:bitcoinsilver_wallet/config.dart';

class BTCSTxInput {
  final String txid;
  final int vout;
  final Uint8List scriptPubKey;
  final int satoshis;
  Uint8List? scriptSig;
  List<Uint8List>? witness;
  int sequence;
  late final Uint8List txidLittleEndian =
      Uint8List.fromList(HEX.decode(txid).reversed.toList());

  BTCSTxInput({
    required this.txid,
    required this.vout,
    required this.scriptPubKey,
    required this.satoshis,
    this.scriptSig,
    this.witness,
    this.sequence = 0xffffffff,
  });
}

class BTCSTxOutput {
  final Uint8List scriptPubKey;
  final int satoshis;

  BTCSTxOutput({
    required this.scriptPubKey,
    required this.satoshis,
  });
}

class BTCSSigner {
  static const int sighashAll = 1;
  static const int p2pkhPrefix = 0x1A;
  static const int p2shPrefix = 0x05;

  static final BaseXCodec _base58 =
      BaseXCodec('123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz');

  static String signTransaction({
    required List<BTCSTxInput> inputs,
    required List<BTCSTxOutput> outputs,
    required String wif,
  }) {
    final Uint8List privKeyBytes = _decodeWifToBytes(wif);
    final node = bip32.BIP32.fromPrivateKey(privKeyBytes, Uint8List(32));
    final Uint8List pubKey = node.publicKey;

    final Uint8List hashPrevouts = _getHashPrevouts(inputs);
    final Uint8List hashSequence = _getHashSequence(inputs);
    final Uint8List hashOutputs = _getHashOutputs(outputs);

    for (int i = 0; i < inputs.length; i++) {
      final Uint8List preimage = _buildSegWitPreimage(
        inputs: inputs,
        outputs: outputs,
        index: i,
        hashPrevouts: hashPrevouts,
        hashSequence: hashSequence,
        hashOutputs: hashOutputs,
        hashType: sighashAll,
      );

      final Uint8List txHash = _doubleSha256(preimage);
      final Uint8List rawSig = node.sign(txHash);
      final Uint8List derSig = _encodeDer(rawSig);

      final Uint8List sigWithHashType = Uint8List(derSig.length + 1);
      sigWithHashType.setRange(0, derSig.length, derSig);
      sigWithHashType[derSig.length] = sighashAll;

      inputs[i].scriptSig = Uint8List(0);
      inputs[i].witness = [sigWithHashType, pubKey];
    }

    return HEX.encode(_serializeSegWitTransaction(inputs, outputs));
  }

  static Uint8List scriptFromAddress(String address) {
    // 1. Handle Native SegWit (Bech32 - 'bs')
    if (address.toLowerCase().startsWith('bs')) {
      try {
        const bech32Codec = Bech32Codec();
        final decoded = bech32Codec.decode(address, 1000);

        final int witnessVersion = decoded.data[0];
        final Uint8List witnessProgram5Bit =
            Uint8List.fromList(decoded.data.sublist(1));
        final Uint8List witnessProgram =
            _convertBits(witnessProgram5Bit, 5, 8, false);

        final builder = _BytesBuilder();
        builder.writeByte(witnessVersion == 0 ? 0x00 : 0x50 + witnessVersion);
        builder.writeByte(witnessProgram.length);
        builder.writeBytes(witnessProgram);
        return builder.toBytes();
      } catch (e) {
        throw Exception('Malformed native SegWit target: $e');
      }
    }

    // 2. Handle Legacy Base58 ('B', 'b', '8', '3' prefixes)
    try {
      final Uint8List decodedWithChecksum =
          Uint8List.fromList(_base58.decode(address));
      final Uint8List payload =
          decodedWithChecksum.sublist(0, decodedWithChecksum.length - 4);

      final int versionByte = payload[0];
      final Uint8List hashPayload = payload.sublist(1);

      final builder = _BytesBuilder();

      // Map based on BTCS prefixes
      if (versionByte == p2pkhPrefix) {
        // P2PKH: OP_DUP OP_HASH160 <20-byte-hash> OP_EQUALVERIFY OP_CHECKSIG
        builder.writeByte(0x76);
        builder.writeByte(0xa9);
        builder.writeByte(hashPayload.length);
        builder.writeBytes(hashPayload);
        builder.writeByte(0x88);
        builder.writeByte(0xac);
      } else if (versionByte == p2shPrefix) {
        // P2SH: OP_HASH160 <20-byte-hash> OP_EQUAL
        builder.writeByte(0xa9);
        builder.writeByte(hashPayload.length);
        builder.writeBytes(hashPayload);
        builder.writeByte(0x87);
      } else {
        throw Exception('Unsupported address prefix byte: $versionByte');
      }
      return builder.toBytes();
    } catch (e) {
      throw Exception('Target address format unsupported: $address');
    }
  }

  static Uint8List _buildSegWitPreimage({
    required List<BTCSTxInput> inputs,
    required List<BTCSTxOutput> outputs,
    required int index,
    required Uint8List hashPrevouts,
    required Uint8List hashSequence,
    required Uint8List hashOutputs,
    required int hashType,
  }) {
    final builder = _BytesBuilder();
    final input = inputs[index];

    builder.writeUint32(1);
    builder.writeBytes(hashPrevouts);
    builder.writeBytes(hashSequence);

    builder.writeBytes(input.txidLittleEndian);
    builder.writeUint32(input.vout);

    final Uint8List pubKeyHash = input.scriptPubKey.sublist(2);
    final scriptCodeBuilder = _BytesBuilder();
    scriptCodeBuilder.writeByte(0x76);
    scriptCodeBuilder.writeByte(0xa9);
    scriptCodeBuilder.writeByte(pubKeyHash.length);
    scriptCodeBuilder.writeBytes(pubKeyHash);
    scriptCodeBuilder.writeByte(0x88);
    scriptCodeBuilder.writeByte(0xac);
    final Uint8List scriptCode = scriptCodeBuilder.toBytes();

    builder.writeVarInt(scriptCode.length);
    builder.writeBytes(scriptCode);
    builder.writeUint64(input.satoshis);
    builder.writeUint32(input.sequence);
    builder.writeBytes(hashOutputs);
    builder.writeUint32(0);
    builder.writeUint32(hashType);

    return builder.toBytes();
  }

  static Uint8List _serializeSegWitTransaction(
      List<BTCSTxInput> inputs, List<BTCSTxOutput> outputs) {
    final builder = _BytesBuilder();

    builder.writeUint32(1);
    builder.writeByte(0x00);
    builder.writeByte(0x01);

    builder.writeVarInt(inputs.length);
    for (final input in inputs) {
      builder.writeBytes(input.txidLittleEndian);
      builder.writeUint32(input.vout);
      builder.writeVarInt(0);
      builder.writeUint32(input.sequence);
    }

    builder.writeVarInt(outputs.length);
    for (final output in outputs) {
      builder.writeUint64(output.satoshis);
      builder.writeVarInt(output.scriptPubKey.length);
      builder.writeBytes(output.scriptPubKey);
    }

    for (final input in inputs) {
      final witnessList = input.witness ?? [];
      builder.writeVarInt(witnessList.length);
      for (final item in witnessList) {
        builder.writeVarInt(item.length);
        builder.writeBytes(item);
      }
    }

    builder.writeUint32(0);
    return builder.toBytes();
  }

  static Uint8List _decodeWifToBytes(String wif) {
    final Uint8List bytes = Uint8List.fromList(_base58.decode(wif));
    final keyWithChecksum = bytes.sublist(0, bytes.length - 4);

    if (keyWithChecksum[0] != Config.networkPrefix) {
      throw Exception('Incompatible WIF prefix found');
    }

    return keyWithChecksum.sublist(1, 33);
  }

  static Uint8List _encodeDer(Uint8List raw64ByteSig) {
    final r = raw64ByteSig.sublist(0, 32);
    final s = raw64ByteSig.sublist(32, 64);

    final rBytes = _minimalEncoding(r);
    final sBytes = _minimalEncoding(s);

    final builder = _BytesBuilder();
    builder.writeByte(0x30);
    builder.writeByte(rBytes.length + sBytes.length + 4);
    builder.writeByte(0x02);
    builder.writeByte(rBytes.length);
    builder.writeBytes(rBytes);
    builder.writeByte(0x02);
    builder.writeByte(sBytes.length);
    builder.writeBytes(sBytes);
    return builder.toBytes();
  }

  static Uint8List _minimalEncoding(Uint8List bytes) {
    int start = 0;
    while (start < bytes.length - 1 && bytes[start] == 0) {
      start++;
    }

    if ((bytes[start] & 0x80) != 0) {
      final padded = Uint8List(bytes.length - start + 1);
      padded[0] = 0x00;
      padded.setRange(1, padded.length, bytes.sublist(start));
      return padded;
    }

    return bytes.sublist(start);
  }

  static Uint8List _getHashPrevouts(List<BTCSTxInput> inputs) {
    final builder = _BytesBuilder();
    for (final input in inputs) {
      builder.writeBytes(input.txidLittleEndian);
      builder.writeUint32(input.vout);
    }
    return _doubleSha256(builder.toBytes());
  }

  static Uint8List _getHashSequence(List<BTCSTxInput> inputs) {
    final builder = _BytesBuilder();
    for (final input in inputs) {
      builder.writeUint32(input.sequence);
    }
    return _doubleSha256(builder.toBytes());
  }

  static Uint8List _getHashOutputs(List<BTCSTxOutput> outputs) {
    final builder = _BytesBuilder();
    for (final output in outputs) {
      builder.writeUint64(output.satoshis);
      builder.writeVarInt(output.scriptPubKey.length);
      builder.writeBytes(output.scriptPubKey);
    }
    return _doubleSha256(builder.toBytes());
  }

  static Uint8List _doubleSha256(Uint8List data) {
    final pass1 = sha256.convert(data).bytes;
    return Uint8List.fromList(sha256.convert(pass1).bytes);
  }

  static Uint8List _convertBits(
      Uint8List data, int fromBits, int toBits, bool pad) {
    int acc = 0;
    int bits = 0;
    final List<int> result = [];
    final int maxv = (1 << toBits) - 1;

    for (final int value in data) {
      if ((value >> fromBits) != 0) {
        throw Exception('Invalid bit range');
      }

      acc = (acc << fromBits) | value;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }

    if (pad) {
      if (bits > 0) {
        result.add((acc << (toBits - bits)) & maxv);
      }
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
      throw Exception('Invalid padding structural verification');
    }

    return Uint8List.fromList(result);
  }
}

class _BytesBuilder {
  final List<int> _bytes = [];

  void writeByte(int value) => _bytes.add(value & 0xFF);
  void writeBytes(Uint8List bytes) => _bytes.addAll(bytes);

  void writeUint16(int value) {
    _bytes.add(value & 0xFF);
    _bytes.add((value >> 8) & 0xFF);
  }

  void writeUint32(int value) {
    _bytes.add(value & 0xFF);
    _bytes.add((value >> 8) & 0xFF);
    _bytes.add((value >> 16) & 0xFF);
    _bytes.add((value >> 24) & 0xFF);
  }

  void writeUint64(int value) {
    _bytes.add(value & 0xFF);
    _bytes.add((value >> 8) & 0xFF);
    _bytes.add((value >> 16) & 0xFF);
    _bytes.add((value >> 24) & 0xFF);
    _bytes.add((value >> 32) & 0xFF);
    _bytes.add((value >> 40) & 0xFF);
    _bytes.add((value >> 48) & 0xFF);
    _bytes.add((value >> 56) & 0xFF);
  }

  void writeVarInt(int value) {
    if (value < 0xfd) {
      writeByte(value);
    } else if (value <= 0xffff) {
      writeByte(0xfd);
      writeUint16(value);
    } else if (value <= 0xffffffff) {
      writeByte(0xfe);
      writeUint32(value);
    } else {
      writeByte(0xff);
      writeUint64(value);
    }
  }

  Uint8List toBytes() => Uint8List.fromList(_bytes);
}
