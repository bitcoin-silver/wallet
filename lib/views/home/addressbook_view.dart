import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:bitcoinsilver_wallet/providers/addressbook_provider.dart';
import 'package:bitcoinsilver_wallet/views/home/scanner_view.dart';
import 'package:bitcoinsilver_wallet/widgets/app_background.dart';

class AddressbookView extends StatefulWidget {
  final bool selectionMode;

  const AddressbookView({
    super.key,
    this.selectionMode = false,
  });

  @override
  State<AddressbookView> createState() => _AddressbookViewState();
}

class _AddressbookViewState extends State<AddressbookView> {
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  String? _editingAddress;
  bool _isBusy = false;

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _saveEntry() async {
    final provider = context.read<AddressbookProvider>();

    setState(() {
      _isBusy = true;
    });

    final error = await provider.addOrUpdateEntry(
      label: _labelController.text,
      address: _addressController.text,
      originalAddress: _editingAddress,
    );

    if (!mounted) return;

    setState(() {
      _isBusy = false;
    });

    if (error != null) {
      _showSnack(error, isError: true);
      return;
    }

    _labelController.clear();
    _addressController.clear();
    _editingAddress = null;
    _showSnack('Address saved.');
  }

  void _startEdit(String label, String address) {
    setState(() {
      _editingAddress = address;
      _labelController.text = label;
      _addressController.text = address;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingAddress = null;
      _labelController.clear();
      _addressController.clear();
    });
  }

  Future<void> _deleteEntry(String address) async {
    await context.read<AddressbookProvider>().removeEntry(address);
    if (!mounted) return;

    if (_editingAddress?.toLowerCase() == address.toLowerCase()) {
      _cancelEdit();
    }
    _showSnack('Address removed.');
  }

  void _copyAddress(String address) {
    Clipboard.setData(ClipboardData(text: address));
    _showSnack('Address copied to clipboard.');
  }

  Future<void> _scanAddress() async {
    final scannedAddress = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ScannerView(),
      ),
    );

    if (scannedAddress != null && mounted) {
      setState(() {
        _addressController.text = scannedAddress;
      });
    }
  }

  Future<void> _importContacts() async {
    final provider = context.read<AddressbookProvider>();
    try {
      PlatformFile? fileResult = await FilePicker.pickFile(
        type: FileType.any,
      );

      if (fileResult != null && fileResult.path != null) {
        final file = File(fileResult.path!);
        final bytes = await file.readAsBytes();
        final content = utf8.decode(bytes, allowMalformed: false);
        final importResult = await provider.importFromBtcsJson(content);

        if (mounted) {
          _showSnack(importResult['message'], isError: !importResult['success']);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Import failed: $e', isError: true);
      }
    }
  }

  Future<void> _exportContacts() async {
    final provider = context.read<AddressbookProvider>();
    if (provider.entries.isEmpty) {
      _showSnack('Address book is empty.', isError: true);
      return;
    }

    try {
      final jsonString = provider.exportToBtcsJson();
      final bytes = Uint8List.fromList(utf8.encode(jsonString));

      dynamic outputResult = await FilePicker.saveFile(
        dialogTitle: 'Export Address Book',
        fileName: 'BTCS_contacts.btcs',
        bytes: bytes,
      );

      if (mounted && outputResult != null) {
        _showSnack('Address book exported.');
      }
    } catch (e) {
      if (mounted) {
        _showSnack('Export failed: $e', isError: true);
      }
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      return;
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? const Color(0xFFD32F2F) : const Color(0xFF111111),
        duration: Duration(milliseconds: isError ? 2600 : 1600),
      ),
    );
  }

  Widget _buildEntryTile(dynamic entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: ListTile(
        leading: const Icon(
          Icons.contact_page_rounded,
          color: Colors.cyanAccent,
        ),
        title: Text(
          entry.label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          entry.address,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        onTap: () {
          if (widget.selectionMode) {
            Navigator.pop(context, entry);
          } else {
            _copyAddress(entry.address);
          }
        },
        trailing: widget.selectionMode
            ? const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.white38,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.white70),
                    tooltip: 'Edit',
                    onPressed:
                        _isBusy ? null : () => _startEdit(entry.label, entry.address),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    tooltip: 'Delete',
                    onPressed: _isBusy ? null : () => _deleteEntry(entry.address),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildAddContactCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _editingAddress == null ? 'Add address' : 'Edit address',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _labelController,
            enabled: !_isBusy,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Label',
              hintText: 'e.g. Savings Wallet',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _addressController,
            enabled: !_isBusy,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'Address',
              hintText: 'bs1...',
              suffixIcon: IconButton(
                icon: const Icon(Icons.qr_code_scanner, color: Colors.cyanAccent),
                tooltip: 'Scan QR code',
                onPressed: _isBusy ? null : _scanAddress,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isBusy ? null : _saveEntry,
                  icon: Icon(_editingAddress == null ? Icons.add : Icons.save),
                  label: Text(_editingAddress == null ? 'Save' : 'Update'),
                ),
              ),
              if (_editingAddress != null) ...[
                const SizedBox(width: 10),
                TextButton(
                  onPressed: _isBusy ? null : _cancelEdit,
                  child: const Text('Cancel'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AddressbookProvider>(
      builder: (context, provider, child) {
        final entries = provider.entries;
        final mediaQuery = MediaQuery.of(context);
        final bottomSafeInset = mediaQuery.padding.bottom;

        return AppBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: true,
            appBar: AppBar(
              title: Text(widget.selectionMode ? 'Select Address' : 'Address Book'),
              actions: [
                if (!widget.selectionMode) ...[
                  IconButton(
                    icon: const Icon(Icons.download_rounded),
                    tooltip: 'Import from file',
                    onPressed: _isBusy ? null : _importContacts,
                  ),
                  IconButton(
                    icon: const Icon(Icons.upload_rounded),
                    tooltip: 'Export to file',
                    onPressed: _isBusy ? null : _exportContacts,
                  ),
                ],
              ],
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.selectionMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _buildAddContactCard(),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 18, 16, 10),
                  child: Text(
                    'Saved Addresses',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: provider.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : entries.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: _EmptyAddressbookCard(),
                            )
                          : ListView.builder(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                0,
                                16,
                                16 + bottomSafeInset + (widget.selectionMode ? 0 : 80),
                              ),
                              itemCount: entries.length,
                              itemBuilder: (context, index) =>
                                  _buildEntryTile(entries[index]),
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EmptyAddressbookCard extends StatelessWidget {
  const _EmptyAddressbookCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: const Text(
        'No saved addresses yet. Add one above.',
        style: TextStyle(color: Colors.white70),
      ),
    );
  }
}