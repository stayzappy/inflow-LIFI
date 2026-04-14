import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:js_interop';
import 'dart:js_util' as js_util;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pinput/pinput.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

// ==============================================================
// 1. JS INTEROP (inFlow EVM Bridge)
// ==============================================================
@JS('window.ZapBridge')
external ZapBridge get zapBridge;

@JS('window.location.reload')
external void reloadWindow();

@JS()
extension type ZapBridge._(JSObject _) implements JSObject {
  external JSPromise initBridge();
  external JSPromise sendEmailOtp(JSString email);
  external JSPromise verifyEmailOtpAndConnect(JSString otp, JSString network);
  external JSPromise logout();
  external JSPromise storeStreamSecret(
    JSNumber streamId,
    JSString secretKey,
    JSString recipientEmail,
    JSString network,
  );

  external JSPromise createYieldStream(
    JSString tokenSymbol,
    JSString amountStr,
    JSNumber durationSecs,
    JSString vaultTokenAddress,
  );
  external JSPromise claimSecureStream(JSNumber streamId);
  external JSPromise withdrawAndRedeemYield(
    JSNumber streamId,
    JSString amountBaseStr,
    JSString vaultTokenAddress,
  );

  external JSPromise cancelStream(JSNumber streamId);
  external JSPromise executeNativeSwap(
    JSString tokenInSymbol,
    JSString tokenOutSymbol,
    JSString amountInStr,
  );
  external JSPromise transferToken(
    JSString tokenSymbol,
    JSString recipientAddress,
    JSString amountStr,
  );
  external JSPromise getBalance(JSString tokenSymbol);
  external JSPromise getNextStreamId();
  external JSPromise getStream(JSNumber streamId);
  external JSPromise waitForTransaction(JSString txHash);
  external JSPromise checkAndTriggerSponsorship(JSString address, JSString network);
}

// ==============================================================
// 2. CONFIGURATION, THEME & DATA MODELS
// ==============================================================
class AppTheme {
  static const Color amber = Color(0xFFF59E0B);
  static const Color green = Color(0xFF00C97A);
  static const Color red = Color(0xFFEF4444);
  static const Color indigo = Color(0xFF818CF8);
  static const Color lifi = Color(0xFF6366F1);
  static const Color bgDark = Color(0xFF07070B);
  static const Color cardBg = Color(0xFF131320);
  static const Color textMuted = Color(0xFF5A6478);
  static const Color muted = Color(0xFF5A6478);
  static const Color dim = Color(0xFF9DA3AE);
  static const Color text = Color(0xFFF0F0F8);
  static const Color border = Color(0xFF1E1E2E);
}

class ZapStreamConfig {
  static const String USDC_ADDRESS = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
  static const String MORPHO_VAULT = "0x7BfA7C4f149E7415b73bdeDfe609237e29CBF34A";

  static String getVoyagerUrl(String txHash, bool isMainnet) {
    String base = isMainnet ? "https://basescan.org/tx/" : "https://sepolia.basescan.org/tx/";
    return "$base$txHash";
  }

  static final Map<String, Map<String, dynamic>> tokens = {
    "ETH": {
      "mainnet": "0x0000000000000000000000000000000000000000",
      "sepolia": "0x0000000000000000000000000000000000000000",
      "decimals": 18,
    },
    "USDC": {
      "mainnet": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
      "sepolia": "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
      "decimals": 6,
    },
  };

  static String normalizeAddress(String address) {
    if (address.isEmpty || address == "0") return "0x0";
    return address.toLowerCase();
  }

  static BigInt decodeU256(String valueStr) {
    return BigInt.tryParse(valueStr) ?? BigInt.zero;
  }
}

class StreamData {
  final int id;
  final String sender;
  final String recipient;
  final String asset;
  final BigInt deposit;
  final BigInt withdrawnAmount;
  final BigInt remainingBalance;
  final int startTime;
  final int stopTime;
  final String claimHash;
  final String? intendedEmail;
  final String? senderEmail;

  StreamData({
    required this.id,
    required this.sender,
    required this.recipient,
    required this.asset,
    required this.deposit,
    required this.withdrawnAmount,
    required this.remainingBalance,
    required this.startTime,
    required this.stopTime,
    required this.claimHash,
    this.intendedEmail,
    this.senderEmail,
  });
}

enum TxPhase { none, processing, success, error }

// ==============================================================
// 3. UI UTILITIES & KEYBOARD SCROLLER
// ==============================================================
class BannerUtils {
  static void showBanner(String message, {BuildContext? context, bool isError = true, int durationSecs = 3}) {
    if (context == null || !context.mounted) return;
    try {
      print("🔔 [BANNER] Showing banner: $message (isError: $isError)");
      final overlay = Overlay.of(context);
      late OverlayEntry overlayEntry;
      overlayEntry = OverlayEntry(
        builder: (context) => FloatingBanner(
          message: message,
          isError: isError,
          duration: Duration(seconds: durationSecs),
          onDismissed: () => overlayEntry.remove(),
        ),
      );
      overlay.insert(overlayEntry);
    } catch (e) {
      print('❌ [BANNER ERROR] Failed to show banner: $e');
    }
  }
}

class FloatingBanner extends StatefulWidget {
  final String message;
  final bool isError;
  final Duration duration;
  final VoidCallback? onDismissed;

  const FloatingBanner({
    Key? key,
    required this.message,
    this.isError = true,
    this.duration = const Duration(seconds: 3),
    this.onDismissed,
  }) : super(key: key);

  @override
  State<FloatingBanner> createState() => _FloatingBannerState();
}

class _FloatingBannerState extends State<FloatingBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      reverseDuration: const Duration(milliseconds: 250),
    );
    _offsetAnimation = Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _controller.forward();
    Future.delayed(widget.duration, () {
      if (mounted) {
        _controller.reverse().then((_) {
          if (widget.onDismissed != null) widget.onDismissed!();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isError ? const Color(0xFFEF4444) : const Color(0xFF10B981);
    final icon = widget.isError ? CupertinoIcons.exclamationmark_circle_fill : CupertinoIcons.checkmark_circle_fill;
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: SlideTransition(
          position: _offsetAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: color.withOpacity(0.18), blurRadius: 16, offset: const Offset(0, 4))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white, size: 22),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        widget.message,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class KeyboardScrollWrapper extends StatefulWidget {
  final Widget child;
  final ScrollController controller;
  const KeyboardScrollWrapper({super.key, required this.child, required this.controller});
  @override
  State<KeyboardScrollWrapper> createState() => _KeyboardScrollWrapperState();
}

class _KeyboardScrollWrapperState extends State<KeyboardScrollWrapper> {
  final FocusNode _focusNode = FocusNode();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        if (FocusManager.instance.primaryFocus?.context?.widget is! EditableText)
          _focusNode.requestFocus();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          if (FocusManager.instance.primaryFocus?.context?.widget is! EditableText)
            _focusNode.requestFocus();
        },
        child: Focus(
          focusNode: _focusNode,
          autofocus: true,
          canRequestFocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent || event is KeyRepeatEvent) {
              if (FocusManager.instance.primaryFocus?.context?.widget is EditableText)
                return KeyEventResult.ignored;
              const double scrollAmount = 150.0;
              const double pageScrollAmount = 400.0;
              double target = widget.controller.offset;
              if (event.logicalKey == LogicalKeyboardKey.arrowDown)
                target += scrollAmount;
              else if (event.logicalKey == LogicalKeyboardKey.arrowUp)
                target -= scrollAmount;
              else if (event.logicalKey == LogicalKeyboardKey.pageDown || event.logicalKey == LogicalKeyboardKey.space)
                target += pageScrollAmount;
              else if (event.logicalKey == LogicalKeyboardKey.pageUp)
                target -= pageScrollAmount;
              if (target != widget.controller.offset) {
                target = target.clamp(0.0, widget.controller.position.maxScrollExtent);
                widget.controller.animateTo(target, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: widget.child,
        ),
      ),
    );
  }
}

// ==============================================================
// 4. ROOT APPLICATION
// ==============================================================
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  print("🚀 [BOOT] Application started. Logging enabled.");

  runApp(const ZapStreamApp());
}

class ZapStreamApp extends StatelessWidget {
  const ZapStreamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: MaterialApp(
        title: 'inFlow Finance',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppTheme.bgDark,
          textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.amber,
            secondary: AppTheme.green,
            surface: AppTheme.cardBg,
          ),
          useMaterial3: true,
        ),
        initialRoute: '/',
        onGenerateRoute: (settings) {
          if (settings.name == '/how-it-works') {
            return PageRouteBuilder(
              pageBuilder: (_, __, ___) => const StoryScreen(),
              transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
              settings: settings,
            );
          }
          return MaterialPageRoute(
            builder: (context) => const LandingScreen(),
            settings: settings,
          );
        },
      ),
    );
  }
}

// ==============================================================
// 5. LANDING SCREEN
// ==============================================================
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});
  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  bool _isBridgeReady = false;
  bool _isProcessing = false;
  bool _isAuthenticating = false;
  bool _hasOtpError = false;
  bool _otpSent = false;
  bool _isMainnet = true;
  bool _isLinkClaimed = false;

  String? _targetStreamId;
  String? _intendedEmailForStream;

  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _otpCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    print("🚀 [LandingScreen] initState called");
    _checkDeepLink();
    Future.delayed(const Duration(milliseconds: 500), () {
      _initEngine();
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkDeepLink() async {
    print("🔍 [DeepLink] Checking URL parameters...");
    try {
      final uri = Uri.base;
      if (uri.queryParameters.containsKey('stream') || uri.queryParameters.containsKey('id')) {
        setState(() {
          _targetStreamId = uri.queryParameters['stream'] ?? uri.queryParameters['id'];
        });
        print("🔗 [DeepLink] Found stream ID: $_targetStreamId");

        try {
          print("📡 [DeepLink] Fetching stream info from Cloudflare...");
          final res = await http.get(Uri.parse('https://inflow-relay.zapstream.workers.dev/stream-info?id=$_targetStreamId'));
          print("📡 [DeepLink] Response status: ${res.statusCode}");
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            print("📡 [DeepLink] Data received: $data");
            if (data.containsKey('network')) {
              setState(() {
                _isMainnet = data['network'] == "mainnet" || data['network'] == "base-mainnet";
              });
            }
            if (data['isClaimed'] == true) {
              setState(() => _isLinkClaimed = true);
            } else if (data['recipientEmail'] != null) {
              setState(() => _intendedEmailForStream = data['recipientEmail'].toString().toLowerCase());
            }
          }
        } catch (e) {
          print("❌ [DeepLink Error] Failed to fetch intended email: $e");
        }
      } else {
        print("🔗 [DeepLink] No stream parameters found.");
      }
    } catch (e) {
      print("❌ [DeepLink Error] URL parsing failed: $e");
    }
  }

  Future<void> _initEngine() async {
    print("⚙️ [LandingScreen] _initEngine started...");
    try {
      bool hasBridge = js_util.hasProperty(js_util.globalThis, 'ZapBridge');
      print("🔍 [INTEROP] Is window.ZapBridge defined? $hasBridge");

      if (!hasBridge) {
        print("❌ [CRITICAL] zapbridge.js failed to load!");
        if (mounted) {
          BannerUtils.showBanner("System UI Error: Bridge missing. Clear cache and reload.", context: context, isError: true);
        }
        return;
      }

      print("🌐 [INTEROP] Calling zapBridge.initBridge()...");
      await zapBridge.initBridge().toDart;
      print("✅ [INTEROP] zapBridge.initBridge() success!");

      if (mounted) {
        setState(() => _isBridgeReady = true);
        print("🔄 [LandingScreen] UI unblocked. _isBridgeReady = true");
      }
    } catch (e, stack) {
      print("❌ [INTEROP ERROR] Bridge init failed: $e");
      print("❌ [STACKTRACE] $stack");
      if (mounted) BannerUtils.showBanner("Failed to initialize Web3. Please reload.", context: context, isError: true);
    }
  }

  Future<void> _sendOtp() async {
    print("✉️ [Auth] Requesting OTP...");
    HapticFeedback.lightImpact();
    final inputEmail = _emailCtrl.text.trim().toLowerCase();
    if (inputEmail.isEmpty) return;

    if (_targetStreamId != null && _intendedEmailForStream != null) {
      if (inputEmail != _intendedEmailForStream) {
        print("❌ [Auth] Email mismatch.");
        BannerUtils.showBanner("This email is not authorized to claim this stream.", context: context, isError: true);
        return;
      }
    }

    setState(() => _isProcessing = true);
    try {
      print("🌐 [INTEROP] Calling zapBridge.sendEmailOtp()...");
      await zapBridge.sendEmailOtp(inputEmail.toJS).toDart;
      print("✅ [Auth] OTP Sent successfully to $inputEmail");
      setState(() => _otpSent = true);
    } catch (e) {
      print("❌ [Auth Error] Failed to send OTP: $e");
      BannerUtils.showBanner("Failed to send code.", context: context, isError: true);
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _verifyOtpAndConnect(String pin) async {
    print("🔐 [Auth] Verifying OTP...");
    HapticFeedback.lightImpact();
    setState(() {
      _hasOtpError = false;
      _isAuthenticating = true;
    });

    try {
      final networkStr = _isMainnet ? "mainnet" : "sepolia";
      print("🌐 [INTEROP] Calling zapBridge.verifyEmailOtpAndConnect() on $networkStr...");

      final addressJs = await zapBridge.verifyEmailOtpAndConnect(pin.trim().toJS, networkStr.toJS).toDart;
      final connectedAddress = (addressJs as JSString).toDart;
      final userEmail = _emailCtrl.text.trim().toLowerCase();

      print("✅ [Auth] Successfully connected wallet! Address: $connectedAddress");

      await Future.delayed(const Duration(milliseconds: 800));

      if (_targetStreamId != null && !_isLinkClaimed) {
        try {
          print("🌐 [INTEROP] Attempting auto-claim for stream $_targetStreamId...");
          await zapBridge.claimSecureStream(int.parse(_targetStreamId!).toJS).toDart;
          print("✅ [Auth] Auto-claim successful!");
        } catch (claimErr) {
          print("❌ [Auth Error] Auto-claim failed: $claimErr");
        }
      }

      if (!mounted) return;
      HapticFeedback.heavyImpact();

      print("🚀 [Navigation] Pushing DashboardScreen...");
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => DashboardScreen(
            connectedAddress: connectedAddress,
            loggedInEmail: userEmail,
            isMainnet: _isMainnet,
            initialTabIndex: _targetStreamId != null && !_isLinkClaimed ? 2 : 0,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
      );
    } catch (e) {
      print("❌ [Auth Error] OTP verification failed: $e");
      HapticFeedback.vibrate();
      setState(() {
        _hasOtpError = true;
        _isAuthenticating = false;
        _otpCtrl.clear();
      });
      BannerUtils.showBanner("Invalid secure code. Please try again.", context: context, isError: true);
    }
  }

  Widget _buildNetworkToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF13131C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1E2E)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggleItem("Base Mainnet", _isMainnet, () {
            HapticFeedback.lightImpact();
            setState(() => _isMainnet = true);
          }),
          _toggleItem("Base Sepolia", !_isMainnet, () {
            HapticFeedback.lightImpact();
            setState(() => _isMainnet = false);
          }),
        ],
      ),
    );
  }

  Widget _toggleItem(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppTheme.amber : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: active ? Colors.black : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isAuthenticating) {
      return Scaffold(
        backgroundColor: AppTheme.bgDark,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1600),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF3A2800)),
                ),
                child: const Center(child: Text("⚡", style: TextStyle(fontSize: 34))),
              ).animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(end: 1.1, duration: 800.ms),
              const SizedBox(height: 32),
              const Text("Signing you in securely...", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)).animate().fadeIn(duration: 400.ms),
              const SizedBox(height: 16),
              const CircularProgressIndicator(color: AppTheme.amber),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: KeyboardScrollWrapper(
        controller: _scrollController,
        child: Center(
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Container(
              width: 400,
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
              child: _isLinkClaimed
                  ? _buildClaimedUI()
                  : (_targetStreamId != null ? _buildBeingPaidUI() : _buildSignInUI()),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClaimedUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(CupertinoIcons.lock_shield_fill, size: 64, color: AppTheme.amber),
        const SizedBox(height: 24),
        const Text("Link Claimed", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(height: 12),
        const Text("This payment link has already been used and is no longer valid.", textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted, fontSize: 14, height: 1.5)),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              setState(() {
                _targetStreamId = null;
                _isLinkClaimed = false;
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text("Go to Dashboard", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    ).animate().fadeIn();
  }

  Widget _buildSignInUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildNetworkToggle(),
        const SizedBox(height: 24),
        Container(
          width: 62, height: 62,
          decoration: BoxDecoration(color: const Color(0xFF1E1600), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF3A2800))),
          child: const Center(child: Text("⚡", style: TextStyle(fontSize: 26))),
        ).animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
        const SizedBox(height: 22),
        const Text("inFlow", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5, color: Colors.white)),
        const SizedBox(height: 9),
        const Text("Get paid the second you earn it.\nYour salary earns yield while it streams.", textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.65)),
        const SizedBox(height: 34),

        if (!_isBridgeReady)
          const CircularProgressIndicator(color: AppTheme.amber)
        else if (!_otpSent) ...[
          TextField(
            controller: _emailCtrl,
            style: const TextStyle(fontSize: 14, color: Colors.white),
            decoration: InputDecoration(
              hintText: "your@email.com",
              hintStyle: const TextStyle(color: AppTheme.textMuted),
              filled: true, fillColor: const Color(0xFF0F0F16),
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
            ),
          ).animate().fadeIn(),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _sendOtp,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amber, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _isProcessing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Text("Continue with Email", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
            ),
          ).animate().fadeIn(),
          const SizedBox(height: 14),
          const Text("No crypto knowledge required.", style: TextStyle(color: Color(0xFF3A4456), fontSize: 12)),

          // LI.FI Badge
          Container(
            margin: const EdgeInsets.only(top: 24),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: AppTheme.lifi.withOpacity(0.1), border: Border.all(color: AppTheme.lifi.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_graph, color: AppTheme.lifi, size: 16),
                const SizedBox(width: 8),
                const Text("Yield powered by LI.FI Earn", style: TextStyle(color: AppTheme.lifi, fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 24),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/how-it-works'),
            child: const Text("How inFlow works →", style: TextStyle(color: AppTheme.amber, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ),
        ] else ...[
          const Text("Check your inbox!\nWe sent a 6-digit code to", textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.5)).animate().fadeIn(),
          Text(_emailCtrl.text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, height: 1.5)).animate().fadeIn(),
          const SizedBox(height: 24),
          _buildPinput(),
          const SizedBox(height: 24),
          TextButton(
            onPressed: () => setState(() { _otpSent = false; _otpCtrl.clear(); }),
            child: const Text("← Back", style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ).animate().fadeIn(),
        ],
      ],
    );
  }

  Widget _buildBeingPaidUI() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: const Color(0xFF0D1812), border: Border.all(color: AppTheme.green.withOpacity(0.3)), borderRadius: BorderRadius.circular(18)),
          child: Column(
            children: [
              const Text("🎉", style: TextStyle(fontSize: 34)),
              const SizedBox(height: 12),
              const Text("Someone set up a\nsalary for you!", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white, height: 1.35)),
              const SizedBox(height: 8),
              const Text("Sign in to securely access your earnings.\nNo crypto knowledge needed — we handle everything.", textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.6)),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(color: const Color(0xFF081410), border: Border.all(color: const Color(0xFF0A2818)), borderRadius: BorderRadius.circular(10)),
                child: const Text("Income Stream · Initiated", style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppTheme.green)),
              ),
            ],
          ),
        ).animate().fadeIn().slideY(begin: 0.1),
        const SizedBox(height: 18),

        if (!_isBridgeReady)
          const CircularProgressIndicator(color: AppTheme.green)
        else if (!_otpSent) ...[
          TextField(
            controller: _emailCtrl,
            style: const TextStyle(fontSize: 14, color: Colors.white),
            decoration: InputDecoration(
              hintText: "your@email.com", hintStyle: const TextStyle(color: AppTheme.textMuted),
              filled: true, fillColor: const Color(0xFF0F0F16),
              contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
            ),
          ).animate().fadeIn(),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _sendOtp,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.green, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: _isProcessing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                  : const Text("Sign In & Start Earning →", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black)),
            ),
          ).animate().fadeIn(),
        ] else ...[
          const Text("Check your inbox!\nWe sent a 6-digit code to", textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.5)).animate().fadeIn(),
          Text(_emailCtrl.text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, height: 1.5)).animate().fadeIn(),
          const SizedBox(height: 24),
          _buildPinput(isGreen: true),
        ],
      ],
    );
  }

  Widget _buildPinput({bool isGreen = false}) {
    Color themeColor = isGreen ? AppTheme.green : AppTheme.amber;
    final defaultPinTheme = PinTheme(
      width: 50, height: 56,
      textStyle: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.w600),
      decoration: BoxDecoration(border: Border.all(color: const Color(0xFF1E1E2E)), borderRadius: BorderRadius.circular(12), color: const Color(0xFF0F0F16)),
    );
    return Column(
      children: [
        Pinput(
          length: 6, controller: _otpCtrl, autofocus: true, defaultPinTheme: defaultPinTheme,
          focusedPinTheme: defaultPinTheme.copyDecorationWith(border: Border.all(color: themeColor), boxShadow: [BoxShadow(color: themeColor.withOpacity(0.2), blurRadius: 8)]),
          submittedPinTheme: defaultPinTheme.copyDecorationWith(border: Border.all(color: _hasOtpError ? AppTheme.red : themeColor)),
          errorPinTheme: defaultPinTheme.copyDecorationWith(border: Border.all(color: AppTheme.red)),
          pinputAutovalidateMode: PinputAutovalidateMode.disabled, showCursor: true,
          onCompleted: (pin) => _verifyOtpAndConnect(pin),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ).animate().fadeIn().scale(),
      ],
    );
  }
}

// ==============================================================
// 6. DASHBOARD SCREEN
// ==============================================================
class DashboardScreen extends StatefulWidget {
  final String connectedAddress;
  final String loggedInEmail;
  final bool isMainnet;
  final int initialTabIndex;

  const DashboardScreen({
    super.key,
    required this.connectedAddress,
    required this.loggedInEmail,
    required this.isMainnet,
    this.initialTabIndex = 0,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late int _selectedIndex;
  String _selectedToken = "USDC";
  bool _isLoggingOut = false;
  final ScrollController _mainScrollController = ScrollController();
  TxPhase _txPhase = TxPhase.none;
  String _txStatusMessage = "";
  String? _txHash;
  int? _lastCreatedStreamId;
  

  String _lastAmount = "";
  String _lastDays = "";

  final _amountCtrl = TextEditingController();
  final _durationDaysCtrl = TextEditingController();
  final _recipientEmailCtrl = TextEditingController();

  bool _isLoadingStreams = false;
  List<StreamData> _myStreams = [];

  // LI.FI Earn Variables
  bool _isLoadingVaults = true;
  List<dynamic> _lifiVaults = [];
  double _bestUsdcApy = 0.0;
  double _pill1Apy = 0.0;
  double _pill2Apy = 0.0;
  String _bestVaultProtocol = "Morpho Blue";
  String _pill1Name = "MORPHO";
  String _pill2Name = "AAVE";
  String _selectedVaultAddress = ZapStreamConfig.USDC_ADDRESS;
  bool _yieldEnabled = true;

  final Map<String, double> _usdPrices = {"ETH": 0.00, "USDC": 1.00};
  String _usdcBalance = "0.00";
  String _ethBalance = "0.00";

  Timer? _liveHeartbeat;
  bool _hasCheckedSponsorship = false;
  bool _hasReceivedStealthDrop = false;
  Timer? _airdropChecker;

  @override
  void initState() {
    super.initState();
    print("🚀 [Dashboard] Initialized for: ${widget.connectedAddress}");
    _selectedIndex = widget.initialTabIndex;

    _fetchLivePrices();
    _fetchBalances();
    _fetchLifiVaults();

    // 🔥 DEDICATED AIRDROP CHECKER
    _airdropChecker = Timer.periodic(const Duration(seconds: 3), (timer) async {
       if (_hasReceivedStealthDrop) {
           timer.cancel();
           return;
       }
       try {
           final usdcJS = await zapBridge.getBalance("USDC".toJS).toDart;
           String val = _safeConvertJsString(usdcJS) ?? "0.00";
           
           // The moment we detect the 0.02, show the banner and kill the timer
           if (val == "0.02" || val == "0.01") { 
               _hasReceivedStealthDrop = true;
               timer.cancel();
               
               if (mounted) {
                   setState(() { _usdcBalance = val; });
                   BannerUtils.showBanner(
                       "Welcome! You've received a free USDC airdrop (with gas covered) to test inFlow.", 
                       context: context, 
                       isError: false,
                       durationSecs: 8
                   );
               }
           }
       } catch (e) {
           // ignore silently
       }
    });

    // Check for stealth drop immediately
    _checkForSponsorship();

    if (_selectedIndex == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchMyStreams();
      });
    }

    _liveHeartbeat = Timer.periodic(const Duration(seconds: 4), (_) {
      _fetchBalances(silentLog: true);
      if (_selectedIndex == 2 && _txPhase == TxPhase.none) {
        _fetchMyStreams(silent: true);
      }
    });

    Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchLivePrices();
    });
  }

  @override
  void dispose() {
    _liveHeartbeat?.cancel();
    _amountCtrl.dispose();
    _durationDaysCtrl.dispose();
    _recipientEmailCtrl.dispose();
    _mainScrollController.dispose();
    super.dispose();
  }

  Future<void> _checkForSponsorship() async {
      if (_hasCheckedSponsorship) return;
      try {
          String networkStr = widget.isMainnet ? "mainnet" : "sepolia";
          final resultJs = await zapBridge.checkAndTriggerSponsorship(widget.connectedAddress.toJS, networkStr.toJS).toDart;
          
          if (resultJs != null) {
              final resultStr = (resultJs as JSString).toDart;
              final result = jsonDecode(resultStr);
              if (result.success == true && mounted) {
                  _hasCheckedSponsorship = true;
                  BannerUtils.showBanner(
                      "Welcome! You've received a \$0.02 USDC airdrop (with gas covered) to test inFlow.", 
                      context: context, 
                      isError: false,
                      durationSecs: 6
                  );
                  _fetchBalances();
              }
          }
      } catch (e) {
          print("Silently ignored sponsorship check error.");
      }
  }

  Future<void> _fetchLifiVaults() async {
    print("📡 [API] Fetching Live LI.FI Vaults...");
    try {
      String apiChainId = "8453"; // Force Mainnet for UI

      final res = await http.get(Uri.parse('https://earn.li.fi/v1/earn/vaults?chainId=$apiChainId&asset=USDC&sortBy=apy'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['data'] != null && data['data'].isNotEmpty) {
          
          final validVaults = (data['data'] as List).where((v) => v['analytics']?['apy']?['total'] != null).toList();

          if (validVaults.isNotEmpty) {
            print("✅ [API] Found ${validVaults.length} Valid Vaults.");
            if (mounted) {
              setState(() {
                _lifiVaults = validVaults;
                _isLoadingVaults = false;

                final bestVault = _lifiVaults[0];
                var rawApy = bestVault['analytics']?['apy']?['total'];
                _bestUsdcApy = (rawApy is num ? rawApy.toDouble() : double.tryParse(rawApy?.toString() ?? '0') ?? 0.0);
                _bestVaultProtocol = bestVault['name'] ?? "Vault";

                _selectedVaultAddress = widget.isMainnet ? bestVault['address'] : ZapStreamConfig.MORPHO_VAULT;

                if (_lifiVaults.isNotEmpty) {
                  _pill1Name = (_lifiVaults[0]['name'] == 'USDC' ? 'LI.FI MAX' : _lifiVaults[0]['name']).toString().toUpperCase();
                  if (_pill1Name.length > 10) _pill1Name = _pill1Name.substring(0, 10);
                  var p1Apy = _lifiVaults[0]['analytics']?['apy']?['total'];
                  _pill1Apy = (p1Apy is num ? p1Apy.toDouble() : double.tryParse(p1Apy?.toString() ?? '0') ?? 0.0);
                }
                
                if (_lifiVaults.length > 1) {
                  _pill2Name = (_lifiVaults[1]['name'] == 'USDC' ? 'LI.FI ALT' : _lifiVaults[1]['name']).toString().toUpperCase();
                  if (_pill2Name.length > 10) _pill2Name = _pill2Name.substring(0, 10);
                  var p2Apy = _lifiVaults[1]['analytics']?['apy']?['total'];
                  _pill2Apy = (p2Apy is num ? p2Apy.toDouble() : double.tryParse(p2Apy?.toString() ?? '0') ?? 0.0);
                }
              });
            }
            return;
          }
        }
      }
    } catch (e) {
      print("❌ [API Error] LI.FI Vault fetch failed: $e");
    }

    print("⚠️ [API] Falling back to Mock Vault Data.");
    if (mounted) {
      setState(() {
        _isLoadingVaults = false;
        _bestUsdcApy = 6.2;
        _pill1Apy = 6.2;
        _pill2Apy = 4.8;
        _pill1Name = "MORPHO";
        _pill2Name = "AAVE";
        _bestVaultProtocol = "Morpho Blue";
        _selectedVaultAddress = ZapStreamConfig.MORPHO_VAULT;
        _lifiVaults = [
          {
            "name": "Morpho Blue",
            "address": ZapStreamConfig.MORPHO_VAULT,
            "asset": {"symbol": "USDC", "priceUsd": 1.0},
            "analytics": {"apy": {"total": 6.2}, "tvl": 48200000},
            "risk": {"rating": "Low"},
          },
          {
            "name": "Aave v3",
            "address": "0x...",
            "asset": {"symbol": "USDC", "priceUsd": 1.0},
            "analytics": {"apy": {"total": 4.8}, "tvl": 312000000},
            "risk": {"rating": "Low"},
          },
        ];
      });
    }
  }

  String? _safeConvertJsString(dynamic jsValue) {
    if (jsValue == null) return null;
    if (jsValue is JSString) return jsValue.toDart;
    return jsValue.toString();
  }

  double _getCurrentTokenBalance(String symbol) {
    if (symbol == "USDC") return double.tryParse(_usdcBalance) ?? 0.0;
    if (symbol == "ETH") return double.tryParse(_ethBalance) ?? 0.0;
    return 0.0;
  }

  String _shortAddress(String addr) {
    if (addr.isEmpty) return "0x0";
    return addr.length >= 8 ? addr.substring(0, 8) : addr;
  }

  Future<void> _fetchBalances({bool silentLog = false}) async {
    try {
      if (!silentLog) print("📡 [INTEROP] Fetching Balances...");
      final usdcJS = await zapBridge.getBalance("USDC".toJS).toDart;
      final ethJS = await zapBridge.getBalance("ETH".toJS).toDart;
      if (mounted) {
        setState(() {
          _usdcBalance = _safeConvertJsString(usdcJS) ?? "0.00";
          _ethBalance = _safeConvertJsString(ethJS) ?? "0.00";
        });
      }
    } catch (e) {
      if (!silentLog) print("❌ [INTEROP Error] Failed to fetch balances: $e");
    }
  }

  Future<void> _fetchLivePrices() async {
    try {
      // 1. Try Binance First (Primary)
      final binanceRes = await http
          .get(Uri.parse('https://api.binance.com/api/v3/ticker/price?symbol=ETHUSDT'))
          .timeout(const Duration(seconds: 4));

      if (binanceRes.statusCode == 200) {
        final data = json.decode(binanceRes.body);
        if (mounted) {
          setState(() {
            _usdPrices["ETH"] = double.parse(data['price']);
          });
        }
        return; // Exit if Binance succeeds
      }
    } catch (e) {
      print("⚠️ [API] Binance price fetch failed, trying fallback...");
    }

    // 2. Fallback to Coinbase
    try {
      final coinbaseRes = await http
          .get(Uri.parse('https://api.coinbase.com/v2/prices/ETH-USD/spot'))
          .timeout(const Duration(seconds: 4));

      if (coinbaseRes.statusCode == 200) {
        final data = json.decode(coinbaseRes.body);
        if (mounted) {
          setState(() {
            _usdPrices["ETH"] = double.parse(data['data']['amount']);
          });
        }
      }
    } catch (e) {
      print("❌ [API] Both Binance and Coinbase failed: $e");
    }
  }

  Future<void> _handleLogout() async {
    print("👋 [Auth] Logging out...");
    HapticFeedback.lightImpact();
    setState(() => _isLoggingOut = true);
    await Future.delayed(const Duration(milliseconds: 800));
    try {
      await zapBridge.logout().toDart;
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const LandingScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 800),
        ),
        (route) => false,
      );
    } catch (e) {
      print("❌ [Auth Error] Logout failed: $e");
      setState(() => _isLoggingOut = false);
    }
  }

  void _showDepositQR() {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: AppTheme.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Color(0xFF1E1E2E))),
        child: Container(
          width: 400, padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Add Money", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  IconButton(icon: const Icon(Icons.close, color: AppTheme.textMuted), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                child: QrImageView(data: widget.connectedAddress, version: QrVersions.auto, size: 200.0),
              ),
              const SizedBox(height: 24),
              const Text("Network: Base", style: TextStyle(color: AppTheme.lifi, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              const Text("Send only USDC or ETH on the Base network to this address.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: const Color(0xFF0F0F16), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF1E1E2E))),
                child: Text(widget.connectedAddress, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontFamily: 'monospace'), textAlign: TextAlign.center),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.lifi, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text("Copy Address", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    Clipboard.setData(ClipboardData(text: widget.connectedAddress));
                    Navigator.pop(context);
                    BannerUtils.showBanner("Address copied to clipboard!", context: context, isError: false);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSwapModal() {
    HapticFeedback.lightImpact();
    String swapInToken = "USDC";
    String swapOutToken = "ETH";
    TextEditingController swapAmountCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            backgroundColor: AppTheme.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Color(0xFF1E1E2E))),
            child: Container(
              width: 400, padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Exchange", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      IconButton(icon: const Icon(Icons.close, color: AppTheme.textMuted), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("FROM", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: swapInToken, dropdownColor: AppTheme.cardBg, icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textMuted),
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.amber),
                              decoration: InputDecoration(
                                filled: true, fillColor: const Color(0xFF0F0F16), contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
                              ),
                              items: ["USDC", "ETH"].map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                              onChanged: (val) { HapticFeedback.selectionClick(); setModalState(() => swapInToken = val!); },
                            ),
                          ],
                        ),
                      ),
                      const Padding(padding: EdgeInsets.only(left: 16, right: 16, top: 20), child: Icon(Icons.arrow_forward, color: AppTheme.textMuted, size: 20)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("TO", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: swapOutToken, dropdownColor: AppTheme.cardBg, icon: const Icon(Icons.keyboard_arrow_down, color: AppTheme.textMuted),
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.amber),
                              decoration: InputDecoration(
                                filled: true, fillColor: const Color(0xFF0F0F16), contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
                                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
                              ),
                              items: ["USDC", "ETH"].map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                              onChanged: (val) { HapticFeedback.selectionClick(); setModalState(() => swapOutToken = val!); },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text("AMOUNT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: swapAmountCtrl, keyboardType: TextInputType.number,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "0.00", hintStyle: const TextStyle(color: AppTheme.textMuted), filled: true, fillColor: const Color(0xFF0F0F16),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: () async {
                        print("💱 [Swap] Initiating Swap via LI.FI...");
                        HapticFeedback.heavyImpact();
                        double val = double.tryParse(swapAmountCtrl.text) ?? 0.0;
                        if (val <= 0 || val > _getCurrentTokenBalance(swapInToken)) {
                          BannerUtils.showBanner("Invalid amount or insufficient balance", context: context);
                          return;
                        }
                        Navigator.pop(context);
                        setState(() { _txPhase = TxPhase.processing; _txStatusMessage = "Exchanging via LI.FI..."; _txHash = null; _selectedIndex = 0; });
                        try {
                          final dynamic result = await zapBridge.executeNativeSwap(swapInToken.toJS, swapOutToken.toJS, swapAmountCtrl.text.toJS).toDart;
                          HapticFeedback.heavyImpact();
                          setState(() { _txPhase = TxPhase.success; _txStatusMessage = "Exchange Complete!"; _txHash = _safeConvertJsString(result) ?? "Transaction sent"; });
                          print("✅ [Swap] Success: $_txHash");
                          _fetchBalances();
                        } catch (e) {
                          HapticFeedback.vibrate();
                          print("❌ [Swap Error] $e");
                          setState(() { _txPhase = TxPhase.error; _txStatusMessage = "Exchange Failed"; });
                        }
                      },
                      child: const Text("Execute Swap", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showSendModal() {
    HapticFeedback.lightImpact();
    String sendToken = "USDC";
    TextEditingController sendAddressCtrl = TextEditingController();
    TextEditingController sendAmountCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            backgroundColor: AppTheme.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: Color(0xFF1E1E2E))),
            child: Container(
              width: 400, padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Send Money", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                      IconButton(icon: const Icon(Icons.close, color: AppTheme.textMuted), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text("ASSET", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  Row(
                    children: ["USDC", "ETH"].map((tok) {
                      bool sel = sendToken == tok;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () { HapticFeedback.selectionClick(); setModalState(() => sendToken = tok); },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: sel ? const Color(0xFF1E1600) : const Color(0xFF0F0F16),
                              border: Border.all(color: sel ? AppTheme.indigo : const Color(0xFF1E1E2E)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(child: Text(tok, style: TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold, color: sel ? AppTheme.indigo : AppTheme.textMuted))),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text("RECIPIENT ADDRESS", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: sendAddressCtrl,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 14, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "0x...", hintStyle: const TextStyle(color: AppTheme.textMuted), filled: true, fillColor: const Color(0xFF0F0F16),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text("AMOUNT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: sendAmountCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "0.00", hintStyle: const TextStyle(color: AppTheme.textMuted), filled: true, fillColor: const Color(0xFF0F0F16),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: () async {
                        print("💸 [Send] Initiating transfer...");
                        HapticFeedback.heavyImpact();
                        if (sendAddressCtrl.text.trim().isEmpty) {
                          BannerUtils.showBanner("Invalid EVM address format.", context: context, isError: true);
                          return;
                        }
                        double val = double.tryParse(sendAmountCtrl.text.trim()) ?? 0.0;
                        if (val <= 0 || val > _getCurrentTokenBalance(sendToken)) {
                          BannerUtils.showBanner("Insufficient $sendToken balance.", context: context, isError: true);
                          return;
                        }
                        Navigator.pop(context);
                        setState(() { _txPhase = TxPhase.processing; _txStatusMessage = "Sending Payment..."; _txHash = null; _selectedIndex = 0; });
                        try {
                          final dynamic hashJs = await zapBridge.transferToken(sendToken.toJS, sendAddressCtrl.text.trim().toJS, sendAmountCtrl.text.trim().toJS).toDart;
                          HapticFeedback.heavyImpact();
                          setState(() { _txPhase = TxPhase.success; _txStatusMessage = "Transfer Broadcasted!"; _txHash = _safeConvertJsString(hashJs); });
                          print("✅ [Send] Transfer broadcasted: $_txHash");
                          BannerUtils.showBanner("Transfer sent successfully!", context: context, isError: false);
                          _fetchBalances();
                        } catch (e) {
                          print("❌ [Send Error] $e");
                          HapticFeedback.vibrate();
                          setState(() { _txPhase = TxPhase.error; _txStatusMessage = "Transfer Rejected or Failed."; });
                          BannerUtils.showBanner("Transfer failed.", context: context, isError: true);
                        }
                      },
                      child: const Text("Send Funds", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _fetchMyStreams({bool silent = false}) async {
    if (!silent && _myStreams.isEmpty) {
      setState(() => _isLoadingStreams = true);
    }
    try {
      if (!silent) print("📡 [INTEROP] Fetching streams...");
      
      final idRes = await zapBridge.getNextStreamId().toDart;
      // Safety check: if the contract returned nothing or failed to decode, abort cleanly.
      if (idRes == null) {
          if (mounted && !silent) setState(() => _isLoadingStreams = false);
          return;
      }
      
      final int totalStreams = (idRes as JSNumber).toDartInt;
      List<StreamData> fetchedStreams = [];
      String myNormalizedAddress = ZapStreamConfig.normalizeAddress(widget.connectedAddress);

      for (int i = totalStreams - 1; i >= 1; i--) {
        try {
          final streamRes = await zapBridge.getStream(i.toJS).toDart;
          if (streamRes == null) continue;
          final resList = (streamRes as JSArray).toDart.map((e) => (e as JSString).toDart).toList();
          if (resList.length < 13) continue;

          String sender = ZapStreamConfig.normalizeAddress(resList[0]);
          String recipient = ZapStreamConfig.normalizeAddress(resList[1]);
          String claimHash = resList.length > 13 ? resList[13] : "0x0";

          String? intendedEmail;
          String? senderEmail;

          if (sender == myNormalizedAddress || recipient == myNormalizedAddress || claimHash != "0x0") {
            final existingStream = _myStreams.where((s) => s.id == i).firstOrNull;

            if (existingStream != null && existingStream.intendedEmail != null) {
              intendedEmail = existingStream.intendedEmail;
              senderEmail = existingStream.senderEmail;
            } else {
              try {
                final res = await http.get(Uri.parse('https://inflow-relay.zapstream.workers.dev/stream-info?id=$i'));
                if (res.statusCode == 200) {
                  final data = jsonDecode(res.body);
                  intendedEmail = data['recipientEmail'];
                  senderEmail = data['senderEmail'];
                }
              } catch (e) {}
            }

            if (sender == myNormalizedAddress || recipient == myNormalizedAddress) {
              fetchedStreams.add(
                StreamData(
                  id: i, sender: sender, recipient: recipient,
                  asset: ZapStreamConfig.normalizeAddress(resList[2]),
                  deposit: ZapStreamConfig.decodeU256(resList[3]),
                  remainingBalance: ZapStreamConfig.decodeU256(resList[9]),
                  withdrawnAmount: ZapStreamConfig.decodeU256(resList[11]),
                  startTime: int.parse(resList[7]), stopTime: int.parse(resList[8]),
                  claimHash: claimHash, intendedEmail: intendedEmail, senderEmail: senderEmail,
                ),
              );
            }
          }
        } catch (e) {debugPrint(e.toString());}
      }

      fetchedStreams.sort((a, b) => b.id.compareTo(a.id));
      if (mounted) setState(() => _myStreams = fetchedStreams);
      if (!silent) print("✅ [Streams] Found ${fetchedStreams.length} active streams for user.");
    } catch (e) {
      if (!silent) print("⚠️ [Streams Error] Ignored fetch error (Likely contract mismatch): $e");
    } finally {
      if (mounted && !silent) setState(() => _isLoadingStreams = false);
    }
  }
  Future<void> _createStream() async {
    print("🌊 [Stream] Initiating create stream process...");
    HapticFeedback.heavyImpact();
    final String recipientEmail = _recipientEmailCtrl.text.trim();
    if (recipientEmail.isEmpty || !recipientEmail.contains('@')) {
      BannerUtils.showBanner("Please enter a valid recipient email.", context: context, isError: true);
      return;
    }

    final double parsedVal = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    if (parsedVal <= 0) {
      BannerUtils.showBanner("Amount must be greater than 0.", context: context, isError: true);
      return;
    }
    if (parsedVal > _getCurrentTokenBalance(_selectedToken)) {
      BannerUtils.showBanner("Insufficient $_selectedToken balance.", context: context, isError: true);
      return;
    }

    final int durationDays = int.tryParse(_durationDaysCtrl.text.trim()) ?? 0;
    if (durationDays <= 0) {
      BannerUtils.showBanner("Duration must be at least 1 day.", context: context, isError: true);
      return;
    }

    setState(() {
      _txPhase = TxPhase.processing;
      _txStatusMessage = "Zapping into Yield Stream...";
      _txHash = null;
      _lastAmount = parsedVal.toString();
      _lastDays = durationDays.toString();
    });

    try {
      final durationSeconds = durationDays * 86400;
      String targetVault = _yieldEnabled ? _selectedVaultAddress : ZapStreamConfig.USDC_ADDRESS;
      print("🌐 [INTEROP] Calling createYieldStream (Vault: $targetVault)...");

      final dynamic responseJs = await zapBridge
          .createYieldStream(_selectedToken.toJS, parsedVal.toString().toJS, durationSeconds.toJS, targetVault.toJS)
          .toDart;

      final responseJson = json.decode(_safeConvertJsString(responseJs) ?? "{}");
      print("✅ [Stream] Created successfully: ${responseJson['txHash']}");

      final idRes = await zapBridge.getNextStreamId().toDart;
      final newStreamId = (idRes as JSNumber).toDartInt - 1;

      print("🌐 [INTEROP] Storing secret in Cloudflare Relay...");
      await zapBridge.storeStreamSecret(newStreamId.toJS, responseJson['secret'].toJS, recipientEmail.toJS, (widget.isMainnet ? "mainnet" : "sepolia").toJS).toDart;

      HapticFeedback.heavyImpact();
      setState(() {
        _txPhase = TxPhase.success;
        _txStatusMessage = "Salary stream is live!";
        _txHash = responseJson['txHash'];
        _lastCreatedStreamId = newStreamId;
      });
      BannerUtils.showBanner("Stream deployed successfully!", context: context, isError: false);
      _fetchBalances();
      _fetchMyStreams(silent: true);
    } catch (e) {
      print("❌ [Stream Error] $e");
      HapticFeedback.vibrate();
      setState(() { _txPhase = TxPhase.error; _txStatusMessage = "Stream Creation Rejected or Failed."; });
      BannerUtils.showBanner("Stream creation failed.", context: context, isError: true);
    }
  }

  Future<void> _withdrawStream(int streamId, double unlockedTokens, bool isFullyUnlocked) async {
    print("💸 [Withdraw] Initiating withdrawal from stream ID $streamId...");
    HapticFeedback.heavyImpact();
    final stream = _myStreams.firstWhere((s) => s.id == streamId);

    int decimals = 6; 
    double alreadyWithdrawn = stream.withdrawnAmount / BigInt.from(10).pow(decimals);
    double currentlyWithdrawable = unlockedTokens - alreadyWithdrawn;

    if (currentlyWithdrawable <= 0.000001 && !isFullyUnlocked) {
      BannerUtils.showBanner("No new earnings to collect yet.", context: context, isError: true);
      return;
    }

    setState(() { _txPhase = TxPhase.processing; _txStatusMessage = "Redeeming Yield & Withdrawing..."; });

    try {
      BigInt amountWei;
      if (isFullyUnlocked) {
        amountWei = stream.remainingBalance;
        if (amountWei <= BigInt.zero) {
          setState(() => _txPhase = TxPhase.none);
          BannerUtils.showBanner("All earnings have already been collected.", context: context, isError: true);
          return;
        }
      } else {
        double safeAmount = currentlyWithdrawable * 0.995;
        amountWei = BigInt.from((safeAmount * 1000000).round());
      }

      print("🌐 [INTEROP] Calling withdrawAndRedeemYield...");
      final dynamic hashJs = await zapBridge.withdrawAndRedeemYield(streamId.toJS, amountWei.toString().toJS, stream.asset.toJS).toDart;

      HapticFeedback.heavyImpact();
      setState(() {
        _txPhase = TxPhase.success;
        _txStatusMessage = "Earnings Redeemed!";
        _txHash = _safeConvertJsString(hashJs);
      });

      print("✅ [Withdraw] Success: $_txHash");
      BannerUtils.showBanner("Earnings withdrawn successfully!", context: context, isError: false);
      _fetchMyStreams();
      _fetchBalances();
    } catch (e) {
      print("❌ [Withdraw Error] $e");
      HapticFeedback.vibrate();
      setState(() { _txPhase = TxPhase.error; _txStatusMessage = "Withdrawal Failed"; });
      BannerUtils.showBanner("Amount exceeds available balance. Try withdrawing a slightly smaller amount.", context: context, isError: true);
    }
  }

  Future<void> _cancelStream(int streamId) async {
    print("🛑 [Cancel] Initiating cancel for stream ID $streamId...");
    HapticFeedback.heavyImpact();
    setState(() { _txPhase = TxPhase.processing; _txStatusMessage = "Stopping Payment..."; });
    try {
      final dynamic hashJs = await zapBridge.cancelStream(streamId.toJS).toDart;
      HapticFeedback.heavyImpact();
      setState(() { _txPhase = TxPhase.success; _txStatusMessage = "Stream Cancelled!"; _txHash = _safeConvertJsString(hashJs); });
      print("✅ [Cancel] Success: $_txHash");
      BannerUtils.showBanner("Stream successfully cancelled.", context: context, isError: false);
      _fetchMyStreams();
      _fetchBalances();
    } catch (e) {
      print("❌ [Cancel Error] $e");
      HapticFeedback.vibrate();
      setState(() { _txPhase = TxPhase.error; _txStatusMessage = "Cancellation Rejected."; });
      BannerUtils.showBanner("Cancellation failed.", context: context, isError: true);
    }
  }

  void _copyViralLink(int streamId) {
    HapticFeedback.lightImpact();
    final url = "https://useinflow.web.app/how-it-works?stream=$streamId";
    Clipboard.setData(ClipboardData(text: url));
    BannerUtils.showBanner("Secure Payment Link Copied!", context: context, isError: false);
  }

  String _formatRemainingTime(int stopTime) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final diff = stopTime - now;
    if (diff <= 0) return "Finished";
    if (diff >= 86400) return "${diff ~/ 86400}d ${(diff % 86400) ~/ 3600}h remaining";
    if (diff >= 3600) return "${diff ~/ 3600}h ${(diff % 3600) ~/ 60}m remaining";
    if (diff >= 60) return "${diff ~/ 60}m ${diff % 60}s remaining";
    return "${diff}s remaining";
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoggingOut) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: AppTheme.amber)),
              const SizedBox(height: 24),
              const Text("Signing out...", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)).animate().fadeIn(),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            double maxWidth = constraints.maxWidth > 800 ? 500 : double.infinity;
            return Container(
              width: maxWidth,
              decoration: BoxDecoration(
                color: const Color(0xFF07070B),
                borderRadius: BorderRadius.circular(18),
                border: constraints.maxWidth > 800 ? Border.all(color: const Color(0xFF1E1E2E)) : null,
                boxShadow: constraints.maxWidth > 800 ? [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, spreadRadius: 10)] : null,
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 12),
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFF1E1E2E)))),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("inFlow", style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: AppTheme.amber, letterSpacing: -0.3)),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                                  decoration: BoxDecoration(color: const Color(0xFF1A1A28), borderRadius: BorderRadius.circular(20)),
                                  child: Row(
                                    children: [
                                      const Icon(CupertinoIcons.person_solid, size: 12, color: AppTheme.textMuted),
                                      const SizedBox(width: 4),
                                      Text(widget.loggedInEmail, style: const TextStyle(fontSize: 11, color: AppTheme.textMuted, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                InkWell(
                                  onTap: _handleLogout,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.red.withOpacity(0.3))),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.logout, size: 12, color: AppTheme.red),
                                        const SizedBox(width: 4),
                                        const Text("Logout", style: TextStyle(fontSize: 11, color: AppTheme.red, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 11),
                        Row(
                          children: [
                            Expanded(child: _buildTabBtn("Wallet", 0)),
                            const SizedBox(width: 4),
                            Expanded(child: _buildTabBtn("Pay", 1)),
                            const SizedBox(width: 4),
                            Expanded(child: _buildTabBtn("Streams", 2)),
                            const SizedBox(width: 4),
                            Expanded(child: _buildTabBtn("Earn", 3)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: KeyboardScrollWrapper(
                      controller: _mainScrollController,
                      child: SingleChildScrollView(
                        controller: _mainScrollController,
                        padding: const EdgeInsets.all(17),
                        child: _txPhase != TxPhase.none ? _buildTransactionOverlay() : _buildSelectedTab(),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTabBtn(String label, int index) {
    bool isSel = _selectedIndex == index;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        if (_txPhase != TxPhase.none) return;
        setState(() => _selectedIndex = index);
        if (index == 2) _fetchMyStreams();
        if (index == 0) _fetchBalances();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSel ? AppTheme.amber : const Color(0xFF1A1A28),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSel ? Colors.black : AppTheme.textMuted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedTab() {
    switch (_selectedIndex) {
      case 0: return _buildWalletView();
      case 1: return _buildPaySomeoneView();
      case 2: return _buildMyStreamsView();
      case 3: return _buildEarnView();
      default: return _buildWalletView();
    }
  }

  Widget _buildTransactionOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_txPhase == TxPhase.processing) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppTheme.amber.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(CupertinoIcons.arrow_2_circlepath, size: 40, color: AppTheme.amber).animate(onPlay: (c) => c.repeat()).rotate(duration: 2.seconds),
            ),
            const SizedBox(height: 24),
            Text(_txStatusMessage, style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text("Securely processing on Base...", style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            const SizedBox(height: 40),
            const SizedBox(width: 40, child: LinearProgressIndicator(color: AppTheme.amber, backgroundColor: Color(0xFF1A1A28))),
          ] else if (_txPhase == TxPhase.success) ...[
            Container(
              width: 62, height: 62,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppTheme.green.withOpacity(0.18), border: Border.all(color: AppTheme.green.withOpacity(0.35))),
              child: const Center(child: Text("✓", style: TextStyle(color: AppTheme.green, fontSize: 24, fontWeight: FontWeight.bold))),
            ).animate().scale(curve: Curves.elasticOut, duration: 600.ms),
            const SizedBox(height: 18),
            Text(_txStatusMessage, style: const TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 7),
            Text(
              _selectedIndex == 1
                  ? "Funds are allocated and streaming. Share the link — your recipient signs in with email and starts earning immediately."
                  : "Transaction broadcasted successfully.",
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.6),
            ),
            const SizedBox(height: 20),

            if (_txHash != null && _selectedIndex != 1) ...[
              ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text("View Confirmation", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E1E2E), foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: () { HapticFeedback.lightImpact(); launchUrl(Uri.parse(ZapStreamConfig.getVoyagerUrl(_txHash!, widget.isMainnet))); },
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 24),
            ],

            if (_selectedIndex == 1 && _lastCreatedStreamId != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: const Color(0xFF13131C), border: Border.all(color: const Color(0xFF1E1E2E)), borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("PAYMENT SUMMARY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
                    const SizedBox(height: 11),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Amount", style: TextStyle(color: AppTheme.textMuted, fontSize: 13)), Text("$_lastAmount $_selectedToken", style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.white))]),
                    const SizedBox(height: 7),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Pay Period", style: TextStyle(color: AppTheme.textMuted, fontSize: 13)), Text("$_lastDays days", style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.white))]),
                  ],
                ),
              ).animate().fadeIn(delay: 400.ms),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFF1E1600), border: Border.all(color: const Color(0xFF2A1E00)), borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Share this secure link with your recipient", style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
                    const SizedBox(height: 9),
                    Container(
                      width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(color: const Color(0xFF0A0800), borderRadius: BorderRadius.circular(10)),
                      child: Text("useinflow.web.app/how-it-works?stream=$_lastCreatedStreamId", style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppTheme.amber)),
                    ),
                    const SizedBox(height: 11),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amber, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () => _copyViralLink(_lastCreatedStreamId!),
                        child: const Text("Copy Payment Link", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 600.ms),
              const SizedBox(height: 24),
            ],
            TextButton(
              onPressed: () {
                HapticFeedback.selectionClick();
                setState(() { _txPhase = TxPhase.none; _amountCtrl.clear(); _durationDaysCtrl.clear(); _recipientEmailCtrl.clear(); });
                if (_selectedIndex == 1) { setState(() => _selectedIndex = 2); _fetchMyStreams(); }
              },
              child: const Text("Done", style: TextStyle(color: AppTheme.textMuted, fontSize: 14, fontWeight: FontWeight.bold)),
            ).animate().fadeIn(delay: 800.ms),
          ] else if (_txPhase == TxPhase.error) ...[
            const Icon(Icons.error_outline, size: 60, color: AppTheme.red).animate().shake(hz: 4, curve: Curves.easeInOut),
            const SizedBox(height: 24),
            const Text("Transaction Failed", style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(_txStatusMessage, style: const TextStyle(color: AppTheme.red, fontSize: 13), textAlign: TextAlign.center),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () { HapticFeedback.lightImpact(); setState(() => _txPhase = TxPhase.none); },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E1E2E), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text("Dismiss", style: TextStyle(fontSize: 13)),
            ),
          ],
        ],
      ),
    ).animate().fadeIn().scale(begin: const Offset(0.95, 0.95));
  }

  Widget _buildWalletView() {
    double usdc = double.tryParse(_usdcBalance) ?? 0.0;
    double eth = double.tryParse(_ethBalance) ?? 0.0;
    double totalUsd = usdc + (eth * (_usdPrices["ETH"] ?? 0.0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.lifi.withOpacity(0.05),
            border: Border.all(color: AppTheme.lifi.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.only(bottom: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("EARNING YIELD VIA LI.FI", style: TextStyle(fontSize: 10, color: AppTheme.lifi, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  const SizedBox(height: 2),
                  Text("$_bestVaultProtocol · ${_bestUsdcApy.toStringAsFixed(2)}% APY", style: const TextStyle(fontSize: 10, color: AppTheme.muted)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text("Active", style: TextStyle(fontFamily: 'monospace', fontSize: 14, color: AppTheme.green, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  const Text("via composer", style: TextStyle(fontSize: 10, color: AppTheme.muted)),
                ],
              )
            ],
          ),
        ),

        const Text("TOTAL BALANCE", style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
          children: [
            const Text("\$", style: TextStyle(fontFamily: 'monospace', fontSize: 36, fontWeight: FontWeight.w500, letterSpacing: -1, color: Colors.white)),
            Text(totalUsd.toStringAsFixed(2).split('.')[0], style: const TextStyle(fontFamily: 'monospace', fontSize: 36, fontWeight: FontWeight.w500, letterSpacing: -1, color: Colors.white)),
            Text(".${totalUsd.toStringAsFixed(2).split('.')[1]}", style: const TextStyle(fontFamily: 'monospace', fontSize: 22, color: AppTheme.textMuted)),
          ],
        ),
        const SizedBox(height: 26),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildWalletAction("↓", "Add Money", AppTheme.green, _showDepositQR),
            _buildWalletAction("↑", "Send", AppTheme.indigo, _showSendModal),
            _buildWalletAction("⇄", "Swap", AppTheme.amber, _showSwapModal),
            _buildWalletAction("⚡", "Pay", AppTheme.amber, () { HapticFeedback.lightImpact(); setState(() => _selectedIndex = 1); }),
          ],
        ),
        const SizedBox(height: 30),
        const Text("ASSETS", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
        const SizedBox(height: 10),
        _buildAssetRow("USD Coin", "USDC", _usdcBalance, (usdc * 1.0).toStringAsFixed(2), const Color(0xFF3B82F6)),
      ],
    ).animate().fadeIn();
  }

  Widget _buildWalletAction(String icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 44, height: 44, margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withOpacity(0.2))),
            child: Center(child: Text(icon, style: TextStyle(fontSize: 17, color: color))),
          ),
          Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildAssetRow(String name, String symbol, String bal, String usd, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: const Color(0xFF13131C), border: Border.all(color: const Color(0xFF1E1E2E)), borderRadius: BorderRadius.circular(13)),
      child: Row(
        children: [
          Container(
            width: 36, height: 36, margin: const EdgeInsets.only(right: 13),
            decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(11)),
            child: Center(child: Text(symbol[0], style: TextStyle(color: color, fontWeight: FontWeight.bold, fontFamily: 'monospace'))),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 2),
                Text("$bal $symbol", style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontFamily: 'monospace')),
              ],
            ),
          ),
          Text("\$$usd", style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildPaySomeoneView() {
    double amt = double.tryParse(_amountCtrl.text.trim()) ?? 0.0;
    int d = int.tryParse(_durationDaysCtrl.text.trim()) ?? 0;

    double yieldEst = 0.0;
    if (d > 0 && amt > 0 && _yieldEnabled) {
      yieldEst = (amt * (_bestUsdcApy / 100) * d) / 365;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Stream + Yield", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text("Locked funds earn vault yield while salary streams.", style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.6)),
        const SizedBox(height: 20),

        // LI.FI Auto-Selector
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.lifi.withOpacity(0.05),
            border: Border.all(color: AppTheme.lifi.withOpacity(0.35)),
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.only(bottom: 18),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("AUTO-SELECTED VAULT · LI.FI EARN", style: TextStyle(fontSize: 9, color: AppTheme.lifi, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                      const SizedBox(height: 4),
                      Text("$_bestVaultProtocol USDC", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 2),
                      const Text("Base Mainnet · Auto-routing", style: TextStyle(fontSize: 10, color: AppTheme.muted)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("${_bestUsdcApy.toStringAsFixed(2)}%", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.green, fontFamily: 'monospace')),
                      const Text("APY", style: TextStyle(fontSize: 10, color: AppTheme.muted)),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (_pill1Apy > 0) _buildApyPill(_pill1Name, _pill1Apy, AppTheme.green),
                  if (_pill1Apy > 0) const SizedBox(width: 6),
                  if (_pill2Apy > 0) _buildApyPill(_pill2Name, _pill2Apy, const Color(0xFF2EBAC6)),
                ],
              )
            ],
          ),
        ),

        const Text("RECIPIENT EMAIL", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
        const SizedBox(height: 8),
        TextField(
          controller: _recipientEmailCtrl,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 14, color: Colors.white),
          decoration: InputDecoration(
            hintText: "employee@email.com", hintStyle: const TextStyle(color: AppTheme.textMuted), filled: true, fillColor: const Color(0xFF0F0F16),
            contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("TOTAL AMOUNT", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
                  const SizedBox(height: 7),
                  TextField(
                    controller: _amountCtrl, keyboardType: TextInputType.number, onChanged: (v) => setState(() {}),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                    decoration: InputDecoration(
                      filled: true, fillColor: const Color(0xFF0F0F16), contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("DURATION (DAYS)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textMuted, letterSpacing: 1.2)),
                  const SizedBox(height: 7),
                  TextField(
                    controller: _durationDaysCtrl, keyboardType: TextInputType.number, onChanged: (v) => setState(() {}),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                    decoration: InputDecoration(
                      filled: true, fillColor: const Color(0xFF0F0F16), contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E1E2E))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Yield Preview Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppTheme.green.withOpacity(0.05), border: Border.all(color: AppTheme.green.withOpacity(0.2)), borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Streaming rate", style: TextStyle(fontSize: 11, color: AppTheme.muted)),
                  Text(d > 0 ? "\$${(amt / (d * 86400)).toStringAsFixed(6)}/sec" : "\$0.00/sec", style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.amber)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Vault APY", style: TextStyle(fontSize: 11, color: AppTheme.muted)),
                  Text("${_bestUsdcApy.toStringAsFixed(2)}% · $_bestVaultProtocol", style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.green)),
                ],
              ),
              Container(height: 1, color: AppTheme.border, margin: const EdgeInsets.symmetric(vertical: 8)),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Yield bonus to recipient", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  Text("+\$${yieldEst.toStringAsFixed(2)}", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.green, fontFamily: 'monospace')),
                ],
              ),
              const SizedBox(height: 4),
              const Align(alignment: Alignment.centerLeft, child: Text("Recipient gets salary + vault yield when they collect", style: TextStyle(fontSize: 10, color: AppTheme.muted))),
            ],
          ),
        ),

        // Yield Toggle
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: AppTheme.cardBg, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.only(bottom: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Enable Yield Generation", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 2),
                  const Text("Auto-deposits via LI.FI Composer", style: TextStyle(fontSize: 11, color: AppTheme.muted)),
                ],
              ),
              CupertinoSwitch(
                value: _yieldEnabled,
                activeColor: AppTheme.green,
                onChanged: (v) => setState(() => _yieldEnabled = v),
              ),
            ],
          ),
        ),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _createStream,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.amber, foregroundColor: Colors.black, padding: const EdgeInsets.all(15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Create Yield Stream → Get Link", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    ).animate().fadeIn();
  }

  Widget _buildApyPill(String protocol, double apy, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.15), border: Border.all(color: color.withOpacity(0.3)), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(protocol, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace', letterSpacing: 0.8)),
          const SizedBox(width: 6),
          Text("${apy.toStringAsFixed(2)}%", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  // --- EARN SCREEN ---
  Widget _buildEarnView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text("Earn Vaults", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppTheme.lifi.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.lifi.withOpacity(0.3))),
              child: const Text("via LI.FI Earn", style: TextStyle(fontSize: 9, color: AppTheme.lifi, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            )
          ],
        ),
        const SizedBox(height: 6),
        const Text("One-tap deposit into top DeFi protocols.", style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppTheme.green.withOpacity(0.05), border: Border.all(color: AppTheme.green.withOpacity(0.2)), borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("YOUR ACTIVE POSITION", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.muted, letterSpacing: 1.0)),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("0.00 USDC", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                      const SizedBox(height: 2),
                      Text("$_bestVaultProtocol · Base", style: const TextStyle(fontSize: 11, color: AppTheme.muted)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("${_bestUsdcApy.toStringAsFixed(2)}% APY", style: const TextStyle(fontSize: 16, color: AppTheme.green, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                      const SizedBox(height: 2),
                      const Text("+\$0.00 today", style: TextStyle(fontSize: 11, color: AppTheme.muted)),
                    ],
                  )
                ]
              )
            ],
          )
        ),

        const Text("ALL VAULTS · SORTED BY APY", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.muted, letterSpacing: 1.2)),
        const SizedBox(height: 12),

        if (_isLoadingVaults)
          const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator(color: AppTheme.lifi)))
        else if (_lifiVaults.isEmpty)
           const Center(child: Padding(padding: EdgeInsets.all(32), child: Text("No vaults found via LI.FI Earn API.", style: TextStyle(color: AppTheme.muted))))
        else
          ..._lifiVaults.map((vault) {
             String protocol = vault['name'] ?? "Vault";
             
             var rawApy = vault['analytics']?['apy']?['total'];
             double apy = (rawApy is num ? rawApy.toDouble() : double.tryParse(rawApy?.toString() ?? '0') ?? 0.0);
             
             dynamic tvlData = vault['analytics']?['tvl'];
             double tvlNum = 0.0;
             if (tvlData is num) {
               tvlNum = tvlData.toDouble();
             } else if (tvlData is String) {
               tvlNum = double.tryParse(tvlData) ?? 0.0;
             } else if (tvlData is Map && tvlData['usd'] != null) {
               var usdVal = tvlData['usd'];
               tvlNum = usdVal is num ? usdVal.toDouble() : double.tryParse(usdVal?.toString() ?? '0') ?? 0.0;
             }
             
             String tvl = tvlNum >= 1000000 
                 ? "\$${(tvlNum / 1000000).toStringAsFixed(1)}M" 
                 : "\$${tvlNum.toStringAsFixed(0)}";
                 
             String risk = vault['risk']?['rating'] ?? "Medium";
             String symbol = vault['asset']?['symbol'] ?? "USDC";

             Color protoColor = protocol.toLowerCase().contains("morpho") ? AppTheme.green : const Color(0xFF2EBAC6);

             return Container(
               margin: const EdgeInsets.only(bottom: 10),
               padding: const EdgeInsets.all(14),
               decoration: BoxDecoration(color: AppTheme.cardBg, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(14)),
               child: Row(
                 mainAxisAlignment: MainAxisAlignment.spaceBetween,
                 children: [
                    Row(
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: protoColor.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                          child: const Center(child: Text("🏛", style: TextStyle(fontSize: 16))),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(protocol, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(height: 2),
                            Text("$symbol · Base · TVL $tvl", style: const TextStyle(fontSize: 10, color: AppTheme.muted, fontFamily: 'monospace')),
                          ],
                        )
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("${apy.toStringAsFixed(2)}%", style: TextStyle(fontSize: 16, color: protoColor, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                        const SizedBox(height: 2),
                        Text(risk, style: TextStyle(fontSize: 9, color: risk == "Low" ? AppTheme.green : AppTheme.amber, fontWeight: FontWeight.bold)),
                      ],
                    )
                 ],
               )
             );
          }).toList(),
      ],
    ).animate().fadeIn();
  }

  // --- STREAM CARDS ---
  Widget _buildMyStreamsView() {
    if (_isLoadingStreams) return const Center(child: Padding(padding: EdgeInsets.all(48.0), child: CircularProgressIndicator(color: AppTheme.amber)));
    if (_myStreams.isEmpty) return const Center(child: Padding(padding: EdgeInsets.all(48.0), child: Text("No active salary streams.", style: TextStyle(color: AppTheme.textMuted, fontSize: 14))));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("My Streams", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppTheme.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Text("${_myStreams.length} active", style: const TextStyle(color: AppTheme.green, fontSize: 10, fontWeight: FontWeight.bold)),
            )
          ],
        ),
        const SizedBox(height: 16),
        ..._myStreams.map((s) => _buildStreamCard(s)),
      ],
    ).animate().fadeIn();
  }

  Widget _buildStreamCard(StreamData stream) {
    String tokenSymbol = "USDC";
    String streamAsset = stream.asset.toLowerCase();
    bool isVault = streamAsset != ZapStreamConfig.USDC_ADDRESS.toLowerCase();

    if (isVault) tokenSymbol = "vUSDC";

    int decimals = 6;
    double depositFormatted = stream.deposit / BigInt.from(10).pow(decimals);
    double withdrawnFormatted = stream.withdrawnAmount / BigInt.from(10).pow(decimals);

    String myNormalizedAddress = ZapStreamConfig.normalizeAddress(widget.connectedAddress);
    bool isReceiving = stream.recipient.toLowerCase() == myNormalizedAddress;
    bool isUnclaimed = stream.recipient == "0x0" || stream.recipient == "0x0000000000000000000000000000000000000000";

    final currentTimestampSec = (DateTime.now().millisecondsSinceEpoch / 1000).round();
    bool isFinished = currentTimestampSec >= stream.stopTime;
    bool isDead = stream.remainingBalance == BigInt.zero;
    bool isCancelled = isDead && !isFinished;

    Color cardColor = isReceiving ? AppTheme.green : AppTheme.amber;
    if (isDead) cardColor = AppTheme.textMuted;

    String badgeText = isDead ? (isCancelled ? "CANCELLED" : "SETTLED") : (isUnclaimed ? "UNCLAIMED" : (isReceiving ? "EARNING" : "PAYING"));

    return Container(
      margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isReceiving ? const Color(0xFF0D1812) : const Color(0xFF141008),
        border: Border.all(color: cardColor.withOpacity(0.2)), borderRadius: BorderRadius.circular(18),
      ),
      child: StreamBuilder<int>(
        stream: Stream.periodic(const Duration(seconds: 1), (i) => i),
        builder: (context, snapshot) {
          final currentMs = DateTime.now().millisecondsSinceEpoch;
          final startMs = stream.startTime * 1000;
          final stopMs = stream.stopTime * 1000;

          double progress = 0.0;
          if (currentMs >= stopMs) progress = 1.0;
          else if (currentMs > startMs) progress = (currentMs - startMs) / (stopMs - startMs);
          if (isCancelled) progress = withdrawnFormatted / depositFormatted;

          double unlockedTokens = depositFormatted * progress;
          double totalDurationSec = (stream.stopTime - stream.startTime).toDouble();
          if (totalDurationSec <= 0) totalDurationSec = 1;
          double liveRateMin = (depositFormatted / totalDurationSec) * 60;
          
          double yieldEarned = 0.0;
          if (isVault) {
             double timeElapsedDays = (currentMs - startMs) / (1000 * 86400);
             if(timeElapsedDays > 0 && !isCancelled) {
                 yieldEarned = unlockedTokens * (_bestUsdcApy / 100) * (timeElapsedDays / 365);
             }
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isReceiving ? "Earning from" : "Paying to", style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 3),
                      Text(isReceiving ? (stream.senderEmail ?? _shortAddress(stream.sender)) : (stream.intendedEmail ?? _shortAddress(stream.recipient)), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: cardColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                    child: Text("● $badgeText", style: TextStyle(color: cardColor, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  ),
                ],
              ),

              if (isReceiving && !isDead) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                  decoration: BoxDecoration(color: const Color(0xFF081410), border: Border.all(color: cardColor.withOpacity(0.15)), borderRadius: BorderRadius.circular(13)),
                  child: Column(
                    children: [
                      const Text("EARNED SO FAR", style: TextStyle(fontSize: 10, color: AppTheme.textMuted, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 6),
                      Text(unlockedTokens.toStringAsFixed(6), style: TextStyle(fontFamily: 'monospace', fontSize: 26, fontWeight: FontWeight.w500, color: cardColor, letterSpacing: -0.5)),
                      const SizedBox(height: 3),
                      Text("+${liveRateMin.toStringAsFixed(6)} $tokenSymbol / min · live", style: const TextStyle(color: Color(0xFF2A6040), fontSize: 11, fontFamily: 'monospace')),
                    ],
                  ),
                ),
              ],
              
              if (isVault && !isDead) ...[
                 const SizedBox(height: 12),
                 Container(
                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                   decoration: BoxDecoration(color: AppTheme.lifi.withOpacity(0.1), border: Border.all(color: AppTheme.lifi.withOpacity(0.25)), borderRadius: BorderRadius.circular(10)),
                   child: Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                       Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                           Text("YIELD · $_bestVaultProtocol · ${_bestUsdcApy.toStringAsFixed(2)}% APY", style: const TextStyle(fontSize: 9, color: AppTheme.lifi, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                           const SizedBox(height: 2),
                           const Text("LI.FI Earn vault · Base", style: TextStyle(fontSize: 10, color: AppTheme.muted)),
                         ],
                       ),
                       Column(
                         crossAxisAlignment: CrossAxisAlignment.end,
                         children: [
                           Text("+\$${yieldEarned.toStringAsFixed(4)}", style: const TextStyle(fontSize: 14, color: AppTheme.lifi, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                           const Text("earned", style: TextStyle(fontSize: 9, color: AppTheme.muted)),
                         ],
                       )
                     ],
                   )
                 )
              ],

              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(isReceiving ? "Total Salary" : "Total Budget", style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)), Text("${depositFormatted.toStringAsFixed(2)} $tokenSymbol", style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 13))]),
              const SizedBox(height: 7),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(isReceiving ? "Collected" : "Released So Far", style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)), Text("${withdrawnFormatted.toStringAsFixed(2)} $tokenSymbol", style: TextStyle(fontFamily: 'monospace', color: isReceiving ? Colors.white : cardColor, fontSize: 13))]),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: const Color(0xFF0A0A14), valueColor: AlwaysStoppedAnimation<Color>(cardColor)),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("${(progress * 100).toStringAsFixed(1)}% complete", style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
                  Text(isDead ? "Finished" : _formatRemainingTime(stream.stopTime), style: TextStyle(fontSize: 10, color: isDead ? AppTheme.textMuted : cardColor, fontWeight: FontWeight.bold)),
                ],
              ),

              const SizedBox(height: 14),
              if (!isDead) ...[
                if (isReceiving)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _withdrawStream(stream.id, unlockedTokens, progress >= 1.0),
                      style: ElevatedButton.styleFrom(backgroundColor: cardColor.withOpacity(0.1), foregroundColor: cardColor, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: cardColor.withOpacity(0.3)))),
                      child: Text(isVault ? "Collect Earnings (salary + yield)" : "Collect Earnings", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  )
                else if (!isFinished)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _cancelStream(stream.id),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: AppTheme.red, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: AppTheme.red.withOpacity(0.3)))),
                      child: const Text("Stop Payment", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ),
                if (!isReceiving && isUnclaimed) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _copyViralLink(stream.id),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amber.withOpacity(0.1), foregroundColor: AppTheme.amber, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: AppTheme.amber.withOpacity(0.3)))),
                      child: const Text("Copy Payment Link", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

// ==============================================================
// 7. STORY / INFO SCREEN (Marketing Replica)
// ==============================================================
class StoryScreen extends StatefulWidget {
  const StoryScreen({super.key});

  @override
  State<StoryScreen> createState() => _StoryScreenState();
}

class _StoryScreenState extends State<StoryScreen> {
  final ScrollController _storyScrollController = ScrollController();

  @override
  void dispose() {
    _storyScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> faqs = [
      {
        "q": "Do I need a crypto wallet or any blockchain experience?",
        "a": "No — not at all. You sign in with your email address, just like any other app. We generate a secure wallet for you silently in the background. You never see a seed phrase, never pay gas, and never need to know what a blockchain is.",
      },
      {
        "q": "What does 'streaming salary' actually mean?",
        "a": "Instead of waiting until the end of the month to get paid, your salary unlocks continuously — by the second. If you've worked 12 days of a 30-day contract, you can withdraw exactly 40% of your salary right now. You don't need to ask. You don't need approval. The money is already yours.",
      },
      {
        "q": "How does the LI.FI Earn Yield work?",
        "a": "When an employer creates a stream, the funds don't just sit idle. We use LI.FI Composer to automatically deposit the budget into a top-tier lending protocol (like Morpho or Aave). The funds earn real APY while they wait to be streamed. When you collect your salary, you get the salary + the yield bonus.",
      },
      {
        "q": "What happens if my employer tries to withhold payment?",
        "a": "They can't. When an employer creates a salary stream, the full amount is locked inside a smart contract — it leaves their account immediately. The contract releases it to you automatically based on time worked. Your employer cannot reach back in and take it. The only thing they can do is stop future payments from accruing; anything already earned stays yours.",
      },
      {
        "q": "What currencies are supported?",
        "a": "Currently USDC (a dollar-pegged stablecoin) and ETH on the Base network. For most salary use cases, USDC is recommended since its value stays stable relative to the dollar. The app shows all balances in USD in real time.",
      },
      {
        "q": "Is this testnet or mainnet? Is my money safe?",
        "a": "inFlow is live on Base Mainnet. The smart contract code has been written to be non-custodial — meaning we, as a team, cannot access your funds at any point.",
      },
    ];

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: KeyboardScrollWrapper(
        controller: _storyScrollController,
        child: CustomScrollView(
          controller: _storyScrollController,
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AppTheme.bgDark.withOpacity(0.9),
              elevation: 0,
              automaticallyImplyLeading: false,
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("⚡ inFlow", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.amber, letterSpacing: -0.3)),
                  Row(
                    children: [
                      _buildStoryChip("Live on Base", AppTheme.amber),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amber, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9)),
                        onPressed: () => Navigator.pop(context),
                        child: const Text("Try the App →", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        bool isMobile = constraints.maxWidth < 600;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _buildStoryChip("Built on Base · Powered by LI.FI", AppTheme.green),
                                const SizedBox(height: 24),
                                ShaderMask(
                                  shaderCallback: (bounds) => const LinearGradient(colors: [AppTheme.text, AppTheme.muted], stops: [0.4, 1.0], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(bounds),
                                  child: Text("Money that moves\nas fast as you do.", textAlign: TextAlign.center, style: TextStyle(fontSize: isMobile ? 38 : 48, fontWeight: FontWeight.w800, height: 1.1, letterSpacing: -1.5, color: Colors.white)),
                                ),
                                const SizedBox(height: 20),
                                const Text("Get paid by the second for every second you work.\nYour salary earns vault yield automatically while it streams.\nNo bank account needed.", textAlign: TextAlign.center, style: TextStyle(color: AppTheme.dim, fontSize: 18, height: 1.7)),
                                const SizedBox(height: 36),
                                const _LiveTickerStory(),
                                const SizedBox(height: 36),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text("Try It Now — It's Free →", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            _buildDivider(),

                            _buildSectionLabel("The Problem"),
                            const Text("Across Africa, delayed wages are an epidemic.", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5, height: 1.3, color: Colors.white)),
                            const SizedBox(height: 20),
                            RichText(
                              text: const TextSpan(
                                style: TextStyle(color: AppTheme.dim, fontSize: 15, height: 1.8),
                                children: [
                                  TextSpan(text: "An employee works for 30 days, hands over their full labour, and then waits — hoping their employer pays on time, in full, at all. The ILO has formally described wage debt as "),
                                  TextSpan(text: "\"another African epidemic.\"", style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.w600)),
                                  TextSpan(text: " It is not a fringe problem. It is the default."),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),
                            if (isMobile) ...[
                              _buildStatCard("93%", "of Nigeria's workforce has no formal wage contract", "Nigeria NBS Labour Force Survey, 2024"),
                              const SizedBox(height: 16),
                              _buildStatCard("0", "receipts, proof, or legal recourse for most workers", "ILO Protection of Wages Convention"),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(child: _buildStatCard("93%", "of Nigeria's workforce has no formal wage contract", "Nigeria NBS Labour Force Survey, 2024")),
                                  const SizedBox(width: 16),
                                  Expanded(child: _buildStatCard("0", "receipts, proof, or legal recourse for most workers", "ILO Protection of Wages Convention")),
                                ],
                              ),
                            ],
                            const SizedBox(height: 32),
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: const BoxDecoration(
                                color: AppTheme.cardBg,
                                border: Border(left: BorderSide(color: AppTheme.amber, width: 3), top: BorderSide(color: AppTheme.border), right: BorderSide(color: AppTheme.border), bottom: BorderSide(color: AppTheme.border)),
                                borderRadius: BorderRadius.horizontal(right: Radius.circular(12)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text("\"There is no receipt. There is no proof. There is just a promise. And for millions of workers across Lagos, Nairobi, Accra, and beyond — that promise is broken every month.\"", style: TextStyle(color: AppTheme.dim, fontSize: 14, height: 1.8, fontStyle: FontStyle.italic)),
                                  SizedBox(height: 10),
                                  Text("— Why inFlow exists", style: TextStyle(color: AppTheme.muted, fontSize: 12, fontFamily: 'monospace')),
                                ],
                              ),
                            ),

                            _buildDivider(),

                            _buildSectionLabel("How It Works"),
                            const Text("Two sides. One stream.", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5, height: 1.3, color: Colors.white)),
                            const SizedBox(height: 10),
                            const Text("Whether you're the one paying or the one earning, the experience takes under 2 minutes to set up.", style: TextStyle(color: AppTheme.dim, fontSize: 15, height: 1.7)),
                            const SizedBox(height: 36),
                            if (isMobile) ...[
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildStoryChip("For Employers / Payers", AppTheme.amber),
                                  const SizedBox(height: 16),
                                  _buildStepCard("1", "Sign in with your email", "No wallet setup. No crypto experience needed. Just your email address.", AppTheme.amber),
                                  _buildStepCard("2", "Set a salary budget", "Enter the total amount and how many days to spread it over. LI.FI zaps it into a yield vault instantly.", AppTheme.amber),
                                  _buildStepCard("3", "Send the payment link", "Copy a secure URL and send it to your employee via WhatsApp. Funds are locked the moment you confirm.", AppTheme.amber),
                                  const SizedBox(height: 32),
                                  _buildStoryChip("For Employees / Earners", AppTheme.green),
                                  const SizedBox(height: 16),
                                  _buildStepCard("1", "Open the payment link", "Your employer sends you a link. Tap it from any device. No app download required.", AppTheme.green),
                                  _buildStepCard("2", "Sign in with your email", "We create a secure wallet for you automatically on Base.", AppTheme.green),
                                  _buildStepCard("3", "Watch your money tick up", "Collect your earned salary plus the vault yield bonus anytime you want via LI.FI Composer.", AppTheme.green),
                                ],
                              ),
                            ] else ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildStoryChip("For Employers / Payers", AppTheme.amber),
                                        const SizedBox(height: 16),
                                        _buildStepCard("1", "Sign in with your email", "No wallet setup. No crypto experience needed. Just your email address.", AppTheme.amber),
                                        _buildStepCard("2", "Set a salary budget", "Enter the total amount and how many days to spread it over. LI.FI zaps it into a yield vault instantly.", AppTheme.amber),
                                        _buildStepCard("3", "Send the payment link", "Copy a secure URL and send it to your employee via WhatsApp. Funds are locked the moment you confirm.", AppTheme.amber),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 24),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildStoryChip("For Employees / Earners", AppTheme.green),
                                        const SizedBox(height: 16),
                                        _buildStepCard("1", "Open the payment link", "Your employer sends you a link. Tap it from any device. No app download required.", AppTheme.green),
                                        _buildStepCard("2", "Sign in with your email", "We create a secure wallet for you automatically on Base.", AppTheme.green),
                                        _buildStepCard("3", "Watch your money tick up", "Collect your earned salary plus the vault yield bonus anytime you want via LI.FI Composer.", AppTheme.green),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            _buildDivider(),

                            _buildSectionLabel("The Technology"),
                            const Text("How we made Web3 invisible.", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5, height: 1.3, color: Colors.white)),
                            const SizedBox(height: 16),
                            RichText(
                              text: const TextSpan(
                                style: TextStyle(color: AppTheme.dim, fontSize: 15, height: 1.8),
                                children: [
                                  TextSpan(text: "The hardest part of building inFlow was not the streaming contract. It was making sure that a first-generation smartphone user in Lagos could use it without knowing they were on a blockchain. That's where "),
                                  TextSpan(text: "LI.FI Earn", style: TextStyle(color: AppTheme.lifi, fontWeight: FontWeight.w700)),
                                  TextSpan(text: " and Base changed everything."),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),

                            if (isMobile) ...[
                              _buildTechCard("🔑", "Email login", "Powered by Privy. We create a secure, non-custodial EVM wallet behind your email address. You own the keys — you just never have to see them."),
                              const SizedBox(height: 12),
                              _buildTechCard("📈", "DeFi Mullet Yield", "LI.FI Composer handles the heavy lifting of routing your idle salary into Morpho and Aave vaults, so you earn APY without touching complex DeFi interfaces."),
                              const SizedBox(height: 12),
                              _buildTechCard("⚡", "Built on Base", "Coinbase's L2 architecture means transactions confirm in under a second for fractions of a penny — fast enough to feel like a normal Web2 app."),
                            ] else ...[
                              Row(
                                children: [
                                  Expanded(child: _buildTechCard("🔑", "Email login", "Powered by Privy. We create a secure, non-custodial EVM wallet behind your email address. You own the keys — you just never have to see them.")),
                                  const SizedBox(width: 12),
                                  Expanded(child: _buildTechCard("📈", "DeFi Mullet Yield", "LI.FI Composer handles the heavy lifting of routing your idle salary into Morpho and Aave vaults, so you earn APY without touching complex DeFi interfaces.")),
                                  const SizedBox(width: 12),
                                  Expanded(child: _buildTechCard("⚡", "Built on Base", "Coinbase's L2 architecture means transactions confirm in under a second for fractions of a penny — fast enough to feel like a normal Web2 app.")),
                                ],
                              ),
                            ],

                            const SizedBox(height: 28),
                            Container(
                              padding: const EdgeInsets.all(22),
                              decoration: BoxDecoration(color: const Color(0xFF0D1812), border: Border.all(color: AppTheme.green.withOpacity(0.25)), borderRadius: BorderRadius.circular(14)),
                              child: Row(
                                children: [
                                  const Text("🌍", style: TextStyle(fontSize: 24)),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: RichText(
                                      text: const TextSpan(
                                        style: TextStyle(color: AppTheme.dim, fontSize: 14, height: 1.65),
                                        children: [
                                          TextSpan(text: "The blockchain is entirely invisible. The trust is entirely real. ", style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.w600)),
                                          TextSpan(text: "A Lagos freelancer, a Nairobi contractor, a remote worker anywhere in Africa — anyone with a smartphone and an email address can use inFlow today."),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            _buildDivider(),
                            
                            // --- Try It Free ---
                            _buildSectionLabel("Try It Free"),
                            const Text("Free USDC to get started.", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5, height: 1.3, color: Colors.white)),
                            const SizedBox(height: 12),
                            const Text("We know asking someone to commit real money to a new app they don't fully understand yet is a big ask. So we don't. Every new user receives a free airdrop of \$0.02 USDC (with the transaction gas covered invisibly by our Treasury) — enough to create a full salary stream and experience inFlow exactly as it was meant to be used.", style: TextStyle(color: AppTheme.dim, fontSize: 15, height: 1.7)),
                            const SizedBox(height: 32),
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.border)),
                              child: Column(
                                children: [
                                  const Text("🎁", style: TextStyle(fontSize: 42)),
                                  const SizedBox(height: 16),
                                  const Text("The Stealth Drop", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                                  const SizedBox(height: 8),
                                  const Text("When you sign in for the first time, our backend silently detects a new wallet and automatically funds it. No claiming, no waiting.", textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
                                  const SizedBox(height: 24),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text("Sign In & Get Funded →", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),

                            _buildDivider(),

                            Column(
                              children: [
                                _buildSectionLabel("Our Mission"),
                                const Text("Revolutionising how Africa gets paid.", textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -1, height: 1.2, color: Colors.white)),
                                const SizedBox(height: 24),
                                const Text("Africa has the world's fastest-growing workforce and some of its most vibrant freelance and remote work ecosystems. What it has lacked is infrastructure that treats workers as the first-class citizens they are — not as creditors extending zero-interest loans to their employers every month.\n\ninFlow is built on the belief that money should move at the speed of work. Not the speed of bureaucracy, not the speed of bank clearing houses — the speed of the second you finish that task, write that line of code, or close that support ticket.", textAlign: TextAlign.center, style: TextStyle(color: AppTheme.dim, fontSize: 16, height: 1.85)),
                                const SizedBox(height: 32),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                                  decoration: BoxDecoration(color: AppTheme.amber.withOpacity(0.1), border: Border.all(color: AppTheme.amber.withOpacity(0.3)), borderRadius: BorderRadius.circular(16)),
                                  child: const Text("Your labour is not a loan. It's yours the moment you do it.", textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppTheme.amber, letterSpacing: -0.3)),
                                ),
                              ],
                            ),

                            _buildDivider(),

                            _buildSectionLabel("FAQ"),
                            const Text("Common questions.", style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: -0.5, height: 1.3, color: Colors.white)),
                            const SizedBox(height: 32),
                            ...faqs.map((f) => _FAQItemStory(q: f["q"]!, a: f["a"]!)),

                            _buildDivider(),

                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 52, horizontal: 36),
                              decoration: BoxDecoration(color: AppTheme.cardBg, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(24)),
                              child: Column(
                                children: [
                                  Container(width: 200, height: 1, color: AppTheme.amber),
                                  const SizedBox(height: 24),
                                  const Text("⚡", style: TextStyle(fontSize: 32)),
                                  const SizedBox(height: 16),
                                  const Text("Ready to get paid by the second?", textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: -0.5, height: 1.3, color: Colors.white)),
                                  const SizedBox(height: 14),
                                  const Text("Sign up in under a minute. No wallet. No crypto experience. Just your email.\nNew users get free USDC automatically.", textAlign: TextAlign.center, style: TextStyle(color: AppTheme.dim, fontSize: 14, height: 1.7)),
                                  const SizedBox(height: 28),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.amber, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text("Try inFlow Now →", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text("Live on Base Mainnet", style: TextStyle(color: AppTheme.muted, fontSize: 11, fontFamily: 'monospace')),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1), border: Border.all(color: color.withOpacity(0.3)), borderRadius: BorderRadius.circular(20)),
      child: Text(text.toUpperCase(), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0, fontFamily: 'monospace')),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: AppTheme.muted, fontFamily: 'monospace')));
  }

  Widget _buildDivider() {
    return Container(height: 1, color: AppTheme.border, margin: const EdgeInsets.symmetric(vertical: 72));
  }

  Widget _buildStepCard(String n, String title, String body, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 24),
      decoration: BoxDecoration(color: AppTheme.cardBg, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(16)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withOpacity(0.1), border: Border.all(color: color.withOpacity(0.3)), shape: BoxShape.circle),
            child: Center(child: Text(n, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'monospace'))),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
                const SizedBox(height: 5),
                Text(body, style: const TextStyle(color: AppTheme.dim, fontSize: 13, height: 1.65)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String value, String label, String source) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      decoration: BoxDecoration(color: AppTheme.cardBg, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: AppTheme.amber, fontFamily: 'monospace', letterSpacing: -1)),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: AppTheme.text, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(source, style: const TextStyle(color: AppTheme.muted, fontSize: 11, fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _buildTechCard(String icon, String title, String body) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.cardBg, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(color: AppTheme.dim, fontSize: 13, height: 1.65)),
        ],
      ),
    );
  }
}

class _LiveTickerStory extends StatefulWidget {
  const _LiveTickerStory();
  @override State<_LiveTickerStory> createState() => _LiveTickerStoryState();
}

class _LiveTickerStoryState extends State<_LiveTickerStory> {
  double val = 0.000000;
  late Timer timer;
  @override void initState() { super.initState(); timer = Timer.periodic(const Duration(seconds: 1), (t) { if (mounted) setState(() => val += 0.00002893); }); }
  @override void dispose() { timer.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 18),
      decoration: BoxDecoration(color: AppTheme.green.withOpacity(0.1), border: Border.all(color: AppTheme.green.withOpacity(0.25)), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic,
        children: [
          const Text("You've earned ", style: TextStyle(color: AppTheme.muted, fontSize: 13, fontFamily: 'monospace')),
          Text("\$${val.toStringAsFixed(6)} ", style: const TextStyle(color: AppTheme.green, fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'monospace', letterSpacing: -0.5)),
          const Text("since opening this page", style: TextStyle(color: AppTheme.muted, fontSize: 11, fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

class _FAQItemStory extends StatefulWidget {
  final String q;
  final String a;
  const _FAQItemStory({required this.q, required this.a});
  @override State<_FAQItemStory> createState() => _FAQItemStoryState();
}

class _FAQItemStoryState extends State<_FAQItemStory> {
  bool open = false;
  @override Widget build(BuildContext context) {
    return InkWell(
      onTap: () => setState(() => open = !open),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: Text(widget.q, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: AppTheme.text, height: 1.5))),
                AnimatedRotation(
                  turns: open ? 0.125 : 0, duration: const Duration(milliseconds: 200),
                  child: Container(
                    width: 26, height: 26,
                    decoration: BoxDecoration(color: AppTheme.amber.withOpacity(0.1), border: Border.all(color: AppTheme.amber.withOpacity(0.3)), shape: BoxShape.circle),
                    child: const Center(child: Text("+", style: TextStyle(color: AppTheme.amber, fontSize: 16, fontWeight: FontWeight.bold))),
                  ),
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: Padding(padding: const EdgeInsets.only(top: 14), child: Text(widget.a, style: const TextStyle(color: AppTheme.dim, fontSize: 14, height: 1.7))),
              crossFadeState: open ? CrossFadeState.showSecond : CrossFadeState.showFirst, duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }
}