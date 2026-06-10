import 'package:flutter/material.dart';

class AppConstants {
  // Couleurs de l'application
  static const Color backgroundColor = Color(0xFF307A59);
  static const Color primaryColor = Color(0xFF307A59);
  static const Color lightPrimaryColor = Color(0xFF2E9366);
  static const Color secondaryColor = Color(0xFF42A5F5);
  static const Color accentColor = Color(0xFF00BCD4);
  static const Color successColor = Color(0xFF4CAF50);
  static const Color warningColor = Color(0xFFFF9800);
  static const Color errorColor = Color(0xFFFF6C6C);
  static const Color greyColor = Color(0xFF9E9E9E);
  static const Color lightGreyColor = Color(0xFFF5F5F5);
  static const Color darkGreyColor = Color(0xFF616161);

  // Textes
  static const String appName = 'University Files';
  static const String appSlogan = 'Partage de ressources universitaires';

  // URLs
  static const String privacyPolicyUrl = 'https://votre-site.com/privacy';
  static const String termsOfServiceUrl = 'https://votre-site.com/terms';

  // Chemins de stockage
  static const String downloadsFolder = 'UniversityFiles';

  // Taille des fichiers
  static const int maxFileSize = 50 * 1024 * 1024; // 50MB
  static const List<String> allowedFileTypes = [
    'pdf',
    'doc',
    'docx',
    'ppt',
    'pptx',
    'xls',
    'xlsx',
    'txt'
  ];

  // Messages d'erreur
  static const String networkError =
      'Connexion indisponible. Vérifiez Internet puis réessayez.';
  static const String authError =
      'Votre session n’est plus valide. Reconnectez-vous.';
  static const String storageError =
      'Le fichier n’a pas pu être traité. Réessayez.';
  static const String unknownError =
      'Une action n’a pas pu être terminée. Réessayez.';

  // Formats de date
  static const String dateFormat = 'dd/MM/yyyy';
  static const String dateTimeFormat = 'dd/MM/yyyy HH:mm';
  static const String timeFormat = 'HH:mm';

  // Tailles
  static const double defaultPadding = 16.0;
  static const double defaultRadius = 8.0;
  static const double defaultIconSize = 24.0;
}

class FirebaseConstants {
  // Collections Firestore
  static const String usersCollection = 'users';
  static const String filesCollection = 'files';
  static const String eventsCollection = 'events';
  static const String facultiesCollection = 'faculties';
  static const String favoritesCollection = 'favorites';

  // Storage paths
  static const String filesStoragePath = 'files';
  static const String thumbnailsStoragePath = 'thumbnails';
  static const String avatarsStoragePath = 'avatars';

  // User roles
  static const String roleGuest = 'guest';
  static const String roleStudent = 'student';
  static const String roleDelegate = 'delegate';
  static const String roleAdmin = 'admin';
}

class RouteConstants {
  static const String home = '/';
  static const String login = '/login';
  static const String register = '/register';
  static const String profile = '/profile';
  static const String files = '/files';
  static const String events = '/events';
  static const String admin = '/admin';
  static const String delegates = '/delegates';
  static const String fileViewer = '/file-viewer';
}
