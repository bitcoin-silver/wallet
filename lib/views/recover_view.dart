import 'package:flutter/material.dart';
import 'home_view.dart';

class RecoverView extends StatelessWidget {
  final TextEditingController _controller = TextEditingController();

  RecoverView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recover View'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Recovery Phrase',
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Save recovery phrase and navigate to home view
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const HomeView()),
                );
              },
              child: const Text('Wiederherstellen'),
            ),
          ],
        ),
      ),
    );
  }
}
