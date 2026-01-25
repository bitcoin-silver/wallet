import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:bitcoinsilver_wallet/models/addressbook_entry.dart';

class AddressbookService {
  static const String _baseUrl = 'https://api.bitcoinsilver.top/addressbook';
  static const Duration _timeout = Duration(seconds: 15);

  /// Register a new username with an address
  /// Returns true if successful, throws exception otherwise
  static Future<bool> registerUsername({
    required String username,
    required String address,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/register'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'username': username,
          'address': address,
        }),
      ).timeout(
        _timeout,
        onTimeout: () {
          throw Exception('Request timeout - please check your connection');
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);

        // Check for success field
        if (data is Map<String, dynamic>) {
          if (data['success'] == true) {
            debugPrint('Registration successful: $data');
            return true;
          } else {
            // Success is false, throw the error message
            throw Exception(data['message'] ?? 'Registration failed');
          }
        }

        debugPrint('Registration successful: $data');
        return true;
      } else if (response.statusCode == 400) {
        try {
          final data = jsonDecode(response.body);
          throw Exception(data['message'] ?? data['error'] ?? 'Username already taken or invalid');
        } catch (e) {
          throw Exception('Username already taken or invalid');
        }
      } else {
        try {
          final data = jsonDecode(response.body);
          throw Exception(data['message'] ?? 'Registration failed with status: ${response.statusCode}');
        } catch (e) {
          throw Exception('Registration failed with status: ${response.statusCode}');
        }
      }
    } catch (e) {
      debugPrint('Error registering username: $e');
      rethrow;
    }
  }

  /// Look up an address by username
  /// Returns AddressbookEntry if found, null otherwise
  static Future<AddressbookEntry?> lookupByUsername(String username) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/username/${Uri.encodeComponent(username)}'),
        headers: {'Accept': 'application/json'},
      ).timeout(
        _timeout,
        onTimeout: () {
          throw Exception('Request timeout - please check your connection');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Check for success field in response
        if (data is Map<String, dynamic>) {
          if (data['success'] == false) {
            debugPrint('API error: ${data['message']}');
            return null;
          }

          // Success response with data
          if (data['success'] == true && data.containsKey('data') && data['data'] != null) {
            final entry = data['data'];
            // API returns 'u' for username and 'a' for address
            try {
              final username = (entry['u'] ?? entry['username'])?.toString() ?? '';
              final address = (entry['a'] ?? entry['address'])?.toString() ?? '';

              if (username.isEmpty || address.isEmpty) {
                debugPrint('⚠️ Invalid entry data: missing username or address');
                return null;
              }

              return AddressbookEntry(
                username: username,
                address: address,
              );
            } catch (e) {
              debugPrint('⚠️ Error parsing entry data: $e');
              return null;
            }
          } else if (data.containsKey('address')) {
            // Direct response format (fallback)
            try {
              final username = data['username']?.toString() ?? '';
              final address = data['address']?.toString() ?? '';

              if (username.isEmpty || address.isEmpty) {
                debugPrint('⚠️ Invalid direct response: missing username or address');
                return null;
              }

              return AddressbookEntry(
                username: username,
                address: address,
              );
            } catch (e) {
              debugPrint('⚠️ Error parsing direct response: $e');
              return null;
            }
          }
        }

        // Check if data is a list (fallback)
        if (data is List && data.isNotEmpty) {
          try {
            final entry = data.first;
            final username = (entry['u'] ?? entry['username'])?.toString() ?? '';
            final address = (entry['a'] ?? entry['address'])?.toString() ?? '';

            if (username.isEmpty || address.isEmpty) {
              debugPrint('⚠️ Invalid list entry: missing username or address');
              return null;
            }

            return AddressbookEntry(
              username: username,
              address: address,
            );
          } catch (e) {
            debugPrint('⚠️ Error parsing list entry: $e');
            return null;
          }
        }

        return null;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        try {
          final data = jsonDecode(response.body);
          final errorMsg = data['message'] ?? 'Lookup failed with status: ${response.statusCode}';
          throw Exception(errorMsg);
        } catch (e) {
          throw Exception('Lookup failed with status: ${response.statusCode}');
        }
      }
    } catch (e) {
      debugPrint('Error looking up username: $e');
      rethrow;
    }
  }

  /// Look up a username by address
  /// Returns AddressbookEntry if found, null otherwise
  static Future<AddressbookEntry?> lookupByAddress(String address) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/address/${Uri.encodeComponent(address)}'),
        headers: {'Accept': 'application/json'},
      ).timeout(
        _timeout,
        onTimeout: () {
          throw Exception('Request timeout - please check your connection');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Check for success field in response
        if (data is Map<String, dynamic>) {
          if (data['success'] == false) {
            debugPrint('API error: ${data['message']}');
            return null;
          }

          // Success response with data
          if (data['success'] == true && data.containsKey('data') && data['data'] != null) {
            final entry = data['data'];
            // API returns 'u' for username and 'a' for address
            try {
              final username = (entry['u'] ?? entry['username'])?.toString() ?? '';
              final address = (entry['a'] ?? entry['address'])?.toString() ?? '';

              if (username.isEmpty || address.isEmpty) {
                debugPrint('⚠️ Invalid entry data: missing username or address');
                return null;
              }

              return AddressbookEntry(
                username: username,
                address: address,
              );
            } catch (e) {
              debugPrint('⚠️ Error parsing entry data: $e');
              return null;
            }
          } else if (data.containsKey('username')) {
            // Direct response format (fallback)
            try {
              final username = data['username']?.toString() ?? '';
              final address = data['address']?.toString() ?? '';

              if (username.isEmpty || address.isEmpty) {
                debugPrint('⚠️ Invalid direct response: missing username or address');
                return null;
              }

              return AddressbookEntry(
                username: username,
                address: address,
              );
            } catch (e) {
              debugPrint('⚠️ Error parsing direct response: $e');
              return null;
            }
          }
        }

        // Check if data is a list (fallback)
        if (data is List && data.isNotEmpty) {
          try {
            final entry = data.first;
            final username = (entry['u'] ?? entry['username'])?.toString() ?? '';
            final address = (entry['a'] ?? entry['address'])?.toString() ?? '';

            if (username.isEmpty || address.isEmpty) {
              debugPrint('⚠️ Invalid list entry: missing username or address');
              return null;
            }

            return AddressbookEntry(
              username: username,
              address: address,
            );
          } catch (e) {
            debugPrint('⚠️ Error parsing list entry: $e');
            return null;
          }
        }

        return null;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        try {
          final data = jsonDecode(response.body);
          final errorMsg = data['message'] ?? 'Lookup failed with status: ${response.statusCode}';
          throw Exception(errorMsg);
        } catch (e) {
          throw Exception('Lookup failed with status: ${response.statusCode}');
        }
      }
    } catch (e) {
      debugPrint('Error looking up address: $e');
      rethrow;
    }
  }
}
