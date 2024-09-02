class Transaction {
  final String txid;
  final double sent;
  final double received;
  final double balance;
  final int timestamp;

  Transaction({
    required this.txid,
    required this.sent,
    required this.received,
    required this.balance,
    required this.timestamp,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      txid: json['txid'],
      sent: json['sent'].toDouble(),
      received: json['received'].toDouble(),
      balance: json['balance'].toDouble(),
      timestamp: json['timestamp'],
    );
  }

  DateTime get dateTime =>
      DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
}
