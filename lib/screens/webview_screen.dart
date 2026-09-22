import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../config/app_config.dart';

/// The entire app: a full-screen WebView loading the web-based customer
/// portal. Unlike the technician app, customers don't need background GPS
/// tracking, but two bridges are still needed: photo uploads (booking
/// request photo, job review photo) — a bare WebView with no
/// setOnShowFileSelector silently does nothing when a file input is
/// tapped — and one-shot geolocation for the "use my current location"
/// button on the address pin picker, which WebView also refuses to grant
/// without an explicit native prompt callback.
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
    _primeLocationPermission();
    _controller = _buildController();
  }

  Future<void> _primeLocationPermission() async {
    // Android must hold the OS-level permission before the WebView's JS
    // geolocation calls can succeed, regardless of what the in-page
    // permission prompt callback below allows.
    try {
      if (await Geolocator.isLocationServiceEnabled()) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          await Geolocator.requestPermission();
        }
      }
    } catch (_) {
      // Non-fatal: the page's own "use my location" button will surface
      // a clear error if location still isn't available when it's
      // actually needed.
    }
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
          onWebResourceError: (error) {
            // Android reports errors for ANY failed resource on the page —
            // a flaky image, a blocked analytics ping, a slow sub-request —
            // not just the main document. Treating every one of those as a
            // fatal "Could not load ShopPulse" was hiding a perfectly
            // working page behind an error screen on good connections.
            // Only the main-frame navigation failing is actually fatal.
            if (error.isForMainFrame == false) return;
            setState(() {
              _loading = false;
              _error = error.description;
            });
          },
        ),
      )
      ..addJavaScriptChannel(
        'ShopPulseNative',
        onMessageReceived: _handleNativeBridgeMessage,
      );

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform.setGeolocationPermissionsPromptCallbacks(
        onShowPrompt: (request) async {
          return const GeolocationPermissionsResponse(allow: true, retain: true);
        },
      );

      platform.setOnShowFileSelector((params) async {
        final source = await showModalBottomSheet<ImageSource>(
          context: context,
          builder: (sheetContext) => SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Take Photo'),
                  onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library),
                  title: const Text('Choose from Gallery'),
                  onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
        if (source == null) return [];

        final picker = ImagePicker();
        final photo = await picker.pickImage(
          source: source,
          imageQuality: 80,
          maxWidth: 1280,
        );
        if (photo == null) return [];
        return ['file://${photo.path}'];
      });
    }

    controller.clearCache().then((_) {
      controller.loadRequest(Uri.parse(AppConfig.customerAppUrl));
    });

    return controller;
  }

  /// Messages from the web page (see the `ShopPulseNative` check in
  /// src/lib/invoice/renderInvoicePng.ts on the web side), routed to
  /// whatever native capability the page can't reach on its own.
  void _handleNativeBridgeMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      switch (data['type']) {
        case 'downloadFile':
          _downloadFile(data['filename'] as String, data['dataUrl'] as String);
          break;
      }
    } catch (_) {
      // Malformed bridge message — ignore rather than crash the WebView.
    }
  }

  /// A generated file (currently just the invoice/receipt PNG) has no
  /// meaningful "download folder" inside a WebView the way it would in a
  /// real browser — the OS share sheet lets the customer save it wherever
  /// they want (Files, Photos, a chat app) without needing storage
  /// permissions, since the file only ever lives in the app's own cache.
  Future<void> _downloadFile(String filename, String dataUrl) async {
    try {
      final commaIndex = dataUrl.indexOf(',');
      if (commaIndex == -1) return;
      final bytes = base64Decode(dataUrl.substring(commaIndex + 1));

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles([XFile(file.path)], text: filename);
    } catch (_) {
      // Non-fatal: worst case the customer just doesn't get the share
      // sheet and can retry the download button.
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _loading = true;
    });
    _controller.clearCache().then((_) => _controller.reload());
  }

  /// The system/gesture back button has nothing to pop in Flutter's own
  /// navigator — this is a single-screen app — so without this it always
  /// falls straight through to closing the app. Customers expect it to step
  /// back to the page's natural parent instead (e.g. off the booking form
  /// back to the dashboard) the same way a browser's back button would.
  ///
  /// Prefers asking the current page itself first, via the same
  /// `__shopPulseSmartBack` handler its own "← Back" button uses (see
  /// useSmartBack.ts on the web side) — the WebView's own back-history
  /// (`canGoBack`/`goBack`) is NOT a reliable fallback signal here on its
  /// own: it can report history with nothing meaningful behind it (e.g.
  /// after the periodic background-reload elsewhere in this file resets
  /// it), which is the same reason the web side abandoned router.back()
  /// for a fixed-destination handler. Only a page with no such handler
  /// registered (i.e. the dashboard root) falls through to WebView
  /// history, and finally to closing the app.
  Future<void> _handleBackButton(bool didPop, Object? result) async {
    if (didPop) return;

    try {
      final hasHandler = await _controller.runJavaScriptReturningResult(
        "typeof window.__shopPulseSmartBack === 'function'",
      );
      if (hasHandler == true) {
        await _controller.runJavaScript('window.__shopPulseSmartBack()');
        return;
      }
    } catch (_) {
      // JS bridge unavailable (e.g. page still loading) — fall through.
    }

    if (await _controller.canGoBack()) {
      _controller.goBack();
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleBackButton,
      child: Scaffold(
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
      ),
    );
  }
}
