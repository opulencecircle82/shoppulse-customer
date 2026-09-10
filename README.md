# ShopPulse Customer (Flutter) — Customer App WebView Wrapper

Same pattern as `shoppulse-mobile` (the technician app), but simpler: this
wrapper needs **no native bridging at all**. Customers only sign up, book
jobs, and view proof/status — nothing here needs camera or background GPS
access, so it's just a full-screen `WebView` loading the web-based
customer portal at `shoppulse-web/src/app/customer/`.

Because the real logic lives on the website, shipping a new feature or
bug fix there reaches every customer on their next page load — no new
APK, no reinstall. This wrapper only needs rebuilding if the wrapper
itself changes (app icon, splash behavior).

## What's here

```
lib/
  config/app_config.dart      AppConfig.customerAppUrl — the page this wrapper loads
  screens/webview_screen.dart The entire UI: a full-screen WebView with
                               loading/error states
  main.dart                   App entry point
```

## 1. Install dependencies

```bash
flutter pub get
```

## 2. Run it

```bash
flutter run
```

## 3. Build a release APK

```bash
./scripts/build_release.sh
```

Builds `build/app/outputs/flutter-apk/app-release.apk`. Publish it to the
GitHub release the web dashboard's "Download App" (customer) button
points at.

## Known gaps

- iOS isn't wired up (Android platform only was generated).
- No push notifications for booking status changes.
