import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TransactionTile extends StatelessWidget {
  final dynamic tx;
  final VoidCallback onTap;

  const TransactionTile({super.key, required this.tx, required this.onTap});

  String _formatAmount(double amount) {
    // Smart formatting: remove trailing zeros but keep at least 4 decimals
    String formatted = amount.abs().toStringAsFixed(8);
    // Remove trailing zeros, but keep at least 4 decimal places
    while (formatted.contains('.') &&
           (formatted.endsWith('0') && formatted.split('.')[1].length > 4)) {
      formatted = formatted.substring(0, formatted.length - 1);
    }
    return formatted;
  }

  @override
  Widget build(BuildContext context) {
    final amountValue = tx['amount'] as num;
    final amount = _formatAmount(amountValue.toDouble());
    final isReceived = amountValue > 0;
    final icon = isReceived ? Icons.arrow_downward : Icons.arrow_upward;
    final color = isReceived ? Colors.green : Colors.red;
    int timestampInSeconds = tx['timestamp'];
    DateTime dateTime =
        DateTime.fromMillisecondsSinceEpoch(timestampInSeconds * 1000);

    final formattedDate = DateFormat('dd MMM yyyy HH:mm').format(dateTime);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Row(
          children: [
            Text(
              isReceived ? '+' : '-',
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              amount,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'BTCS',
              style: TextStyle(
                color: color.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
        subtitle: Text(
          formattedDate,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }
}
