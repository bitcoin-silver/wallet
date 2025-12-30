import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PrivacyView extends StatefulWidget {
  const PrivacyView({super.key});

  @override
  State<PrivacyView> createState() => _PrivacyViewState();
}

class _PrivacyViewState extends State<PrivacyView>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();

    _scrollController.addListener(() {
      final isScrolled = _scrollController.offset > 10;
      if (isScrolled != _isScrolled) {
        setState(() {
          _isScrolled = isScrolled;
        });
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: _buildAppBar(context),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black,
                Colors.grey.shade900,
                Colors.black,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
          child: SafeArea(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildHeader(),
                            const SizedBox(height: 32),
                            _buildIntroduction(),
                            const SizedBox(height: 32),
                            ..._buildSections(),
                            const SizedBox(height: 40),
                            _buildFooter(),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: _isScrolled ? Colors.black.withValues(alpha: 0.9) : Colors.transparent,
      elevation: _isScrolled ? 1 : 0,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.pop(context);
          },
        ),
      ),
      title: AnimatedOpacity(
        opacity: _isScrolled ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: const Text(
          'Privacy Policy',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      centerTitle: true,
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade700, Colors.blue.shade900],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'PRIVACY FIRST',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Privacy Policy',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade400),
            const SizedBox(width: 6),
            Text(
              'Last updated: September 5, 2024',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIntroduction() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.withValues(alpha: 0.1),
            Colors.purple.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: Colors.blue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Introduction',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'We, the team behind the Bitcoin Silver (BTCS) Wallet, take your privacy seriously. '
                'This Privacy Policy outlines the data we collect, how we use it, and your rights regarding your '
                'data. By using our app, you agree to the processing of your data as described in this policy.',
            style: TextStyle(
              color: Colors.grey.shade300,
              fontSize: 15,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSections() {
    final sections = [
      {
        'icon': Icons.data_usage,
        'title': 'Data Collection and Processing',
        'color': Colors.orange,
        'points': <String>[
          'We do not collect personal data directly from you unless you voluntarily provide it to us.',
          'The BTCS Wallet is designed to operate without requiring registration, and we do not collect sensitive information such as names, addresses, or email addresses.',
          'However, the following data may be automatically collected through the use of the app:',
        ],
        'subPoints': <String>[
          'Device Information: Information about the device, operating system, and app version used.',
          'Transaction Data: Public blockchain data, such as sending and receiving addresses, as well as transaction amounts.',
        ],
      },
      {
        'icon': Icons.analytics_outlined,
        'title': 'Use of Collected Data',
        'color': Colors.green,
        'points': <String>[
          'The data collected through the app is used solely to ensure the functionality of the wallet.',
          'We do not collect or store personal data on our servers.',
        ],
        'subPoints': <String>[],
      },
      {
        'icon': Icons.share_outlined,
        'title': 'Sharing Data with Third Parties',
        'color': Colors.purple,
        'points': <String>[
          'The BTCS Wallet does not share personal data with third parties.',
          'All transactions conducted through the wallet are publicly viewable on the blockchain, but we do not store or track this information.',
        ],
        'subPoints': <String>[],
      },
      {
        'icon': Icons.security,
        'title': 'Data Security',
        'color': Colors.red,
        'points': <String>[
          'The security of your data is a top priority for us. Your private keys and sensitive information are stored only locally on your device and are never transmitted to us or third parties.',
        ],
        'subPoints': <String>[],
      },
      {
        'icon': Icons.person_outline,
        'title': 'User Rights',
        'color': Colors.cyan,
        'points': <String>[
          'Since we do not collect or store personal data, you can delete the app at any time without us retaining any information about you.',
          'If this changes in the future, you will be informed and have the right to view, modify, or delete your data.',
        ],
        'subPoints': <String>[],
      },
      {
        'icon': Icons.update,
        'title': 'Changes to the Privacy Policy',
        'color': Colors.amber,
        'points': <String>[
          'We reserve the right to modify this privacy policy to reflect new legal requirements or changes to our app.',
          'The current version of the privacy policy will always be available in the app and on our website.',
        ],
        'subPoints': <String>[],
      },
      {
        'icon': Icons.mail_outline,
        'title': 'Contact',
        'color': Colors.teal,
        'points': <String>[
          'If you have any questions regarding this privacy policy, feel free to contact us at info@bitcoinsilver.top.',
        ],
        'subPoints': <String>[],
      },
    ];

    return sections.asMap().entries.map((entry) {
      final index = entry.key;
      final section = entry.value;

      // Safely cast the lists
      final points = List<String>.from(section['points'] as List);
      final subPoints = List<String>.from(section['subPoints'] as List);

      return _buildSection(
        index + 1,
        section['icon'] as IconData,
        section['title'] as String,
        section['color'] as Color,
        points,
        subPoints,
      );
    }).toList();
  }

  Widget _buildSection(
      int number,
      IconData icon,
      String title,
      Color color,
      List<String> points,
      List<String> subPoints,
      ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withValues(alpha: 0.3), color.withValues(alpha: 0.1)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    '$number',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...points.map((point) => _buildModernBulletPoint(point, color)),
          if (subPoints.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.only(left: 20),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                    color: color.withValues(alpha: 0.5),
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                children: subPoints
                    .map((subPoint) => _buildSubPoint(subPoint, color))
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModernBulletPoint(String text, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.grey.shade300,
                fontSize: 15,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubPoint(String text, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.chevron_right,
            color: accentColor.withValues(alpha: 0.6),
            size: 16,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.05),
            Colors.white.withValues(alpha: 0.02),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.verified_user, color: Colors.blue.shade400, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Bitcoin Silver Team',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.email, size: 16, color: Colors.blue.shade300),
                const SizedBox(width: 8),
                Text(
                  'info@bitcoinsilver.top',
                  style: TextStyle(
                    color: Colors.blue.shade300,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your privacy is our priority',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}