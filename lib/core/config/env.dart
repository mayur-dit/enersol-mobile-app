/// Backend configuration.
///
/// Mirrors `enersol-admin-fe/src/environments/environment.ts` so the mobile app
/// talks to exactly the same API Maker instance as the admin panel.
class Env {
  const Env._();

  /// API Maker backend origin.
  static const String apiHost = 'https://gbs.dev.be.savaapi.com';

  /// API Maker's WebSocket gateway — the same socket the admin panel and the
  /// engineer PWA listen on (`WS_HOST` in the Angular environment files).
  ///
  /// A SEPARATE HOST, not `apiHost` with the scheme swapped: the platform
  /// serves the socket from its own `*.ws.*` origin, so deriving it from the
  /// API origin would connect to nothing. It pairs with [apiHost] — change the
  /// two together or the app will authenticate against one backend and try to
  /// receive its notifications from another.
  static const String wsHost = 'wss://gbs.dev.ws.savaapi.com';

  /// The `{USER_PATH}` segment present in every custom-API URL.
  static const String userPath = 'enersol';

  /// Database instance + name (schema CRUD routes are scoped by neither, but
  /// they are kept here to mirror the admin config).
  static const String instance = 'mongodb';
  static const String database = 'enersol_db';

  /// Only a CUSTOMER may sign in to this app. Staff and vendors use the web
  /// admin panel — see [AuthService.login], which rejects anything else.
  static const String allowedUserType = 'CUSTOMER';

  static const String companyName = 'Enersol';
  static const String developerName = 'SAVA Info Systems Pvt. Ltd.';
}
