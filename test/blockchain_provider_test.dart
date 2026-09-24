import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:bitcoinsilver_wallet/providers/blockchain_provider.dart';

// A background ("silent") refresh on app resume must keep the current
// history on screen until the explorer answers, and keep it if it fails.
void main() {
  const address = 'bs1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh';

  Map<String, dynamic> tx(String id, int amount) =>
      {'txid': id, 'timestamp': 1700000000, 'amount': amount, 'type': 'received'};

  // Explorer answers from [explorer]; everything else (price API) gets 404.
  MockClient client(FutureOr<http.Response> Function() explorer) => MockClient((request) async {
        if (request.url.path.contains('price') || request.method == 'POST') {
          return http.Response('{}', 404);
        }
        return explorer();
      });

  http.Response ok(List<Map<String, dynamic>> txs) =>
      http.Response(jsonEncode({'transactions': txs}), 200);

  Future<BlockchainProvider> loaded(List<Map<String, dynamic>> txs) async {
    final bp = BlockchainProvider();
    await http.runWithClient(() => bp.loadBlockchain(address), () => client(() => ok(txs)));
    return bp;
  }

  test('initial load fills the list', () async {
    final bp = await loaded([tx('a', 1), tx('b', 2)]);
    expect(bp.transactions.map((t) => t['txid']), ['a', 'b']);
  });

  test('silent refresh keeps the list while waiting, then replaces it', () async {
    final bp = await loaded([tx('a', 1)]);
    final gate = Completer<http.Response>();

    final refresh = http.runWithClient(
      () => bp.loadBlockchain(address, silent: true),
      () => client(() => gate.future),
    );
    await Future<void>.delayed(Duration.zero);
    expect(bp.transactions.map((t) => t['txid']), ['a'], reason: 'must not flash an empty list');

    gate.complete(ok([tx('new', 5), tx('a', 1)]));
    await refresh;
    expect(bp.transactions.map((t) => t['txid']), ['new', 'a']);
  });

  test('failed silent refresh keeps the previous list', () async {
    final bp = await loaded([tx('a', 1), tx('b', 2)]);
    await http.runWithClient(
      () => bp.loadBlockchain(address, silent: true),
      () => client(() => http.Response('boom', 500)),
    );
    expect(bp.transactions.map((t) => t['txid']), ['a', 'b']);
  });

  test('silent refresh to an empty history empties the list', () async {
    final bp = await loaded([tx('a', 1)]);
    await http.runWithClient(
      () => bp.loadBlockchain(address, silent: true),
      () => client(() => ok([])),
    );
    expect(bp.transactions, isEmpty);
  });

  test('silent refresh restarts paging from the newest page', () async {
    final many = List.generate(120, (i) => tx('t$i', 1));
    final bp = await loaded(many);
    expect(bp.transactions, hasLength(50));

    // "Load more" fetches the next page.
    await http.runWithClient(() => bp.fetchTransactions(address), () => client(() => ok(many)));
    expect(bp.transactions, hasLength(100));

    await http.runWithClient(
      () => bp.loadBlockchain(address, silent: true),
      () => client(() => ok(many)),
    );
    expect(bp.transactions, hasLength(50));
    expect(bp.transactions.first['txid'], 't0');
    expect(bp.hasMore, isTrue);
  });
}
