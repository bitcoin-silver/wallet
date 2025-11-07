import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bitcoinsilver_wallet/models/addressbook_entry.dart';
import 'package:bitcoinsilver_wallet/services/addressbook_service.dart';

class AddressbookProvider with ChangeNotifier {
  List<AddressbookEntry> _favorites = [];
  List<AddressbookEntry> _recentSearches = [];
  bool _isLoading = false;
  String? _errorMessage;
  AddressbookEntry? _lastSearchResult;

  static const String _favoritesKey = 'addressbook_favorites';
  static const String _recentSearchesKey = 'addressbook_recent_searches';
  static const int _maxRecentSearches = 10;

  List<AddressbookEntry> get favorites => _favorites;
  List<AddressbookEntry> get recentSearches => _recentSearches;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  AddressbookEntry? get lastSearchResult => _lastSearchResult;

  AddressbookProvider() {
    _loadFromStorage();
  }

  /// Load favorites and recent searches from local storage
  Future<void> _loadFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load favorites
      final favoritesJson = prefs.getString(_favoritesKey);
      if (favoritesJson != null) {
        final List<dynamic> decoded = jsonDecode(favoritesJson);
        _favorites = decoded.map((json) => AddressbookEntry.fromJson(json)).toList();
      }

      // Load recent searches
      final recentJson = prefs.getString(_recentSearchesKey);
      if (recentJson != null) {
        final List<dynamic> decoded = jsonDecode(recentJson);
        _recentSearches = decoded.map((json) => AddressbookEntry.fromJson(json)).toList();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading addressbook data: $e');
    }
  }

  /// Save favorites to local storage
  Future<void> _saveFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> jsonList = _favorites.map((e) => e.toJson()).toList();
      await prefs.setString(_favoritesKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving favorites: $e');
    }
  }

  /// Save recent searches to local storage
  Future<void> _saveRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> jsonList = _recentSearches.map((e) => e.toJson()).toList();
      await prefs.setString(_recentSearchesKey, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('Error saving recent searches: $e');
    }
  }

  /// Register a username with an address
  Future<bool> registerUsername({
    required String username,
    required String address,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final success = await AddressbookService.registerUsername(
        username: username,
        address: address,
      );

      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// Look up an entry by username
  Future<AddressbookEntry?> searchByUsername(String username) async {
    _isLoading = true;
    _errorMessage = null;
    _lastSearchResult = null;
    notifyListeners();

    try {
      final result = await AddressbookService.lookupByUsername(username);

      if (result != null) {
        _lastSearchResult = result;
        _addToRecentSearches(result);
      } else {
        _errorMessage = 'Username not found';
      }

      _isLoading = false;
      notifyListeners();
      return result;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return null;
    }
  }

  /// Look up an entry by address
  Future<AddressbookEntry?> searchByAddress(String address) async {
    _isLoading = true;
    _errorMessage = null;
    _lastSearchResult = null;
    notifyListeners();

    try {
      final result = await AddressbookService.lookupByAddress(address);

      if (result != null) {
        _lastSearchResult = result;
        _addToRecentSearches(result);
      } else {
        _errorMessage = 'Address not registered';
      }

      _isLoading = false;
      notifyListeners();
      return result;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return null;
    }
  }

  /// Add an entry to favorites
  Future<void> addToFavorites(AddressbookEntry entry) async {
    // Check if already in favorites
    if (_favorites.any((e) => e.username == entry.username || e.address == entry.address)) {
      return;
    }

    _favorites.insert(0, entry.copyWith(isFavorite: true));
    await _saveFavorites();
    notifyListeners();
  }

  /// Remove an entry from favorites
  Future<void> removeFromFavorites(AddressbookEntry entry) async {
    _favorites.removeWhere((e) => e.username == entry.username && e.address == entry.address);
    await _saveFavorites();
    notifyListeners();
  }

  /// Check if an entry is in favorites
  bool isFavorite(AddressbookEntry entry) {
    return _favorites.any((e) => e.username == entry.username || e.address == entry.address);
  }

  /// Add to recent searches (max 10)
  Future<void> _addToRecentSearches(AddressbookEntry entry) async {
    // Remove if already exists
    _recentSearches.removeWhere((e) => e.username == entry.username && e.address == entry.address);

    // Add to beginning
    _recentSearches.insert(0, entry);

    // Keep only last 10
    if (_recentSearches.length > _maxRecentSearches) {
      _recentSearches = _recentSearches.take(_maxRecentSearches).toList();
    }

    await _saveRecentSearches();
  }

  /// Clear recent searches
  Future<void> clearRecentSearches() async {
    _recentSearches.clear();
    await _saveRecentSearches();
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Clear last search result
  void clearLastSearchResult() {
    _lastSearchResult = null;
    notifyListeners();
  }

  /// Export favorites to a .btcs file
  Future<Map<String, dynamic>> exportToFile() async {
    try {
      if (_favorites.isEmpty) {
        return {
          'success': false,
          'message': 'No contacts to export',
        };
      }

      // Create export data structure
      final exportData = {
        'version': '1.0',
        'exportDate': DateTime.now().toIso8601String(),
        'contactCount': _favorites.length,
        'contacts': _favorites.map((e) => e.toJson()).toList(),
      };

      // Convert to JSON string
      final jsonString = jsonEncode(exportData);

      return {
        'success': true,
        'message': 'Ready to export ${_favorites.length} contacts',
        'count': _favorites.length,
        'data': jsonString,
      };
    } catch (e) {
      debugPrint('Error exporting addressbook: $e');
      return {
        'success': false,
        'message': 'Export failed: ${e.toString()}',
      };
    }
  }

  /// Import favorites from a .btcs file
  Future<Map<String, dynamic>> importFromFile(String filePath) async {
    try {
      // Validate file extension
      if (!filePath.toLowerCase().endsWith('.btcs')) {
        return {
          'success': false,
          'message': 'Invalid file type. Please select a .btcs file',
        };
      }

      final file = File(filePath);

      // Check file exists
      if (!await file.exists()) {
        return {
          'success': false,
          'message': 'File not found',
        };
      }

      // Check file size (max 1 MB)
      final fileSize = await file.length();
      if (fileSize > 1024 * 1024) {
        return {
          'success': false,
          'message': 'File too large (max 1 MB)',
        };
      }

      // Read and parse file
      final jsonString = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(jsonString);

      // Validate required fields
      if (!data.containsKey('version') || !data.containsKey('contacts')) {
        return {
          'success': false,
          'message': 'Invalid file format',
        };
      }

      // Parse contacts
      final List<dynamic> contactsJson = data['contacts'];
      final List<AddressbookEntry> newContacts = [];
      int duplicates = 0;

      for (var contactJson in contactsJson) {
        try {
          // Validate contact data
          if (!contactJson.containsKey('username') || !contactJson.containsKey('address')) {
            continue; // Skip invalid entries
          }

          final username = contactJson['username'] as String;
          final address = contactJson['address'] as String;

          // Validate username length (min 4 characters)
          if (username.length < 4) {
            continue;
          }

          // Check for duplicates
          final isDuplicate = _favorites.any(
            (e) => e.username == username || e.address == address,
          );

          if (isDuplicate) {
            duplicates++;
            continue;
          }

          // Create entry and add to new contacts
          final entry = AddressbookEntry.fromJson(contactJson).copyWith(isFavorite: true);
          newContacts.add(entry);
        } catch (e) {
          debugPrint('Error parsing contact: $e');
          // Skip invalid entries
          continue;
        }
      }

      // Add new contacts to favorites
      _favorites.addAll(newContacts);
      await _saveFavorites();
      notifyListeners();

      final message = duplicates > 0
          ? 'Imported ${newContacts.length} contacts, $duplicates duplicates skipped'
          : 'Imported ${newContacts.length} contacts';

      return {
        'success': true,
        'message': message,
        'imported': newContacts.length,
        'duplicates': duplicates,
      };
    } catch (e) {
      debugPrint('Error importing addressbook: $e');
      return {
        'success': false,
        'message': 'Import failed: ${e.toString()}',
      };
    }
  }
}
