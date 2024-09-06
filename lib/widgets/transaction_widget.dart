import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TransactionTile extends StatelessWidget {
  final dynamic tx;
  final VoidCallback onTap;

  const TransactionTile({super.key, required this.tx, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final amount = tx['amount'].toStringAsFixed(8);
    final icon = tx['amount'] > 0 ? Icons.arrow_downward : Icons.arrow_upward;
    final color = tx['amount'] > 0 ? Colors.green : Colors.red;
    int timestampInSeconds = tx['timestamp'];
    DateTime dateTime =
        DateTime.fromMillisecondsSinceEpoch(timestampInSeconds * 1000);

    final formattedDate = DateFormat('dd MMM yyyy HH:mm:ss').format(dateTime);

    return ListTile(
      leading: Icon(icon, color: color),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formattedDate,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Text('$amount BTCS', style: TextStyle(color: color)),
        ],
      ),
      onTap: onTap,
    );
  }
}
