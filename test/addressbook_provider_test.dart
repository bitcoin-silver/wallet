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

    test('reports the real count when a file has fewer contacts than declared', () async {
      final provider = AddressbookProvider();
      await provider.reloadEntries();

      final result = await provider.importFromBtcsJson(
        '{"version":"1.0","contactCount":3,"contacts":'
        '[{"username":"A","address":"bs1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh"}]}',
      );

      expect(result['success'], false);
      expect(result['message'], contains('(1 of 3 contacts)'));
    });
  });

  // Older exports: FilePicker.saveFile did not truncate when saving over a
  // longer file, so the old file's tail follows the new JSON (real case:
  // 5 contacts followed by 124 leftover bytes). See MainActivity.kt.
  group('AddressbookProvider import of exports with leftover bytes', () {
    const export = '{"version":"1.0","exportDate":"2026-09-24T17:17:06.099880","contactCount":2,'
        '"contacts":[{"username":"miner 4","address":"bs1q8dnz4q52czdusl8hy04fw3jryj2kc3earck3y2",'
        '"isFavorite":true,"addedAt":"2026-09-06T11:06:59.984662"},'
        '{"username":"Raul.A","address":"bs1qxxmaq9929mddelzh2x73ydwcq6xvd0z4yxh55p",'
        '"isFavorite":true,"addedAt":"2026-06-17T23:07:18.750032"}]}';
    const leftover = '"username":"Raul.A","address":"bs1qxxmaq9929mddelzh2x73ydwcq6xvd0z4yxh55p",'
        '"isFavorite":true,"addedAt":"2026-06-17T23:07:18.750032"}]}';

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('imports the complete export and ignores the leftovers', () async {
      final provider = AddressbookProvider();
      await provider.reloadEntries();

      final result = await provider.importFromBtcsJson(export + leftover);

      expect(result['success'], true);
      expect(result['imported'], 2);
      expect(result['message'], contains('Leftover data'));
      expect(provider.entries.map((e) => e.label), ['miner 4', 'Raul.A']);
    });

    test('refuses leftovers when the contact count does not match', () async {
      final provider = AddressbookProvider();
      await provider.reloadEntries();

      final wrongCount = export.replaceFirst('"contactCount":2', '"contactCount":7');
      final result = await provider.importFromBtcsJson(wrongCount + leftover);

      expect(result['success'], false);
      expect(provider.entries, isEmpty);
    });

    test('refuses leftovers when there is no contact count', () async {
      final provider = AddressbookProvider();
      await provider.reloadEntries();

      final noCount = export.replaceFirst('"contactCount":2,', '');
      final result = await provider.importFromBtcsJson(noCount + leftover);

      expect(result['success'], false);
      expect(provider.entries, isEmpty);
    });
  });
}
