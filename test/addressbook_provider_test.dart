import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bitcoinsilver_wallet/providers/addressbook_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AddressbookProvider persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('saves entries and loads them back from storage', () async {
      final provider = AddressbookProvider();
      await provider.reloadEntries();

      final error = await provider.addOrUpdateEntry(
        label: 'Savings Wallet',
        address: 'bs1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
      );

      expect(error, isNull);
      expect(provider.entries, hasLength(1));
      expect(provider.entries.first.label, 'Savings Wallet');

      final reloadedProvider = AddressbookProvider();
      await reloadedProvider.reloadEntries();

      expect(reloadedProvider.entries, hasLength(1));
      expect(reloadedProvider.entries.first.label, 'Savings Wallet');
      expect(
        reloadedProvider.entries.first.address,
        'bs1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
      );
    });

    test('imports valid btcs backup payload', () async {
      final provider = AddressbookProvider();
      await provider.reloadEntries();

      const jsonPayload = '''
{
  "version": "1.0",
  "contactCount": 1,
  "contacts": [
    {
      "username": "Alice",
      "address": "bs1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"
    }
  ]
}
''';

      final result = await provider.importFromJsonString(jsonPayload);

      expect(result['success'], true);
      expect(provider.entries, hasLength(1));
      expect(provider.entries.first.label, 'Alice');
    });

    test('exports and reimports roundtrip payload', () async {
      final provider = AddressbookProvider();
      await provider.reloadEntries();

      final addError = await provider.addOrUpdateEntry(
        label: 'Cold Storage',
        address: 'bs1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh',
      );

      expect(addError, isNull);

      final exported = provider.exportToBtcsJson();
      await provider.clearEntries();
      expect(provider.entries, isEmpty);

      final importResult = await provider.importFromBtcsJson(exported);

      expect(importResult['success'], true);
      expect(provider.entries, hasLength(1));
      expect(provider.entries.first.label, 'Cold Storage');
    });

    test('accepts legacy base58 addresses', () async {
      final provider = AddressbookProvider();
      await provider.reloadEntries();

      final error = await provider.addOrUpdateEntry(
        label: 'Legacy Wallet',
        address: 'bJPfKAKhP79hPWAQ8xyJc9PywXQL8Vxw8d',
      );

      expect(error, isNull);
      expect(provider.entries, hasLength(1));
      expect(provider.entries.first.address, 'bJPfKAKhP79hPWAQ8xyJc9PywXQL8Vxw8d');
    });

    test('rejects truncated json payloads', () async {
      final provider = AddressbookProvider();
      await provider.reloadEntries();

      const truncated = '{"version":"1.0","contactCount":1,"contacts":[{"username":"A"';
      final result = await provider.importFromBtcsJson(truncated);

      expect(result['success'], false);
      expect((result['message'] as String).toLowerCase(), contains('incomplete'));
    });
  });
}
