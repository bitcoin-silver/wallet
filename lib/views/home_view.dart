import 'package:flutter/material.dart';

import 'package:bitcoinsilver_wallet/modals/transactions_modal.dart';
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
    null,
    const SettingsView(),
  ];

  void _onItemTapped(int index) {
    if (index == 0) {
      setState(() {
        _selectedIndex = 0;
      });
    } else if (index == 1) {
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(25.0)),
        ),
        isScrollControlled: true,
        builder: (BuildContext context) {
          return const TransactionsModal();
        },
      );
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
                icon: Icon(Icons.sync_alt),
                label: '',
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
            backgroundColor: const Color(0xFF333333),
            selectedLabelStyle: const TextStyle(
              fontSize: 14.0,
              fontWeight: FontWeight.normal,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 14.0,
              fontWeight: FontWeight.normal,
            ),
          ),
          Positioned(
            top: -20,
            left: MediaQuery.of(context).size.width / 2 - 35,
            child: InkWell(
              onTap: () => _onItemTapped(1),
              child: Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(
                  color: Colors.cyanAccent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.sync_alt,
                  color: Color(0xFF333333),
                  size: 36,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
