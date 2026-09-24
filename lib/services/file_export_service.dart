import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// Saves bytes to a file the user picks.
///
/// On Android this does NOT use FilePicker.saveFile: that plugin writes with
/// openOutputStream(uri) (mode "w"), which on many Android 10+ providers does
/// not truncate. Saving over an older, longer file then leaves the old tail
/// after the new content (see the comment in MainActivity.kt). The native
/// channel below writes with mode "wt" and verifies the final size.
class FileExportService {
  static const MethodChannel _channel = MethodChannel('top.bitcoinsilver.wallet/file_export');

  /// Returns the saved location, or null if the user cancelled.
  /// Throws a [PlatformException] (Android) or plugin error when writing fails.
  static Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
    String? dialogTitle,
  }) async {
    if (Platform.isAndroid) {
      return _channel.invokeMethod<String>('saveFile', <String, Object>{
        'fileName': fileName,
        'bytes': bytes,
      });
    }

    final result = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      bytes: bytes,
    );
    return result?.toString();
  }
}
