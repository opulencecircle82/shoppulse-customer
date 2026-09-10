import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../config/app_config.dart';

/// The entire app: a full-screen WebView loading the web-based customer
/// portal. Unlike the technician app, customers don't need camera or
/// background GPS access — just booking and viewing job status/proof —
/// so this wrapper needs no native bridging at all.
class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

// Below this, a brief background/resume round-trip (e.g. switching to
// pick a photo, a notification shade swipe) does NOT trigger a reload —
// only genuinely leaving the app for a while does. This keeps the "always
// show the latest version" fix from being disruptive on quick app
// switches, and (for the technician app, which shares this file) avoids
// wiping in-progress form state that a naive reload-on-every-resume
// would cause.
const _reloadAfterBackgroundDuration = Duration(minutes: 2);

class _WebViewScreenState extends State<WebViewScreen> with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _loading = true;
  String? _error;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = _buildController();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _pausedAt ??= DateTime.now();
      return;
    }

    if (state != AppLifecycleState.resumed) return;

    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt != null &&
        DateTime.now().difference(pausedAt) > _reloadAfterBackgroundDuration) {
      // Android's WebView keeps its own disk HTTP cache that survives app
      // restarts, so a plain reload() can still re-serve a stale page after
      // a new deploy — clear it first so "resume after a while" always
      // fetches the current site.
      _controller.clearCache().then((_) => _controller.reload());
    }
  }

  WebViewController _buildController() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFF8FAFC))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() {
            _loading = true;
            _error = null;
          }),
          onPageFinished: (_) => setState(() => _loading = false),
          onWebResourceError: (error) => setState(() {
            _loading = false;
            _error = error.description;
          }),
        ),
      );

    controller.clearCache().then((_) {
      controller.loadRequest(Uri.parse(AppConfig.customerAppUrl));
    });

    return controller;
  }

  void _retry() {
    setState(() {
      _error = null;
      _loading = true;
    });
    _controller.clearCache().then((_) => _controller.reload());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Stack(
          children: [
            if (_error == null) WebViewWidget(controller: _controller),
            if (_loading && _error == null)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF2563EB)),
              ),
            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Could not load ShopPulse',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _retry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
