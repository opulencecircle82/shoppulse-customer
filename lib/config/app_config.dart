class AppConfig {
  /// The web-based customer app this wrapper loads. Overridable via
  /// --dart-define=CUSTOMER_APP_URL=... for testing against a different
  /// deployment; defaults to production.
  static const String customerAppUrl = String.fromEnvironment(
    'CUSTOMER_APP_URL',
    defaultValue: 'https://shoppulse-web.vercel.app/customer',
  );
}
