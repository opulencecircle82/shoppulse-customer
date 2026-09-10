#!/usr/bin/env bash
# Builds the release APK. No credentials to bake in — this wrapper just
# loads AppConfig.customerAppUrl (see lib/config/app_config.dart), which
# defaults to production. Pass --dart-define=CUSTOMER_APP_URL=... only to
# point at a different deployment (e.g. a preview URL) for testing.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter build apk --release

echo "Built build/app/outputs/flutter-apk/app-release.apk"
