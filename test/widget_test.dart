// WebViewScreen can't be widget-tested here: WebViewPlatform.instance is
// only registered on a real device/emulator, not in the plain widget-test
// environment. The customer flow itself (signup, booking, job list) lives
// on the website this wrapper loads, so it's covered by the web app's own
// checks — this just confirms the wrapper points at the right place.

import 'package:flutter_test/flutter_test.dart';
import 'package:shoppulse_customer/config/app_config.dart';

void main() {
  test('AppConfig.customerAppUrl defaults to the production customer app', () {
    expect(AppConfig.customerAppUrl, 'https://shoppulse-web.vercel.app/customer');
  });
}
