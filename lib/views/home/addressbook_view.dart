import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/addressbook_provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:bitcoinsilver_wallet/models/addressbook_entry.dart';
import 'package:bitcoinsilver_wallet/widgets/app_background.dart';
import 'package:bitcoinsilver_wallet/widgets/button_widget.dart';
import 'package:file_picker/file_picker.dart';

class AddressbookView extends StatefulWidget {
  final bool selectionMode;
  final Function(String address, String username)? onAddressSelected;

  const AddressbookView({
    super.key,
    this.selectionMode = false,
    this.onAddressSelected,
  });

  @override
  State<AddressbookView> createState() => _AddressbookViewState();
}

class _AddressbookViewState extends State<AddressbookView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();

  bool _searchByUsername = true;
  String? _registrationMessage;
  bool _registrationSuccess = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final provider = Provider.of<AddressbookProvider>(context, listen: false);
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      return;
    }

    FocusScope.of(context).unfocus();

    if (_searchByUsername) {
      await provider.searchByUsername(query);
    } else {
      await provider.searchByAddress(query);
    }
  }

  Future<void> _registerUsername() async {
    final provider = Provider.of<AddressbookProvider>(context, listen: false);
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final username = _usernameController.text.trim();

    if (username.isEmpty) {
      setState(() {
        _registrationMessage = 'Please enter a username';
        _registrationSuccess = false;
      });
      return;
    }

    if (username.length < 4) {
      setState(() {
        _registrationMessage = 'Username must be at least 4 characters';
        _registrationSuccess = false;
      });
      return;
    }

    final address = walletProvider.address;
    if (address == null || address.isEmpty) {
      setState(() {
        _registrationMessage = 'Wallet address not available';
        _registrationSuccess = false;
      });
      return;
    }

    FocusScope.of(context).unfocus();

    final success = await provider.registerUsername(
      username: username,
      address: address,
    );

    setState(() {
      if (success) {
        _registrationMessage = 'Successfully registered as @$username';
        _registrationSuccess = true;
        _usernameController.clear();
      } else {
        _registrationMessage = provider.errorMessage ?? 'Registration failed';
        _registrationSuccess = false;
      }
    });

    // Show snackbar for immediate feedback
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error_outline,
                color: success ? Colors.green : Colors.orange,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  success
                      ? 'Successfully registered as @$username!'
                      : provider.errorMessage ?? 'Registration failed',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: success
              ? Colors.green.withOpacity(0.9)
              : Colors.orange.withOpacity(0.9),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }

    // Clear message after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _registrationMessage = null;
        });
      }
    });
  }

  Future<void> _exportContacts() async {
    final provider = Provider.of<AddressbookProvider>(context, listen: false);

    try {
      // Get export data from provider
      final result = await provider.exportToFile();

      if (!result['success']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.orange, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      result['message'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.orange.withOpacity(0.9),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return;
      }

      // Convert JSON string to bytes
      final jsonData = result['data'].toString();
      final bytes = utf8.encode(jsonData);

      // Use file picker to save the file with bytes
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Contacts',
        fileName: 'BTCS_contacts.btcs',
        bytes: Uint8List.fromList(bytes),
      );

      if (outputPath != null) {

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Exported ${result['count']} contacts successfully',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green.withOpacity(0.9),
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } catch (e, stackTrace) {
      // Log detailed error for debugging
      debugPrint('Export error: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.orange, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Export failed: ${e.toString()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange.withOpacity(0.9),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _importContacts() async {
    final provider = Provider.of<AddressbookProvider>(context, listen: false);

    try {
      // Open file picker
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;

        // Import the file
        final importResult = await provider.importFromFile(filePath);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    importResult['success'] ? Icons.check_circle : Icons.error_outline,
                    color: importResult['success'] ? Colors.green : Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      importResult['message'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: importResult['success']
                  ? Colors.green.withOpacity(0.9)
                  : Colors.orange.withOpacity(0.9),
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.orange, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Failed to import: ${e.toString()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.orange.withOpacity(0.9),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        backgroundColor: const Color(0xFF2A2A2A),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<AddressbookProvider>(context);
    final walletProvider = Provider.of<WalletProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Address Book',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color(0xFF1A1A1A),
        iconTheme: const IconThemeData(color: Colors.cyanAccent),
        elevation: 0,
        bottom: widget.selectionMode
            ? null
            : TabBar(
                controller: _tabController,
                indicatorColor: Colors.cyanAccent,
                labelColor: Colors.cyanAccent,
                unselectedLabelColor: Colors.white54,
                tabs: const [
                  Tab(text: 'Search'),
                  Tab(text: 'Register'),
                  Tab(text: 'Favorites'),
                ],
              ),
      ),
      body: AppBackground(
        child: widget.selectionMode
            ? _buildSelectionModeView(provider)
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildSearchTab(provider),
                  _buildRegisterTab(provider, walletProvider),
                  _buildFavoritesTab(provider),
                ],
              ),
      ),
    );
  }

  Widget _buildSelectionModeView(AddressbookProvider provider) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select a contact',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            if (provider.favorites.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Icon(
                        Icons.contacts_outlined,
                        size: 64,
                        color: Colors.white.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No favorites yet',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...provider.favorites.map((entry) => _buildContactCard(
                    entry,
                    provider,
                    selectable: true,
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchTab(AddressbookProvider provider) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SilverCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildToggleButton(
                          'Username',
                          _searchByUsername,
                          () => setState(() => _searchByUsername = true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildToggleButton(
                          'Address',
                          !_searchByUsername,
                          () => setState(() => _searchByUsername = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: _searchByUsername ? 'Enter username' : 'Enter address',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.cyanAccent),
                      ),
                      prefixIcon: Icon(
                        _searchByUsername ? Icons.person : Icons.account_balance_wallet,
                        color: Colors.cyanAccent,
                      ),
                    ),
                    onSubmitted: (_) => _performSearch(),
                  ),
                  const SizedBox(height: 16),
                  ButtonWidget(
                    text: 'Search',
                    isPrimary: true,
                    icon: Icons.search,
                    onPressed: provider.isLoading ? null : _performSearch,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (provider.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: Colors.cyanAccent),
                ),
              )
            else if (provider.errorMessage != null)
              SilverCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.orange),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        provider.errorMessage!,
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              )
            else if (provider.lastSearchResult != null)
              _buildSearchResult(provider.lastSearchResult!, provider)
            else if (provider.recentSearches.isNotEmpty) ...[
              const Text(
                'Recent Searches',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ...provider.recentSearches.map((entry) => _buildContactCard(entry, provider)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRegisterTab(AddressbookProvider provider, WalletProvider walletProvider) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SilverCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Wallet Address',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            walletProvider.address ?? 'No address available',
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          color: Colors.white54,
                          onPressed: walletProvider.address != null
                              ? () => _copyToClipboard(walletProvider.address!, 'Address')
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SilverCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Register Username',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose a unique username for your wallet address',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _usernameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Enter username',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.cyanAccent),
                      ),
                      prefixIcon: const Icon(Icons.alternate_email, color: Colors.cyanAccent),
                    ),
                    onSubmitted: (_) => _registerUsername(),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: Colors.cyanAccent.withOpacity(0.5),
                      disabledForegroundColor: Colors.black.withOpacity(0.5),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: provider.isLoading ? null : _registerUsername,
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.app_registration, color: Colors.black),
                        SizedBox(width: 8),
                        Text(
                          'REGISTER',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_registrationMessage != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _registrationSuccess
                            ? Colors.green.withOpacity(0.1)
                            : Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _registrationSuccess
                              ? Colors.green.withOpacity(0.3)
                              : Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _registrationSuccess ? Icons.check_circle : Icons.error_outline,
                            color: _registrationSuccess ? Colors.green : Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _registrationMessage!,
                              style: TextStyle(
                                color: _registrationSuccess ? Colors.green : Colors.orange,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            SilverCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Backup & Restore',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Backup your favorite contacts to a .btcs file or restore from a previous backup',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.cyan.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.cyanAccent, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              'About Backup Files',
                              style: TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• Export saves all favorites to BTCS_contacts.btcs\n'
                          '• Import restores contacts from backup files\n'
                          '• Duplicates are automatically skipped\n'
                          '• Files are validated for security',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ButtonWidget(
                          text: 'Export',
                          isPrimary: false,
                          icon: Icons.upload_file,
                          onPressed: provider.isLoading ? null : _exportContacts,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ButtonWidget(
                          text: 'Import',
                          isPrimary: false,
                          icon: Icons.download,
                          onPressed: provider.isLoading ? null : _importContacts,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'How it works',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '• Register a unique username for your wallet\n'
                    '• Others can send BTCS using your username\n'
                    '• Your address will be publicly linked to your username\n'
                    '• Usernames are registered on a first-come basis',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoritesTab(AddressbookProvider provider) {
    return provider.favorites.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.star_border,
                    size: 64,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No favorites yet',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Search for users and add them to favorites',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: provider.favorites.map((entry) => _buildContactCard(entry, provider)).toList(),
          );
  }

  Widget _buildSearchResult(AddressbookEntry entry, AddressbookProvider provider) {
    return SilverCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: Colors.cyanAccent),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '@${entry.username}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _copyToClipboard(entry.address, 'Address'),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.address,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.copy,
                            size: 14,
                            color: Colors.white.withOpacity(0.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ButtonWidget(
            text: provider.isFavorite(entry) ? 'Remove from Favorites' : 'Add to Favorites',
            isPrimary: !provider.isFavorite(entry),
            icon: provider.isFavorite(entry) ? Icons.star : Icons.star_border,
            onPressed: () {
              if (provider.isFavorite(entry)) {
                provider.removeFromFavorites(entry);
              } else {
                provider.addToFavorites(entry);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(
    AddressbookEntry entry,
    AddressbookProvider provider, {
    bool selectable = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: Key(entry.username + entry.address),
        direction: selectable ? DismissDirection.none : DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        onDismissed: (_) => provider.removeFromFavorites(entry),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: selectable
                ? () {
                    widget.onAddressSelected?.call(entry.address, entry.username);
                    Navigator.pop(context);
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person, color: Colors.cyanAccent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${entry.username}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${entry.address.substring(0, 12)}...${entry.address.substring(entry.address.length - 8)}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selectable)
                    Icon(Icons.arrow_forward_ios, color: Colors.white.withOpacity(0.3), size: 16)
                  else
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      color: Colors.white54,
                      onPressed: () => _copyToClipboard(entry.address, 'Address'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButton(String text, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? Colors.cyanAccent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? Colors.cyanAccent : Colors.white.withOpacity(0.2),
            width: isActive ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              color: isActive ? Colors.cyanAccent : Colors.white.withOpacity(0.6),
              fontSize: 14,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
