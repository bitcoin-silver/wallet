import 'package:flutter/material.dart';
import 'home_view.dart';
import 'recover_view.dart';

class StartView extends StatelessWidget {
  const StartView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Start View'),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          ElevatedButton(
            onPressed: () {
              // Navigate directly to home view
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const HomeView()),
              );
            },
            child: const Text('Wallet erstellen'),
          ),
          ElevatedButton(
            onPressed: () {
              // Navigate to recover view
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => RecoverView()),
              );
            },
            child: const Text('Wallet wiederherstellen'),
          ),
        ],
      ),
    );
  }
}
