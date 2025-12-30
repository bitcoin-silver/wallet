import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import 'package:bitcoinsilver_wallet/providers/blockchain_provider.dart';
import 'package:bitcoinsilver_wallet/providers/wallet_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:bitcoinsilver_wallet/widgets/app_background.dart';

class ExchangeView extends StatefulWidget {
  const ExchangeView({super.key});

  @override
  State<ExchangeView> createState() => _ExchangeViewState();
}

class _ExchangeViewState extends State<ExchangeView> with TickerProviderStateMixin {
  double? _moneySupply;
  bool _isLoadingSupply = false;

  // Volume data for exchanges
  String? _exbitronVolume;
  String? _nestexVolume;
  String? _qutradeVolume;
  String? _klingexVolume;
  String? _bitstorageVolume;

  // Animation controllers
  late AnimationController _logoAnimationController;
  late AnimationController _shimmerController;
  late Animation<double> _logoScaleAnimation;
  late Animation<double> _logoRotateAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _logoAnimationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    _shimmerController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _logoScaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _logoAnimationController,
      curve: Curves.elasticOut,
    ));

    _logoRotateAnimation = Tween<double>(
      begin: -0.1,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _logoAnimationController,
      curve: Curves.easeInOut,
    ));

    _logoAnimationController.forward();

    // Fetch price, money supply and volumes on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final blockchainProvider = Provider.of<BlockchainProvider>(context, listen: false);
      blockchainProvider.fetchPrice();
      _fetchMoneySupply();
      _fetchAllVolumes();
    });
  }

  @override
  void dispose() {
    _logoAnimationController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _fetchAllVolumes() async {
    _fetchExbitronVolume();
    _fetchQutradeVolume();
    _fetchNestexVolume();
    _fetchKlingexVolume();
    _fetchBitstorageVolume();
  }

  Future<void> _fetchMoneySupply() async {
    if (_isLoadingSupply) return;

    setState(() {
      _isLoadingSupply = true;
    });

    try {
      final response = await http.get(
        Uri.parse('https://explorer.bitcoinsilver.top/ext/getmoneysupply'),
        headers: {'Accept': 'application/json'},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      if (response.statusCode == 200) {
        final responseBody = response.body.trim();
        final supply = double.tryParse(responseBody);
        if (supply != null) {
          setState(() {
            _moneySupply = supply;
          });
        } else {
          try {
            final data = jsonDecode(responseBody);
            if (data is num) {
              setState(() {
                _moneySupply = data.toDouble();
              });
            } else if (data is Map && data.containsKey('moneysupply')) {
              setState(() {
                _moneySupply = double.tryParse(data['moneysupply'].toString());
              });
            }
          } catch (e) {
            debugPrint('Error parsing money supply JSON: $e');
          }
        }
      } else {
        debugPrint('Money supply fetch failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching money supply: $e');
      setState(() {
        _moneySupply = 100000000; // 100M fallback
      });
    } finally {
      setState(() {
        _isLoadingSupply = false;
      });
    }
  }

  Future<void> _fetchExbitronVolume() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.exbitron.com/api/v1/trading/info/BTCS-USDT'),
        headers: {'Accept': 'application/json'},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      if (response.statusCode == 200) {
        // Check if response body is empty or invalid before parsing
        if (response.body.trim().isEmpty) {
          setState(() {
            _exbitronVolume = 'Trade Now';
          });
          return;
        }

        try {
          final data = jsonDecode(response.body);
          if (data['status'] == 'OK' && data['data'] != null) {
            // Convert to string first, then parse as double for consistency
            final volume24h = double.tryParse(
                data['data']['market']['marketDynamics']['volume24h'].toString()
            ) ?? 0.0;

            setState(() {
              if (volume24h > 0) {
                _exbitronVolume = '\$${volume24h.toStringAsFixed(2)}';
              } else {
                _exbitronVolume = 'Low Volume';
              }
            });
          } else {
            setState(() {
              _exbitronVolume = 'Trade Now';
            });
          }
        } on FormatException {
          // Silent handling when JSON is invalid (exchange is down)
          setState(() {
            _exbitronVolume = 'Trade Now';
          });
        }
      } else {
        setState(() {
          _exbitronVolume = 'Trade Now';
        });
      }
    } catch (e) {
      // Silent handling - exchange may be temporarily down
      if (mounted) {
        setState(() {
          _exbitronVolume = 'Trade Now';
        });
      }
    }
  }

  Future<void> _fetchQutradeVolume() async {
    try {
      final response = await http.get(
        Uri.parse('https://qutrade.io/api/v1/market_data/?pair=btcs_usdt'),
        headers: {'Accept': 'application/json'},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] == 'success' && data['list'] != null) {
          final btcsData = data['list']['btcs_usdt'];
          if (btcsData != null) {
            // Convert to string first, then parse as double
            final usdtVolume = double.tryParse(btcsData['asset_2_volume'].toString()) ?? 0.0;

            setState(() {
              if (usdtVolume > 0) {
                _qutradeVolume = '\$${usdtVolume.toStringAsFixed(2)}';
              } else {
                _qutradeVolume = 'Low Volume';
              }
            });
          }
        }
      } else {
        setState(() {
          _qutradeVolume = 'Data unavailable';
        });
      }
    } catch (e) {
      debugPrint('Error fetching Qutrade volume: $e');
      setState(() {
        _qutradeVolume = 'Trade Now';
      });
    }
  }

  Future<void> _fetchNestexVolume() async {
    try {
      final response = await http.get(
        Uri.parse('https://trade.nestex.one/api/cg/tickers/BTCS_USDT'),
        headers: {'Accept': 'application/json'},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['ticker_id'] == 'BTCS_USDT') {
          // Convert to string first, then parse as double
          final usdtVolume = double.tryParse(data['target_volume'].toString()) ?? 0.0;

          setState(() {
            if (usdtVolume > 0) {
              _nestexVolume = '\$${usdtVolume.toStringAsFixed(2)}';
            } else {
              _nestexVolume = 'Low Volume';
            }
          });
        }
      } else {
        setState(() {
          _nestexVolume = 'Data unavailable';
        });
      }
    } catch (e) {
      debugPrint('Error fetching Nestex volume: $e');
      setState(() {
        _nestexVolume = 'Trade Now';
      });
    }
  }

  Future<void> _fetchKlingexVolume() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.klingex.io/api/tickers'),
        headers: {'Accept': 'application/json'},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> tickers = jsonDecode(response.body);

        // Find the BTCS_USDT pair in the list
        final btcsTicker = tickers.firstWhere(
              (ticker) => ticker['ticker_id'] == 'BTCS_USDT',
          orElse: () => null,
        );

        if (btcsTicker != null) {
          // target_volume is USDT volume
          final usdtVolume = double.tryParse(btcsTicker['target_volume'].toString()) ?? 0.0;

          setState(() {
            // Show volume or indicate no trading if volume is 0
            if (usdtVolume > 0) {
              _klingexVolume = '\$${usdtVolume.toStringAsFixed(2)}';
            } else {
              _klingexVolume = 'Low Volume';
            }
          });
        } else {
          setState(() {
            _klingexVolume = 'Data unavailable';
          });
        }
      } else {
        setState(() {
          _klingexVolume = 'Data unavailable';
        });
      }
    } catch (e) {
      debugPrint('Error fetching KlingEx volume: $e');
      setState(() {
        _klingexVolume = 'Trade Now';
      });
    }
  }

  Future<void> _fetchBitstorageVolume() async {
    try {
      final response = await http.get(
        Uri.parse('https://api.bitstorage.finance/v1/public/ticker?pair=BTCSUSDT'),
        headers: {'Accept': 'application/json'},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timeout');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == true && data['data'] != null) {
          // Get the last price and 24h volume
          final lastPrice = double.tryParse(data['data']['last'].toString()) ?? 0.0;
          final volume24h = double.tryParse(data['data']['volume_24H'].toString()) ?? 0.0;

          // Calculate volume in USD (volume * last price)
          final usdtVolume = volume24h * lastPrice;

          setState(() {
            if (usdtVolume > 0) {
              _bitstorageVolume = '\$${usdtVolume.toStringAsFixed(2)}';
            } else {
              _bitstorageVolume = 'Low Volume';
            }
          });
        } else {
          setState(() {
            _bitstorageVolume = 'Data unavailable';
          });
        }
      } else {
        setState(() {
          _bitstorageVolume = 'Data unavailable';
        });
      }
    } catch (e) {
      debugPrint('Error fetching Bitstorage volume: $e');
      setState(() {
        _bitstorageVolume = 'Trade Now';
      });
    }
  }

  String _formatPrice(double price) {
    if (price < 0.01) {
      return '\$${price.toStringAsFixed(6)}';
    } else if (price < 1) {
      return '\$${price.toStringAsFixed(4)}';
    } else {
      return '\$${price.toStringAsFixed(2)}';
    }
  }

  String _formatMarketCap(double price, double? supply) {
    if (supply == null || price == 0) return '---';

    final marketCap = price * supply;
    if (marketCap >= 1000000000) {
      return '\$${(marketCap / 1000000000).toStringAsFixed(2)}B';
    } else if (marketCap >= 1000000) {
      return '\$${(marketCap / 1000000).toStringAsFixed(2)}M';
    } else if (marketCap >= 1000) {
      return '\$${(marketCap / 1000).toStringAsFixed(2)}K';
    } else {
      return '\$${marketCap.toStringAsFixed(2)}';
    }
  }

  String _formatSupply(double? supply) {
    if (supply == null) return '---';

    if (supply >= 1000000000) {
      return '${(supply / 1000000000).toStringAsFixed(2)}B';
    } else if (supply >= 1000000) {
      return '${(supply / 1000000).toStringAsFixed(2)}M';
    } else if (supply >= 1000) {
      return '${(supply / 1000).toStringAsFixed(2)}K';
    } else {
      return supply.toStringAsFixed(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blockchainProvider = Provider.of<BlockchainProvider>(context);
    final walletProvider = Provider.of<WalletProvider>(context);

    final double btcsPrice = blockchainProvider.price;
    final double? balance = walletProvider.balance;
    final String balanceInUSD = balance != null && btcsPrice > 0
        ? '\$${(balance * btcsPrice).toStringAsFixed(2)}'
        : '---';

    return Scaffold(
      body: AppBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),

                  // Enhanced Logo Section
                  Center(
                    child: AnimatedBuilder(
                      animation: _logoAnimationController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _logoScaleAnimation.value,
                          child: Transform.rotate(
                            angle: _logoRotateAnimation.value,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Glowing background effect
                                Container(
                                  width: 160,
                                  height: 160,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        Colors.cyanAccent.withValues(alpha: 0.3),
                                        Colors.cyanAccent.withValues(alpha: 0.1),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.3, 0.6, 1.0],
                                    ),
                                  ),
                                ),

                                // Rotating ring
                                AnimatedBuilder(
                                  animation: _shimmerController,
                                  builder: (context, child) {
                                    return Transform.rotate(
                                      angle: _shimmerController.value * 2 * 3.14159,
                                      child: Container(
                                        width: 140,
                                        height: 140,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: SweepGradient(
                                            colors: [
                                              Colors.transparent,
                                              Colors.cyanAccent.withValues(alpha: 0.2),
                                              Colors.cyanAccent.withValues(alpha: 0.4),
                                              Colors.transparent,
                                            ],
                                            stops: const [0.0, 0.25, 0.5, 1.0],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),

                                // Main logo container
                                Container(
                                  padding: const EdgeInsets.all(25),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.black.withValues(alpha: 0.8),
                                        Colors.black.withValues(alpha: 0.6),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    border: Border.all(
                                      color: Colors.cyanAccent.withValues(alpha: 0.5),
                                      width: 3,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.cyanAccent.withValues(alpha: 0.5),
                                        blurRadius: 20,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Image.asset(
                                    'assets/logo.png',
                                    height: 80,
                                    width: 80,
                                    errorBuilder: (context, error, stackTrace) {
                                      return const Icon(
                                        Icons.currency_bitcoin,
                                        size: 80,
                                        color: Colors.cyanAccent,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  const SizedBox(height: 25),

                  // Title and Subtitle
                  SilverBorder(
                    borderWidth: 3,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: ShaderMask(
                        shaderCallback: (bounds) => const LinearGradient(
                          colors: [Colors.cyanAccent, Colors.white],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ).createShader(bounds),
                        child: const Text(
                          'BTCS EXCHANGES',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Trade Bitcoin Silver on Premium Exchanges',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 15,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 30),

                  // Live Price Ticker
                  SilverCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildPriceInfo(
                              'BTCS Price',
                              btcsPrice > 0 ? _formatPrice(btcsPrice) : '---',
                              isLoading: blockchainProvider.isLoading && btcsPrice == 0,
                            ),
                            Container(
                              height: 40,
                              width: 1,
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            _buildPriceInfo(
                              'Your Balance',
                              balance != null
                                  ? '${balance.toStringAsFixed(4)} BTCS'
                                  : '---',
                            ),
                            Container(
                              height: 40,
                              width: 1,
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                            _buildPriceInfo(
                              'USD Value',
                              balanceInUSD,
                              isPositive: btcsPrice > 0,
                            ),
                          ],
                        ),
                        if (btcsPrice > 0 || _moneySupply != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Market Cap: ${_formatMarketCap(btcsPrice, _moneySupply)}',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Supply: ${_formatSupply(_moneySupply)} BTCS',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Markets Header
                  SilverCard(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.show_chart,
                          color: Colors.cyanAccent,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Available Markets',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () {
                            blockchainProvider.fetchPrice();
                            _fetchMoneySupply();
                            _fetchAllVolumes();
                          },
                          icon: Icon(
                            Icons.refresh,
                            color: blockchainProvider.isLoading || _isLoadingSupply
                                ? Colors.white38
                                : Colors.white70,
                            size: 20,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Exchange Cards - Reordered as requested
                  _buildExchangeCard(
                    context,
                    name: 'EXBITRON',
                    url: 'https://app.exbitron.com/exchange/?market=BTCS-USDT',
                    pair: 'BTCS/USDT',
                    volume: _exbitronVolume != null
                        ? '24h Volume: $_exbitronVolume'
                        : 'Loading volume...',
                    icon: Icons.currency_exchange,
                    isPrimary: true,
                  ),

                  _buildExchangeCard(
                    context,
                    name: 'NESTEX',
                    url: 'https://trade.nestex.one/spot/BTCS_USDT',
                    pair: 'BTCS/USDT',
                    volume: _nestexVolume != null
                        ? '24h Volume: $_nestexVolume'
                        : 'Trade Now',
                    icon: Icons.account_balance,
                  ),

                  _buildExchangeCard(
                    context,
                    name: 'QUTRADE',
                    url: 'https://qutrade.io/en/?market=btcs_usdt',
                    pair: 'BTCS/USDT',
                    volume: _qutradeVolume != null
                        ? '24h Volume: $_qutradeVolume'
                        : 'Trade Now',
                    icon: Icons.trending_up,
                    isNew: true,
                  ),

                  _buildExchangeCard(
                    context,
                    name: 'KlingEx',
                    url: 'https://klingex.io/trade/BTCS-USDT',
                    pair: 'BTCS/USDT',
                    volume: _klingexVolume != null
                        ? '24h Volume: $_klingexVolume'
                        : 'Professional Trading',
                    icon: Icons.auto_graph,
                    isNew: true,
                  ),

                  _buildExchangeCard(
                    context,
                    name: 'BITSTORAGE',
                    url: 'https://bitstorage.finance/spot/trading/BTCSUSDT?interface=classic',
                    pair: 'BTCS/USDT',
                    volume: _bitstorageVolume != null
                        ? '24h Volume: $_bitstorageVolume'
                        : 'Trade Now',
                    icon: Icons.storage,
                  ),

                  const SizedBox(height: 30),

                  // Info Section
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.blue,
                          size: 32,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Trading Information',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Bitcoin Silver (BTCS) is listed on multiple exchanges. Click on any exchange above to start trading. Always ensure you\'re using the official exchange links.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 14,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
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
      ),
    );
  }

  Widget _buildExchangeCard(
      BuildContext context, {
        required String name,
        required String url,
        required String pair,
        required String volume,
        required IconData icon,
        bool isNew = false,
        bool isPrimary = false,
      }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => launchUrl(Uri.parse(url)),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: isPrimary
                  ? LinearGradient(
                colors: [
                  Colors.cyanAccent.withValues(alpha: 0.1),
                  Colors.transparent,
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              )
                  : null,
              color: !isPrimary ? Colors.white.withValues(alpha: 0.05) : null,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isPrimary
                    ? Colors.cyanAccent.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.1),
                width: isPrimary ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // Icon Container
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.cyanAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),

                // Exchange Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: isPrimary ? FontWeight.w900 : FontWeight.bold,
                            ),
                          ),
                          if (isNew) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'NEW',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        volume,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Pair and Arrow
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      pair,
                      style: const TextStyle(
                        color: Colors.cyanAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white.withValues(alpha: 0.4),
                      size: 16,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPriceInfo(
      String label,
      String value, {
        bool isPositive = false,
        bool isLoading = false,
      }) {
    Color valueColor = Colors.white;
    if (isPositive && value != '---') valueColor = Colors.cyanAccent;

    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        if (isLoading)
          const SizedBox(
            width: 50,
            height: 14,
            child: LinearProgressIndicator(
              color: Colors.cyanAccent,
              backgroundColor: Colors.white24,
            ),
          )
        else
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }
}