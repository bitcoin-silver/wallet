import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:bitcoinsilver_wallet/config.dart';

class TransactionModal extends StatefulWidget {
  final String txid;

  const TransactionModal({super.key, required this.txid});

  @override
  State<TransactionModal> createState() => _TransactionModalState();
}

class _TransactionModalState extends State<TransactionModal> {
  Map<String, dynamic>? _transactionData;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _fetchTransactionData();
  }

  Future<void> _fetchTransactionData() async {
    final txid = widget.txid;
    final url = '${Config.baseUrl}${Config.getTxEndpoint}/$txid';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _transactionData = data['tx'];
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load transaction data');
      }
    } catch (error) {
      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16.0),
          topRight: Radius.circular(16.0),
        ),
        child: Container(
          color: const Color(0xFF333333),
          padding: const EdgeInsets.all(16.0),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _hasError
                  ? const Center(
                      child: Text('Failed to load transaction details',
                          style: TextStyle(color: Colors.white)))
                  : _transactionData == null
                      ? const Center(
                          child: Text('No transaction data available',
                              style: TextStyle(color: Colors.white)))
                      : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Transaction Details',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildDetailRow(
                                  'TXID', _transactionData!['txid']),
                              _buildDetailRow('Total',
                                  _formatAmount(_transactionData!['total'])),
                              const SizedBox(height: 16),
                              const Text(
                                'Input:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              ...(_transactionData!['vin'] as List).map((vin) {
                                return _buildDetailRow(
                                  _formatAmount(vin['amount']),
                                  vin['addresses'],
                                );
                              }),
                              const SizedBox(height: 16),
                              const Text(
                                'Output:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              ...(_transactionData!['vout'] as List)
                                  .map((vout) {
                                return _buildDetailRow(
                                  _formatAmount(vout['amount']),
                                  vout['addresses'],
                                );
                              }),
                            ],
                          ),
                        ),
        ));
  }

  Widget _buildDetailRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAmount(int amount) {
    final formattedAmount = amount / 100000000;
    return formattedAmount.toStringAsFixed(8);
  }
}
