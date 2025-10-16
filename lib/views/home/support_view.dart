import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bitcoinsilver_wallet/widgets/app_background.dart';

class SupportView extends StatelessWidget {
  const SupportView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'Support',
          style: TextStyle(color: Colors.white, fontSize: 20),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
      ),
      body: AppBackground(
        child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Colors.cyanAccent.withOpacity(0.3),
                        Colors.cyanAccent.withOpacity(0.1),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: const Icon(
                    Icons.support_agent,
                    size: 60,
                    color: Colors.cyanAccent,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              const Center(
                child: Text(
                  'Get Help & Connect',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),

              const Center(
                child: Text(
                  'We\'re here to help you with Bitcoin Silver',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 15,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 32),

              // Contact Section
              _buildSectionTitle('Contact Us'),
              const SizedBox(height: 16),

              _buildContactCard(
                icon: Icons.language,
                title: 'Website',
                subtitle: 'bitcoinsilver.top',
                url: 'https://bitcoinsilver.top',
                color: Colors.blue,
              ),

              _buildContactCard(
                icon: Icons.email,
                title: 'Email',
                subtitle: 'info@bitcoinsilver.top',
                url: 'mailto:info@bitcoinsilver.top',
                color: Colors.red,
              ),

              const SizedBox(height: 32),

              // Community Section
              _buildSectionTitle('Join Our Community'),
              const SizedBox(height: 16),

              _buildContactCard(
                icon: Icons.chat,
                title: 'Discord',
                subtitle: 'Join our Discord server',
                url: 'https://discord.com/invite/MCGn7dzvgd',
                color: const Color(0xFF5865F2),
              ),

              _buildContactCard(
                icon: Icons.send,
                title: 'Telegram',
                subtitle: 'Follow us on Telegram',
                url: 'https://t.me/official_bitcoinsilver',
                color: const Color(0xFF0088CC),
              ),

              _buildContactCard(
                icon: Icons.tag,
                title: 'X (Twitter)',
                subtitle: '@Official_BTCS',
                url: 'https://x.com/Official_BTCS',
                color: Colors.black,
                iconColor: Colors.white,
              ),

              const SizedBox(height: 32),

              // Resources Section
              _buildSectionTitle('Resources'),
              const SizedBox(height: 16),

              _buildContactCard(
                icon: Icons.code,
                title: 'Developers',
                subtitle: 'View our GitHub repository',
                url: 'https://github.com/bitcoin-silver',
                color: const Color(0xFF24292e),
                iconColor: Colors.white,
              ),

              _buildContactCard(
                icon: Icons.savings,
                title: 'Mining Pool',
                subtitle: 'Start mining BTCS',
                url: 'https://sha256-mining.go.ro:50300/',
                color: Colors.orange,
              ),

              const SizedBox(height: 32),

              // Help Message
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.cyanAccent.withOpacity(0.2),
                      Colors.cyanAccent.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.cyanAccent,
                      size: 24,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Need immediate assistance? Join our Discord or Telegram for real-time support from our community.',
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 14,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
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
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildContactCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String url,
    required Color color,
    Color? iconColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () async {
          final uri = Uri.parse(url);
          try {
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          } catch (e) {
            // Silently handle - no app available to open this link
          }
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: iconColor ?? Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white.withOpacity(0.3),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
