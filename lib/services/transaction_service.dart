import 'dart:convert';
import 'dart:typed_data';
import 'package:bech32/bech32.dart';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import 'package:pointycastle/api.dart' show PrivateKeyParameter, Signer;
import 'package:pointycastle/digests/ripemd160.dart';
import 'package:pointycastle/ecc/api.dart' as ecc;
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/pointycastle.dart' as pc;
import 'wallet_service.dart';

class TransactionService {
  final WalletService _walletService = WalletService();

  // Node-API-URLs
  final String utxoApiUrl = 'https://dein-bitcoin-silver-node/api/getutxos';
  final String broadcastApiUrl =
      'https://dein-bitcoin-silver-node/api/sendrawtransaction';

  // Transaktion erstellen und senden
  Future<String> createAndSendTransaction({
    required String privateKeyHex,
    required String toAddress,
    required int amount,
    required int fee,
  }) async {
    final senderAddress = _walletService.recoverAddress(privateKeyHex);
    if (senderAddress == null) throw Exception('Ungültiger privater Schlüssel');

    final utxos = await _fetchUtxos(senderAddress);
    final txHex = _createTransaction(
      privateKey: Uint8List.fromList(HEX.decode(privateKeyHex)),
      toAddress: toAddress,
      amount: amount,
      utxos: utxos,
      fee: fee,
      senderAddress: senderAddress,
    );

    return _broadcastTransaction(txHex);
  }

  // UTXOs von der Node abrufen
  Future<List<Map<String, dynamic>>> _fetchUtxos(String address) async {
    final response = await http.post(
      Uri.parse(utxoApiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'address': address}),
    );

    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    } else {
      throw Exception('Fehler beim Abrufen der UTXOs: ${response.body}');
    }
  }

  // Transaktion erstellen und signieren
  String _createTransaction({
    required Uint8List privateKey,
    required String toAddress,
    required int amount,
    required List<Map<String, dynamic>> utxos,
    required int fee,
    required String senderAddress,
  }) {
    final publicKey = _getPublicKey(privateKey);
    final totalInputValue =
        utxos.fold<int>(0, (sum, utxo) => sum + (utxo['value'] as int));

    final txBuffer = BytesBuilder();
    txBuffer.add(_intToBytes(1, 4)); // Version
    txBuffer.add(_varInt(utxos.length)); // Eingänge
    for (var utxo in utxos) {
      txBuffer.add(HEX.decode(utxo['txid']).reversed.toList());
      txBuffer.add(_intToBytes(utxo['vout'] as int, 4));
      txBuffer.add(_varInt(0)); // Leer ScriptSig
      txBuffer.add(_intToBytes(0xFFFFFFFF, 4)); // Sequence
    }

    txBuffer.add(_varInt(2)); // Ausgänge
    txBuffer.add(_intToBytes(amount, 8)); // Empfänger
    txBuffer.add(_scriptPubKey(toAddress));
    txBuffer.add(_intToBytes(totalInputValue - amount - fee, 8)); // Rückgeld
    txBuffer.add(_scriptPubKey(senderAddress));

    txBuffer.add(_intToBytes(0, 4)); // Locktime

    // Signiere jede Eingabe
    for (int i = 0; i < utxos.length; i++) {
      final sigHash = _calculateSigHash(txBuffer.toBytes(), i, publicKey);
      final signature = _sign(sigHash, privateKey);
      final sigScript = BytesBuilder()
        ..add(_varInt(signature.length + 1))
        ..add(signature)
        ..addByte(1) // SIGHASH_ALL
        ..add(_varInt(publicKey.length))
        ..add(publicKey);

      txBuffer.add(sigScript.toBytes());
    }

    return HEX.encode(txBuffer.toBytes());
  }

  // Signatur-Hash berechnen
  Uint8List _calculateSigHash(
      Uint8List tx, int inputIndex, Uint8List publicKey) {
    final txCopy = Uint8List.fromList(tx);
    txCopy.setAll(inputIndex, _scriptPubKeyFromPublicKey(publicKey));
    return sha256.convert(sha256.convert(txCopy).bytes).bytes as Uint8List;
  }

  // Transaktion an die Node senden
  Future<String> _broadcastTransaction(String txHex) async {
    final response = await http.post(
      Uri.parse(broadcastApiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'hex': txHex}),
    );

    if (response.statusCode == 200) {
      final responseData = jsonDecode(response.body);
      return responseData['txid'] ?? 'Transaktion erfolgreich gesendet';
    } else {
      throw Exception('Fehler beim Senden der Transaktion: ${response.body}');
    }
  }

  // Hilfsfunktionen

  Uint8List _getPublicKey(Uint8List privateKey) {
    final ecCurve = ECCurve_secp256k1();
    final ecPrivateKey = ecc.ECPrivateKey(
        BigInt.parse(HEX.encode(privateKey), radix: 16), ecCurve);
    final ecPoint = ecCurve.G * ecPrivateKey.d;

    if (ecPoint != null) {
      return ecPoint.getEncoded(true);
    } else {
      throw Exception('Fehler beim Generieren des Public Keys.');
    }
  }

  Uint8List _intToBytes(int value, int length) {
    final result = Uint8List(length);
    for (int i = 0; i < length; i++) {
      result[length - i - 1] = value & 0xff;
      value >>= 8;
    }
    return result;
  }

  Uint8List _varInt(int value) {
    if (value < 0xfd) {
      return Uint8List.fromList([value]);
    } else if (value <= 0xffff) {
      return Uint8List.fromList([0xfd, value & 0xff, (value >> 8) & 0xff]);
    } else if (value <= 0xffffffff) {
      return Uint8List.fromList([
        0xfe,
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff
      ]);
    } else {
      throw Exception('VarInt zu groß');
    }
  }

  Uint8List _scriptPubKey(String address) {
    final decoded = const Bech32Codec().decode(address);
    return Uint8List.fromList([0x00, decoded.data.length, ...decoded.data]);
  }

  Uint8List _scriptPubKeyFromPublicKey(Uint8List publicKey) {
    final sha256Hash = sha256.convert(publicKey).bytes;
    final ripemd160Digest = RIPEMD160Digest();
    final ripemd160Hash =
        ripemd160Digest.process(Uint8List.fromList(sha256Hash));
    return Uint8List.fromList([0x00, ripemd160Hash.length, ...ripemd160Hash]);
  }

  Uint8List _sign(Uint8List data, Uint8List privateKey) {
    final ecCurve = ECCurve_secp256k1();
    final ecPrivateKey = ecc.ECPrivateKey(
        BigInt.parse(HEX.encode(privateKey), radix: 16), ecCurve);

    final signer = Signer('SHA-256/ECDSA');
    signer.init(true, PrivateKeyParameter<ecc.ECPrivateKey>(ecPrivateKey));
    final signature = signer.generateSignature(data) as pc.ECSignature;

    // Extrahiere die Signatur-Daten (r und s)
    final r = signature.r.toUnsigned(32).toByteArray();
    final s = signature.s.toUnsigned(32).toByteArray();

    // Signatur in der Form von r und s erstellen
    final sigScript = BytesBuilder()
      ..add([0x30, (r.length + s.length + 4)]) // SEQUENCE
      ..add([0x02, r.length]) // r
      ..add(r)
      ..add([0x02, s.length]) // s
      ..add(s);

    return sigScript.toBytes();
  }
}

extension on BigInt {
  Uint8List toByteArray() {
    final byteArray = toByteArray();
    final padding = (byteArray[0] & 0x80) != 0 ? 1 : 0;
    final result = Uint8List(byteArray.length + padding);
    if (padding == 1) {
      result[0] = 0x00;
    }
    result.setRange(padding, result.length, byteArray);
    return result;
  }
}
