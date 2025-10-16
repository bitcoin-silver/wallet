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
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          WalletView(),
          ExchangeView(),
          SettingsView(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF1A1A1A),
              const Color(0xFF0A0A0A),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          border: Border(
            top: BorderSide(
              color: const Color(0xFFC0C0C0).withOpacity(0.2),
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          items: const <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.wallet, size: 28),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.sync, size: 28),
              label: '',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings, size: 28),
              label: '',
            ),
          ],
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          selectedItemColor: const Color(0xFFC0C0C0),
          unselectedItemColor: Colors.white.withOpacity(0.5),
          backgroundColor: Colors.transparent,
          elevation: 0,
          showSelectedLabels: false,
          showUnselectedLabels: false,
        ),
      ),
    );
  }
}
