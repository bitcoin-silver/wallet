import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bitcoinsilver_wallet/services/biometric_service.dart';
import 'package:bitcoinsilver_wallet/views/biometric_gate.dart';

/// Biometric lock under test control: each authenticate() call waits for the
/// test to answer.
class FakeBiometricService extends BiometricService {
  bool enabled;
  bool available = true;
  int prompts = 0;
  Completer<bool>? _pending;

  FakeBiometricService({this.enabled = true});

  @override
  Future<bool> isBiometricEnabled() async => enabled;

  @override
  Future<bool> isBiometricAvailable() async => available;

  @override
  Future<bool> authenticate({
    String localizedReason = 'Please authenticate to continue',
    bool useErrorDialogs = true,
    bool stickyAuth = true,
  }) {
    prompts++;
    _pending = Completer<bool>();
    return _pending!.future;
  }

  void answer(bool ok) => _pending!.complete(ok);
}

// Stand-in for HomeView that opens a "secret" screen on top, like Send.
class _FakeHome extends StatelessWidget {
  const _FakeHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Center(child: Text('SECRET SEND SCREEN'))),
          )),
          child: const Text('HOME'),
        ),
      ),
    );
  }
}

void main() {
  Future<void> goToBackgroundAndBack(WidgetTester tester) async {
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
      await tester.pump();
    }
    await tester.pump();
  }

  Future<FakeBiometricService> startUnlocked(WidgetTester tester, {bool enabled = true}) async {
    final bio = FakeBiometricService(enabled: enabled);
    await tester.pumpWidget(MaterialApp(home: BiometricGate(home: const _FakeHome(), biometricService: bio)));
    await tester.pump();
    if (enabled) {
      expect(find.text('Authenticating...'), findsOneWidget);
      expect(find.text('HOME'), findsNothing, reason: 'nothing visible before the first unlock');
      bio.answer(true);
    }
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
    return bio;
  }

  testWidgets('lock covers a screen opened on top of home, and restores it after unlock', (tester) async {
    final bio = await startUnlocked(tester);
    await tester.tap(find.text('HOME'));
    await tester.pumpAndSettle();
    expect(find.text('SECRET SEND SCREEN'), findsOneWidget);

    await goToBackgroundAndBack(tester);
    expect(find.text('Authenticating...'), findsOneWidget);
    expect(find.text('SECRET SEND SCREEN'), findsNothing, reason: 'must be hidden while locked');
    expect(bio.prompts, 2);

    bio.answer(true);
    await tester.pumpAndSettle();
    expect(find.text('Authenticating...'), findsNothing);
    expect(find.text('SECRET SEND SCREEN'), findsOneWidget, reason: 'the open screen comes back as it was');
  });

  testWidgets('back button does not close the lock or the screens under it', (tester) async {
    final bio = await startUnlocked(tester);
    await tester.tap(find.text('HOME'));
    await tester.pumpAndSettle();

    await goToBackgroundAndBack(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Authenticating...'), findsOneWidget);
    expect(find.text('SECRET SEND SCREEN'), findsNothing);

    bio.answer(true);
    await tester.pumpAndSettle();
    expect(find.text('SECRET SEND SCREEN'), findsOneWidget, reason: 'back did not pop the hidden screen');
  });

  testWidgets('failed unlock shows the failure screen; Try Again unlocks', (tester) async {
    final bio = await startUnlocked(tester);
    await goToBackgroundAndBack(tester);

    bio.answer(false);
    await tester.pumpAndSettle();
    expect(find.text('Authentication Failed'), findsOneWidget);
    expect(find.text('HOME'), findsNothing);

    await tester.tap(find.text('Try Again'));
    await tester.pump();
    bio.answer(true);
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });

  testWidgets('no lock on resume when the biometric lock is off', (tester) async {
    await startUnlocked(tester, enabled: false);
    await tester.tap(find.text('HOME'));
    await tester.pumpAndSettle();

    await goToBackgroundAndBack(tester);
    await tester.pumpAndSettle();
    expect(find.text('Authenticating...'), findsNothing);
    expect(find.text('SECRET SEND SCREEN'), findsOneWidget);
  });

  testWidgets('turning the lock on in Settings takes effect on the next resume', (tester) async {
    final bio = await startUnlocked(tester, enabled: false);
    bio.enabled = true; // user enables it in Settings
    await goToBackgroundAndBack(tester);
    expect(find.text('Authenticating...'), findsOneWidget);
    bio.answer(true);
    await tester.pumpAndSettle();
    expect(find.text('HOME'), findsOneWidget);
  });
}
