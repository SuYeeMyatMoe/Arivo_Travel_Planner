/// Build-time configuration. Only public values live in the app — every secret stays on the backend.
///
///   flutter run --dart-define=ARIVO_API=https://api.arivo.app --dart-define=ARIVO_DEV_USER=
abstract final class ArivoConfig {
  static const apiBase = String.fromEnvironment('ARIVO_API', defaultValue: 'http://localhost:8787');

  /// Local/dev only: the backend accepts `Authorization: Dev <id>` when ALLOW_DEV_AUTH=true (refused in production).
  static const devUser = String.fromEnvironment('ARIVO_DEV_USER', defaultValue: 'demo-traveller');

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY'); // public by design (RLS protects data)
  static const stripePublishableKey = String.fromEnvironment('STRIPE_PUBLISHABLE_KEY'); // pk_… only, never sk_

  static const mapStylePaper = 'https://tiles.openfreemap.org/styles/positron';
  static const mapStyleInk = 'https://tiles.openfreemap.org/styles/dark';
}
