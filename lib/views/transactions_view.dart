import 'package:flutter/material.dart';

class TransactionsView extends StatelessWidget {
  const TransactionsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions View'),
      ),
      body: const Center(child: Text('Transactions Content')),
    );
  }
}
