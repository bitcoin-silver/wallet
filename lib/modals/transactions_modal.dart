import 'package:flutter/material.dart';
import 'package:bitcoinsilver_wallet/views/home/transaction/send_view.dart';
import 'package:bitcoinsilver_wallet/views/home/transaction/receive_view.dart';

class TransactionsModal extends StatelessWidget {
  const TransactionsModal({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16.0),
        topRight: Radius.circular(16.0),
      ),
      child: Container(
        color: const Color(0xFF333333), // Hintergrundfarbe des Modals
        padding: const EdgeInsets.symmetric(
            horizontal: 16.0), // Spacing on the sides
        child: Column(
          mainAxisSize: MainAxisSize.min, // Automatically size to content
          children: [
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.arrow_upward,
                  size: 24, color: Colors.white), // Iconfarbe
              title: const Text(
                'Send',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white), // Textfarbe
              ),
              subtitle: const Text(
                  'Lorem ipsum dolor sit amet, consectetur adipiscing elit.',
                  style: TextStyle(color: Colors.white)), // Subtitle Textfarbe
              onTap: () {
                Navigator.pop(context); // Close the modal
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SendView()),
                );
              },
            ),
            const Divider(color: Colors.white), // Dividerfarbe
            ListTile(
              leading: const Icon(Icons.arrow_downward,
                  size: 24, color: Colors.white), // Iconfarbe
              title: const Text(
                'Receive',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white), // Textfarbe
              ),
              subtitle: const Text(
                  'Lorem ipsum dolor sit amet, consectetur adipiscing elit.',
                  style: TextStyle(color: Colors.white)), // Subtitle Textfarbe
              onTap: () {
                Navigator.pop(context); // Close the modal
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ReceiveView()),
                );
              },
            ),
            const SizedBox(height: 20),
            // Schließen Button
            Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.all(8.0),
              child: Container(
                width: 70,
                height: 70,
                decoration: const BoxDecoration(
                  color: Colors
                      .cyanAccent, // Background color of the circle (Neon Blue)
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 10,
                      offset: Offset(0, 5), // Shadow position
                    ),
                  ],
                ),
                child: IconButton(
                  icon: const Icon(Icons.close,
                      color: Color(0xFF333333), size: 36),
                  onPressed: () {
                    Navigator.pop(context); // Close the modal
                  },
                  padding: const EdgeInsets.all(16.0), // Padding für das Icon
                  constraints: const BoxConstraints(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
