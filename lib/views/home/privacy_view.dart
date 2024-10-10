import 'package:flutter/material.dart';

class PrivacyView extends StatelessWidget {
  const PrivacyView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: const Text(
          'Privacy Policy',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        centerTitle: true,
      ),
      body: Container(
        color: Colors.black,
        constraints: const BoxConstraints.expand(),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(top: 32.0, left: 16.0, right: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Introduction',
                  style: TextStyle(
                      fontSize: 20.0,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 8.0),
                const Text(
                    'We, the team behind the Bitcoin Silver (BTCS) Wallet, take your privacy seriously. '
                    'This Privacy Policy outlines the data we collect, how we use it, and your rights regarding your '
                    'data. By using our app, you agree to the processing of your data as described in this policy.',
                    style: TextStyle(color: Colors.white)),
                const SizedBox(height: 16.0),
                _buildSectionTitle('1. Data Collection and Processing'),
                _buildBulletPoint(
                    'We do not collect personal data directly from you unless you voluntarily provide it to us.'),
                _buildBulletPoint(
                    'The BTCS Wallet is designed to operate without requiring registration, and we do not collect sensitive information such as names, addresses, or email addresses.'),
                _buildBulletPoint(
                    'However, the following data may be automatically collected through the use of the app:'),
                _buildIndentedBullet(
                    '• Device Information: Information about the device, operating system, and app version used.'),
                _buildIndentedBullet(
                    '• Transaction Data: Public blockchain data, such as sending and receiving addresses, as well as transaction amounts.'),
                const SizedBox(height: 16.0),
                _buildSectionTitle('2. Use of Collected Data'),
                _buildBulletPoint(
                    'The data collected through the app is used solely to ensure the functionality of the wallet.'),
                _buildBulletPoint(
                    'We do not collect or store personal data on our servers.'),
                const SizedBox(height: 16.0),
                _buildSectionTitle('3. Sharing Data with Third Parties'),
                _buildBulletPoint(
                    'The BTCS Wallet does not share personal data with third parties.'),
                _buildBulletPoint(
                    'All transactions conducted through the wallet are publicly viewable on the blockchain, but we do not store or track this information.'),
                const SizedBox(height: 16.0),
                _buildSectionTitle('4. Data Security'),
                _buildBulletPoint(
                    'The security of your data is a top priority for us. Your private keys and sensitive information are stored only locally on your device and are never transmitted to us or third parties.'),
                const SizedBox(height: 16.0),
                _buildSectionTitle('5. User Rights'),
                _buildBulletPoint(
                    'Since we do not collect or store personal data, you can delete the app at any time without us retaining any information about you.'),
                _buildBulletPoint(
                    'If this changes in the future, you will be informed and have the right to view, modify, or delete your data.'),
                const SizedBox(height: 16.0),
                _buildSectionTitle('6. Changes to the Privacy Policy'),
                _buildBulletPoint(
                    'We reserve the right to modify this privacy policy to reflect new legal requirements or changes to our app.'),
                _buildBulletPoint(
                    'The current version of the privacy policy will always be available in the app and on our website.'),
                const SizedBox(height: 16.0),
                _buildSectionTitle('7. Contact'),
                _buildBulletPoint(
                    'If you have any questions regarding this privacy policy, feel free to contact us at info@bitcoinsilver.top.'),
                const SizedBox(height: 16.0),
                const Text(
                  'September 5, 2024',
                  style: TextStyle(
                      fontStyle: FontStyle.italic, color: Colors.white),
                ),
                const Text(
                  'Bitcoin Silver Team',
                  style: TextStyle(
                      fontStyle: FontStyle.italic, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
          fontSize: 20.0, fontWeight: FontWeight.bold, color: Colors.white),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 16.0, top: 8.0),
      child: Text(
        '• $text',
        style: const TextStyle(color: Colors.white),
      ),
    );
  }

  Widget _buildIndentedBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 32.0, top: 4.0),
      child: Text(text, style: const TextStyle(color: Colors.white)),
    );
  }
}
