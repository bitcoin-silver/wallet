import 'package:flutter/material.dart';
import 'package:bitcoinsilver_wallet/views/home/exchange_view.dart';
import 'package:bitcoinsilver_wallet/views/home/wallet_view.dart';
import 'package:bitcoinsilver_wallet/views/home/settings_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});
  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  int _selectedIndex = 0;

  final List<Widget?> _pages = [
    const WalletView(),
    const ExchangeView(),
    const SettingsView(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex] ?? Container(),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.wallet, size: 32),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sync, size: 32),
            label: '',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings, size: 32),
            label: '',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.cyanAccent,
        unselectedItemColor: Colors.white,
        backgroundColor: Colors.black,
        showSelectedLabels: false,
        showUnselectedLabels: false,
      ),
    );
  }
}
