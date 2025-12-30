import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchTransactionData();
  }

  Future<void> _fetchTransactionData() async {
    final txid = widget.txid;
    final url = '${Config.explorerUrl}${Config.getTxEndpoint}?txid=$txid';

    try {
      final response = await http.get(Uri.parse(url)).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Request timed out after 15 seconds');
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;

        setState(() {
          _transactionData = data;
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load transaction data (Status: ${response.statusCode})');
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
        _errorMessage = 'Connection timeout. Please try again.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _isLoading = false;
        _errorMessage = 'Failed to load transaction details: ${error.toString()}';
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
          color: Colors.black,
          padding: const EdgeInsets.all(16.0),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _hasError
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage.isNotEmpty
                                ? _errorMessage
                                : 'Failed to load transaction details',
                            style: const TextStyle(color: Colors.white),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _isLoading = true;
                                _hasError = false;
                                _errorMessage = '';
                              });
                              _fetchTransactionData();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent,
                              foregroundColor: Colors.black,
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
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
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white54,
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

  String _formatAmount(num amount) {
    // New explorer API returns amounts in BTCS format (not satoshis)
    return amount.toStringAsFixed(8);
  }
}
