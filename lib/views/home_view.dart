import 'package:flutter/material.dart';

import 'package:bitcoinsilver_wallet/views/home/wallet_view.dart';
import 'package:bitcoinsilver_wallet/views/home/transactions_view.dart';
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
    const TransactionsView(),
    const SettingsView(),
  ];

  void _onItemTapped(int index) {
    if (index == 0) {
      setState(() {
        _selectedIndex = 0;
      });
    } else if (index == 1) {
      setState(() {
        _selectedIndex = 1;
      });
    } else if (index == 2) {
      setState(() {
        _selectedIndex = 2;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex] ?? Container(),
      bottomNavigationBar: Stack(
        clipBehavior: Clip.none,
        children: [
          BottomNavigationBar(
            items: const <BottomNavigationBarItem>[
              BottomNavigationBarItem(
                icon: Icon(Icons.wallet),
                label: 'Wallet',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.repeat),
                label: 'Transactions',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
            currentIndex: _selectedIndex,
            onTap: (index) {
              setState(() {
                _selectedIndex = index;
              });
              _onItemTapped(index);
            },
            selectedItemColor: Colors.cyanAccent,
            unselectedItemColor: Colors.white,
            backgroundColor: const Color.fromARGB(255, 25, 25, 25),
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
            unselectedLabelStyle: const TextStyle(
              fontSize: 14.0,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
