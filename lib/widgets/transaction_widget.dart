import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:bitcoinsilver_wallet/models/transaction.dart';

class TransactionTile extends StatelessWidget {
  final Transaction tx;
  final VoidCallback onTap;

  const TransactionTile({super.key, required this.tx, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isSent = tx.sent > 0;
    final icon = isSent ? Icons.arrow_downward : Icons.arrow_upward;
    final color = isSent ? Colors.green : Colors.red;
    final amount = isSent ? tx.sent : -tx.received;
    final formattedDate =
        DateFormat('dd MMM yyyy HH:mm:ss').format(tx.dateTime);

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
