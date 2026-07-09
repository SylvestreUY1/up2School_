import 'dart:io';

/**
 * FICHIER : app_config.dart
 * RÔLE : Le centre de contrôle de l'application.
 * C'est ici qu'on définit les adresses des serveurs et qu'on adapte le comportement
 * de l'application selon qu'elle tourne sur un téléphone (Android/iPhone) ou un ordinateur.
 */
class AppConfig {
  // L'identifiant de notre projet chez Google (Firebase)
  static const String firebaseProjectId = 'up2school-app';

  /// --- LES ADRESSES DES SERVEURS ---

  // L'adresse de notre serveur en ligne (Production)
  static const String productionBackendUrl =
      'https://up2school-api.onrender.com';
  static const String productionWebSocketUrl =
      'wss://up2school-api.onrender.com';

  // L'adresse pour les tests sur son propre ordinateur (Développement)
  static const String desktopLocalBackendUrl = 'http://localhost:3000';
  static const String desktopLocalWebSocketUrl = 'ws://localhost:3000';

  // Variables pour changer d'adresse facilement sans toucher au code
  static const String environmentBackendUrl = String.fromEnvironment(
    'UP2SCHOOL_BACKEND_URL',
    defaultValue: '',
  );
  static const String environmentWebSocketUrl = String.fromEnvironment(
    'UP2SCHOOL_WEBSOCKET_URL',
    defaultValue: '',
  );
  static const bool useLocalDesktopBackend = bool.fromEnvironment(
    'UP2SCHOOL_USE_LOCAL_BACKEND',
    defaultValue: false,
  );
  static const String googleWebClientId = String.fromEnvironment(
    'UP2SCHOOL_GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '846269435063-cbsj8fhcou2ojhsgspni5o5c1b3n047n.apps.googleusercontent.com',
  );

  /// --- LES TESTS DE PLATEFORME ---

  // Est-ce qu'on est sur un téléphone ?
  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  // Est-ce qu'on est sur un appareil Apple (iPhone, Mac) ?
  static bool get isApplePlatform => Platform.isIOS || Platform.isMacOS;

  // Est-ce qu'on est sur un ordinateur (Windows, Linux, Mac) ?
  static bool get isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  /// --- LES RÈGLES DE FONCTIONNEMENT ---

  // Sur téléphone, on utilise Firebase directement pour certaines données.
  // Sur Desktop, on garde le backend comme source principale.
  static bool get useFirebaseDataLayer => Platform.isAndroid || Platform.isIOS;

  // Désormais, on passe par notre propre serveur pour les annonces
  static bool get useFirebaseAds => false;

  // On utilise notre serveur (Backend) pour presque tout
  static bool get useBackendDataApi => true;
  static bool get useBackendStorage => true;
  static bool get useBackendNotificationState => true;

  // Sur ordinateur, on a obligatoirement besoin du serveur (car pas de Firebase complet)
  static bool get useIntermediateBackend => isDesktop;
  static bool get useBackendForProtectedFiles => useBackendStorage;

  // Certaines plateformes ont besoin que Firebase soit allumé au démarrage
  // Note: Firebase Core n'a pas de plugin natif pour Linux/Windows, donc on l'initialise
  // uniquement sur mobile et macOS
  static bool get requiresFirebaseInitialization =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS;

  // Est-ce qu'on peut recevoir des messages Firebase ?
  static bool get usesFirebaseMessaging =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  // Est-ce qu'on utilise le système de push spécifique à Apple ?
  static bool get usesApplePushNotifications =>
      Platform.isIOS || Platform.isMacOS;

  /// RÉCUPÉRER LA BONNE ADRESSE DU SERVEUR
  static String get backendUrl {
    if (environmentBackendUrl.isNotEmpty) {
      return environmentBackendUrl;
    }
    if (isDesktop && useLocalDesktopBackend) {
      return desktopLocalBackendUrl;
    }
    return productionBackendUrl;
  }

  /// RÉCUPÉRER L'ADRESSE POUR LES MESSAGES EN DIRECT (Websocket)
  static String get webSocketUrl {
    if (environmentWebSocketUrl.isNotEmpty) {
      return environmentWebSocketUrl;
    }
    if (isDesktop && useLocalDesktopBackend) {
      return desktopLocalWebSocketUrl;
    }
    return productionWebSocketUrl;
  }

  // Petit texte qui indique dans quel mode on est
  static String get backendModeLabel {
    if (environmentBackendUrl.isNotEmpty) {
      return 'custom';
    }
    if (isDesktop && useLocalDesktopBackend) {
      return 'desktop-local';
    }
    return 'production';
  }

  // Nom de la plateforme pour afficher dans les logs (journaux)
  static String get platformName {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isMacOS) return 'macOS';
    return 'Inconnue';
  }

  /// CHOISIR COMMENT RECEVOIR LES NOTIFICATIONS
  static NotificationStrategy get notificationStrategy {
    if (usesApplePushNotifications) return NotificationStrategy.apns;
    if (Platform.isAndroid) return NotificationStrategy.fcm;
    if (Platform.isWindows) return NotificationStrategy.polling;
    if (Platform.isLinux) return NotificationStrategy.websocket;
    return NotificationStrategy.polling;
  }
}

/**
 * LISTE DES FAÇONS DE RECEVOIR UNE ALERTE
 */
enum NotificationStrategy {
  /// Le service d'Apple (iOS, macOS)
  apns,

  /// Le service de Google (Android)
  fcm,

  /// Demander au serveur régulièrement (Windows, Linux)
  polling,

  /// Rester connecté en permanence (Linux)
  websocket,
}
