import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bitcoinsilver_wallet/models/addressbook_entry.dart';

class AddressbookProvider with ChangeNotifier {
  static const String _storageKey = 'addressbook_entries_v1';
  static const int maxImportEntries = 5000;
  static const int maxLabelLength = 64;
  static const int maxAddressLength = 128;
  static final RegExp _legacyAddressRegex = RegExp(
    r'^[bB83][1-9A-HJ-NP-Za-km-z]{24,33}$',
  );
  static final RegExp _bech32AddressRegex = RegExp(r'^bs1[a-z0-9]{39,59}$');

  final List<AddressbookEntry> _entries = [];
  bool _isLoading = false;
  Future<void>? _inFlightLoad;

  List<AddressbookEntry> get entries => List.unmodifiable(_entries);
  bool get isLoading => _isLoading;

  AddressbookProvider() {
    loadEntries();
  }

  Future<void> reloadEntries() => loadEntries();

  Future<void> loadEntries() async {
    if (_inFlightLoad != null) {
      return _inFlightLoad!;
    }

    final loadFuture = _loadEntriesInternal();
    _inFlightLoad = loadFuture;
    try {
      await loadFuture;
    } finally {
      if (identical(_inFlightLoad, loadFuture)) {
        _inFlightLoad = null;
      }
    }
  }

  Future<void> _loadEntriesInternal() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_storageKey);
      if (data == null || data.isEmpty) {
        _entries.clear();
        return;
      }

      final decoded = jsonDecode(data);
      if (decoded is! List) {
        _entries.clear();
        return;
      }

      _entries
        ..clear()
        ..addAll(
          decoded
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .map(AddressbookEntry.fromJson)
              .where((e) => e.label.isNotEmpty && e.address.isNotEmpty),
        );
    } catch (_) {
      _entries.clear();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _persistEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, payload);
  }

  String _normalizeAddressForMatch(String address) {
    final trimmed = address.trim();
    final lower = trimmed.toLowerCase();
    return lower.startsWith('bs1') ? lower : trimmed;
  }

  bool _isValidAddressFormat(String address) {
    final trimmed = address.trim();
    final lower = trimmed.toLowerCase();
    return _legacyAddressRegex.hasMatch(trimmed) ||
        _bech32AddressRegex.hasMatch(lower);
  }

  bool _isValidLabelFormat(String label) {
    final trimmed = label.trim();
    return trimmed.isNotEmpty && trimmed.length <= maxLabelLength;
  }

  bool _isValidAddressLength(String address) {
    final trimmed = address.trim();
    return trimmed.isNotEmpty && trimmed.length <= maxAddressLength;
  }

  Future<String?> addOrUpdateEntry({
    required String label,
    required String address,
    String? originalAddress,
  }) async {
    final cleanLabel = label.trim();
    final cleanAddress = address.trim();

    if (cleanLabel.isEmpty || cleanAddress.isEmpty) {
      return 'Label and address are required.';
    }

    if (!_isValidLabelFormat(cleanLabel)) {
      return 'Label is too long (max $maxLabelLength characters).';
    }

    if (!_isValidAddressLength(cleanAddress)) {
      return 'Address is too long (max $maxAddressLength characters).';
    }

    if (!_isValidAddressFormat(cleanAddress)) {
      return 'Address format is invalid.';
    }

    final normalizedCleanAddress = _normalizeAddressForMatch(cleanAddress);

    final existingByAddress = _entries.indexWhere(
      (e) =>
          _normalizeAddressForMatch(e.address) == normalizedCleanAddress,
    );

    if (existingByAddress != -1 &&
        (originalAddress == null ||
            _normalizeAddressForMatch(_entries[existingByAddress].address) !=
                _normalizeAddressForMatch(originalAddress))) {
      return 'This address is already saved.';
    }

    if (originalAddress != null && originalAddress.trim().isNotEmpty) {
      final existingIndex = _entries.indexWhere(
        (e) =>
            _normalizeAddressForMatch(e.address) ==
            _normalizeAddressForMatch(originalAddress),
      );
      if (existingIndex != -1) {
        _entries[existingIndex] = _entries[existingIndex].copyWith(
          label: cleanLabel,
          address: cleanAddress,
        );
      } else {
        _entries.insert(
          0,
          AddressbookEntry(
            label: cleanLabel,
            address: cleanAddress,
            createdAt: DateTime.now(),
          ),
        );
      }
    } else {
      _entries.insert(
        0,
        AddressbookEntry(
          label: cleanLabel,
          address: cleanAddress,
          createdAt: DateTime.now(),
        ),
      );
    }

    await _persistEntries();
    notifyListeners();
    return null;
  }

  Future<void> removeEntry(String address) async {
    final normalizedAddress = _normalizeAddressForMatch(address);
    _entries.removeWhere(
      (e) => _normalizeAddressForMatch(e.address) == normalizedAddress,
    );
    await _persistEntries();
    notifyListeners();
  }

  Future<void> clearEntries() async {
    _entries.clear();
    await _persistEntries();
    notifyListeners();
  }

  String exportToBtcsJson() {
    final contacts = _entries
        .map(
          (e) => <String, dynamic>{
            'username': e.label,
            'address': e.address,
            'isFavorite': true,
            'addedAt': e.createdAt.toIso8601String(),
          },
        )
        .toList();

    return jsonEncode(<String, dynamic>{
      'version': '1.0',
      'exportDate': DateTime.now().toIso8601String(),
      'contactCount': contacts.length,
      'contacts': contacts,
    });
  }

  Future<Map<String, dynamic>> importFromBtcsJson(String jsonString) async {
    try {
      final sanitized = jsonString
          .replaceAll('\u0000', '')
          .replaceFirst(RegExp(r'^\uFEFF'), '')
          .trim();

      final decoded = jsonDecode(sanitized);

      if (decoded is! Map) {
        return {
          'success': false,
          'message': 'Invalid .btcs format.',
        };
      }

      final decodedMap = Map<String, dynamic>.from(decoded);
      if (!decodedMap.containsKey('version') || !decodedMap.containsKey('contacts')) {
        return {
          'success': false,
          'message': 'Invalid .btcs format. Missing required fields.',
        };
      }

      final declaredCount = decodedMap['contactCount'] is num
          ? (decodedMap['contactCount'] as num).toInt()
          : null;
      final rawEntries = decodedMap['contacts'];

      if (rawEntries is! List) {
        return {
          'success': false,
          'message': 'Invalid .btcs format. Contacts must be a list.',
        };
      }

      if (rawEntries.length > maxImportEntries) {
        return {
          'success': false,
          'message': 'File contains too many entries (max $maxImportEntries).',
        };
      }

      if (declaredCount != null && rawEntries.length < declaredCount) {
        return {
          'success': false,
          'message':
              'Selected file appears incomplete ($rawEntries.length of $declaredCount contacts). '
              'Please reselect the original .btcs file (not a temporary .bin cache copy).',
        };
      }

      var imported = 0;
      var skipped = 0;

      for (final item in rawEntries) {
        if (item is! Map) {
          skipped++;
          continue;
        }

        final entry = AddressbookEntry.fromJson(Map<String, dynamic>.from(item));
        if (!_isValidLabelFormat(entry.label) ||
            !_isValidAddressLength(entry.address) ||
            !_isValidAddressFormat(entry.address)) {
          skipped++;
          continue;
        }

        final normalizedEntryAddress = _normalizeAddressForMatch(entry.address);
        final existingIndex = _entries.indexWhere(
          (e) =>
              _normalizeAddressForMatch(e.address) == normalizedEntryAddress,
        );

        if (existingIndex != -1) {
          _entries[existingIndex] = _entries[existingIndex].copyWith(
            label: entry.label,
          );
        } else {
          _entries.add(
            AddressbookEntry(
              label: entry.label,
              address: entry.address,
              createdAt: entry.createdAt,
            ),
          );
        }
        imported++;
      }

      await _persistEntries();
      notifyListeners();

      if (imported == 0) {
        return {
          'success': false,
          'imported': imported,
          'skipped': skipped,
          'message': 'No valid contacts found in this .btcs file.',
        };
      }

      return {
        'success': true,
        'imported': imported,
        'skipped': skipped,
        'message': 'Imported $imported contacts. Skipped $skipped invalid contacts.',
      };
    } catch (e) {
      if (e is FormatException) {
        final lower = e.message.toLowerCase();
        if (lower.contains('unexpected end of input')) {
          return {
            'success': false,
            'message':
                'Selected .btcs file appears incomplete or truncated. Please reselect the original file.',
          };
        }

        return {
          'success': false,
          'message': 'Selected .btcs file is not valid JSON content (${e.message}).',
        };
      }

      return {
        'success': false,
        'message': 'Could not import .btcs file.',
      };
    }
  }

  Future<Map<String, dynamic>> importFromJsonString(String jsonString) {
    return importFromBtcsJson(jsonString);
  }

}
