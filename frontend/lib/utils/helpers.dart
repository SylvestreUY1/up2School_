import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'constants.dart';
import '../l10n/app_localizations.dart';

class AppHelpers {
  /// Récupère la locale active de l'application.
  ///
  /// On s'appuie sur `Intl.defaultLocale` afin que les formateurs suivent
  /// automatiquement la langue système résolue au niveau racine.
  static String get _activeLocale => Intl.getCurrentLocale();
  static bool get _isFrenchLocale =>
      _activeLocale.toLowerCase().startsWith('fr');

  static String userFriendlyErrorMessage(
    Object? error, {
    String? fallback,
  }) {
    final raw =
        (error?.toString() ?? '').replaceFirst('Exception: ', '').trim();
    final normalized = raw.toLowerCase();

    String defaultMessage() =>
        fallback ??
        (_isFrenchLocale
            ? 'Une action n’a pas pu être terminée. Réessayez dans un instant.'
            : 'This action could not be completed. Please try again.');

    if (normalized.isEmpty) {
      return defaultMessage();
    }

    if (normalized.contains('network') ||
        normalized.contains('socket') ||
        normalized.contains('connection') ||
        normalized.contains('connexion') ||
        normalized.contains('timeout') ||
        normalized.contains('timed out') ||
        normalized.contains('internet')) {
      return _isFrenchLocale
          ? 'Connexion indisponible. Vérifiez Internet puis réessayez.'
          : 'Connection unavailable. Check your internet and try again.';
    }

    if (normalized.contains('invalid_login_credentials') ||
        normalized.contains('invalid_password') ||
        normalized.contains('invalid-credential') ||
        normalized.contains('wrong-password') ||
        normalized.contains('mot de passe incorrect') ||
        normalized.contains('user-not-found') ||
        normalized.contains('email_not_found') ||
        normalized.contains('aucun utilisateur') ||
        normalized.contains('supplied auth credential')) {
      return _isFrenchLocale
          ? 'Email ou mot de passe incorrect.'
          : 'Incorrect email or password.';
    }

    if (normalized.contains('401') ||
        normalized.contains('token') ||
        normalized.contains('session') ||
        normalized.contains('unauthorized')) {
      return _isFrenchLocale
          ? 'Votre session a expiré. Reconnectez-vous puis réessayez.'
          : 'Your session has expired. Sign in again and try again.';
    }

    if (normalized.contains('permission') ||
        normalized.contains('refused') ||
        normalized.contains('denied') ||
        normalized.contains('refus')) {
      return _isFrenchLocale
          ? 'Cette action n’est pas autorisée sur votre appareil.'
          : 'This action is not allowed on your device.';
    }

    if (normalized.contains('not found') ||
        normalized.contains('introuvable') ||
        normalized.contains('inaccessible')) {
      return _isFrenchLocale
          ? 'Élément introuvable. Actualisez la page puis réessayez.'
          : 'Item not found. Refresh the page and try again.';
    }

    if (normalized.contains('storage') ||
        normalized.contains('upload') ||
        normalized.contains('download') ||
        normalized.contains('fichier')) {
      return fallback ??
          (_isFrenchLocale
              ? 'Le fichier n’a pas pu être traité. Réessayez.'
              : 'The file could not be processed. Please try again.');
    }

    return fallback ?? raw;
  }

  // Formatteur de date
  static String formatDate(DateTime date, {String format = 'dd/MM/yyyy'}) {
    return DateFormat(format, _activeLocale).format(date);
  }

  static String formatDateTime(DateTime date) {
    return DateFormat(AppConstants.dateTimeFormat, _activeLocale).format(date);
  }

  // Formatteur de taille de fichier
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // Obtenir l'icône selon le type de fichier
  static IconData getFileIcon(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'txt':
        return Icons.text_fields;
      case 'zip':
      case 'rar':
        return Icons.archive;
      default:
        return Icons.insert_drive_file;
    }
  }

  // Obtenir la couleur selon le type de fichier
  static Color getFileColor(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'ppt':
      case 'pptx':
        return Colors.orange;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'txt':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  // Valider un email
  static bool isValidEmail(String email) {
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailRegex.hasMatch(email);
  }

  // Valider un mot de passe
  static bool isValidPassword(String password) {
    return password.length >= 6;
  }

  static String getUserInitial(String? name, String? email,
      {String fallback = '?'}) {
    final normalizedName = name?.trim() ?? '';
    if (normalizedName.isNotEmpty) {
      return normalizedName.substring(0, 1).toUpperCase();
    }

    final normalizedEmail = email?.trim() ?? '';
    if (normalizedEmail.isNotEmpty) {
      return normalizedEmail.substring(0, 1).toUpperCase();
    }

    return fallback;
  }

  // Ouvrir une URL
  static Future<void> openUrl(String url, {BuildContext? context}) async {
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } else {
      if (context != null) {
        throw context.l10n.openUrlError(url);
      }
      throw _isFrenchLocale
          ? 'Impossible d’ouvrir l’URL : $url'
          : 'Unable to open URL: $url';
    }
  }

  // Télécharger un fichier
  static Future<File?> downloadFile(String url, String fileName) async {
    try {
      // Demander la permission de stockage
      if (Platform.isAndroid || Platform.isIOS) {
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          return null;
        }
      }

      // Créer le répertoire de téléchargement
      final directory = await getApplicationDocumentsDirectory();
      final downloadDir =
          Directory('${directory.path}/${AppConstants.downloadsFolder}');

      if (!await downloadDir.exists()) {
        await downloadDir.create(recursive: true);
      }

      // Télécharger le fichier
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();

      final filePath = '${downloadDir.path}/$fileName';
      final file = File(filePath);

      await response.pipe(file.openWrite());

      return file;
    } catch (e) {
      print('Erreur de téléchargement: $e');
      return null;
    }
  }

  // Afficher un snackbar
  static void showSnackBar(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? AppConstants.errorColor : AppConstants.successColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // Afficher un dialog de confirmation
  static Future<bool> showConfirmationDialog(
    BuildContext context,
    String title,
    String message,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              context.l10n.cancel,
              style: const TextStyle(color: Color(0xFF307A59)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.l10n.confirm,
              style: const TextStyle(color: Color(0xFFFF6C6C)),
            ),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  // Formater la durée restante
  static String formatRemainingTime(DateTime date, {BuildContext? context}) {
    final now = DateTime.now();
    final difference = date.difference(now);
    final l10n = context != null ? context.l10n : null;

    if (difference.isNegative) {
      return l10n?.past ?? (_isFrenchLocale ? 'Passé' : 'Past');
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).toStringAsFixed(0);
      return l10n?.inMonths(int.parse(months)) ??
          (_isFrenchLocale ? 'Dans $months mois' : 'In $months months');
    } else if (difference.inDays > 0) {
      return l10n?.inDays(difference.inDays) ??
          (_isFrenchLocale
              ? 'Dans ${difference.inDays} jours'
              : 'In ${difference.inDays} days');
    } else if (difference.inHours > 0) {
      return l10n?.inHours(difference.inHours) ??
          (_isFrenchLocale
              ? 'Dans ${difference.inHours} heures'
              : 'In ${difference.inHours} hours');
    } else if (difference.inMinutes > 0) {
      return l10n?.inMinutes(difference.inMinutes) ??
          (_isFrenchLocale
              ? 'Dans ${difference.inMinutes} minutes'
              : 'In ${difference.inMinutes} minutes');
    } else {
      return l10n?.now ?? (_isFrenchLocale ? 'Maintenant' : 'Now');
    }
  }

  // Générer une couleur stable par utilisateur (pour les avatars)
  static Color getRandomColor(String seed) {
    const avatarColors = [
      Color(0xFF2E9366),
      Color(0xFF42A5F5),
      Color(0xFF00BCD4),
      Color(0xFF4CAF50),
      Color(0xFFFF9800),
      Color(0xFFFF6C6C),
      Color(0xFF7E57C2),
      Color(0xFF26A69A),
      Color(0xFFEC407A),
      Color(0xFF5C6BC0),
    ];
    final normalizedSeed = seed.trim().toLowerCase();
    final index = simpleHash(
          normalizedSeed.isEmpty ? 'default-avatar' : normalizedSeed,
        ).abs() %
        avatarColors.length;
    return avatarColors[index];
  }

  // Extraire l'extension d'un fichier
  static String getFileExtension(String fileName) {
    final parts = fileName.split('.');
    return parts.isNotEmpty ? parts.last.toLowerCase() : '';
  }

  // Vérifier si un fichier est d'un type autorisé
  static bool isAllowedFileType(String fileName) {
    final extension = getFileExtension(fileName);
    return AppConstants.allowedFileTypes.contains(extension);
  }

  // ========== NOUVELLES MÉTHODES AJOUTÉES ==========

  // Tester la connexion Firebase
  static Future<bool> testFirebaseConnection() async {
    try {
      final firestore = FirebaseFirestore.instance;
      await firestore.collection('test').limit(1).get();
      return true;
    } catch (e) {
      print('❌ Test Firebase échoué: $e');
      return false;
    }
  }

  // Vérifier si on est en mode développement
  static bool isDevMode() {
    return kDebugMode;
  }

  // Afficher une boîte de dialogue d'information
  static void showInfoDialog(
    BuildContext context,
    String title,
    String message,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.ok),
          ),
        ],
      ),
    );
  }

  // Générer un mot de passe aléatoire
  static String generateRandomPassword({int length = 12}) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*';
    final random = Random.secure();
    return String.fromCharCodes(
      Iterable.generate(
        length,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  // Afficher les logs de débogage
  static void debugLog(String message, {bool isError = false}) {
    if (kDebugMode) {
      final prefix = isError ? '❌ ERREUR' : '✅ INFO';
      print('$prefix: $message');
    }
  }

  // Formater un numéro de téléphone
  static String formatPhoneNumber(String phone) {
    if (phone.length == 10) {
      return '${phone.substring(0, 2)} ${phone.substring(2, 4)} ${phone.substring(4, 6)} ${phone.substring(6, 8)} ${phone.substring(8)}';
    }
    return phone;
  }

  // Capitaliser la première lettre d'une chaîne
  static String capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }

  // Créer un chemin de fichier sécurisé
  static String createSafeFileName(String originalName) {
    final now = DateTime.now();
    final timestamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour}${now.minute}${now.second}';
    final extension = getFileExtension(originalName);
    final baseName = originalName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return '${baseName}_$timestamp.$extension';
  }

  // Vérifier si l'app est en ligne
  static Future<bool> isOnline() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  // Afficher une bannière d'information contextuelle
  static Widget buildInfoBanner({
    required String message,
    IconData icon = Icons.info_outline,
    Color color = Colors.blue,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Convertir des secondes en format lisible
  static String formatSeconds(int seconds, {BuildContext? context}) {
    final l10n = context != null ? context.l10n : null;

    if (seconds < 60) {
      return l10n?.secondsLabel(seconds) ??
          (_isFrenchLocale ? '$seconds secondes' : '$seconds seconds');
    }
    if (seconds < 3600) {
      final minutes = (seconds / 60).toStringAsFixed(0);
      return l10n?.minutesLabel(int.parse(minutes)) ?? '$minutes minutes';
    }
    if (seconds < 86400) {
      final hours = (seconds / 3600).toStringAsFixed(1);
      return l10n?.hoursLabel(hours) ??
          (_isFrenchLocale ? '$hours heures' : '$hours hours');
    }

    final days = (seconds / 86400).toStringAsFixed(1);
    return l10n?.daysLabel(days) ??
        (_isFrenchLocale ? '$days jours' : '$days days');
  }

  // Créer un hachage simple pour les avatars
  static int simpleHash(String str) {
    var hash = 0;
    for (var i = 0; i < str.length; i++) {
      hash = str.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return hash;
  }

  // Générateur de couleurs pour avatars
  static List<Color> avatarColors = [
    Colors.red.shade300,
    Colors.pink.shade300,
    Colors.purple.shade300,
    Colors.deepPurple.shade300,
    Colors.indigo.shade300,
    Colors.blue.shade300,
    Colors.lightBlue.shade300,
    Colors.cyan.shade300,
    Colors.teal.shade300,
    Colors.green.shade300,
    Colors.lightGreen.shade300,
    Colors.lime.shade300,
    Colors.yellow.shade700,
    Colors.amber.shade300,
    Colors.orange.shade300,
    Colors.deepOrange.shade300,
    Colors.brown.shade300,
    Colors.grey.shade400,
    Colors.blueGrey.shade300,
  ];

  static Color getAvatarColor(String seed) {
    final hash = simpleHash(seed);
    return avatarColors[hash.abs() % avatarColors.length];
  }

  // Formater un nombre avec séparateurs de milliers
  static String formatNumber(int number) {
    return NumberFormat.decimalPattern(_activeLocale).format(number);
  }

  // Créer un gradient basé sur un email
  static LinearGradient getEmailGradient(String email) {
    final hash = simpleHash(email);
    final color1 = avatarColors[hash.abs() % avatarColors.length];
    final color2 = avatarColors[(hash + 7).abs() % avatarColors.length];

    return LinearGradient(
      colors: [color1, color2],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }
}
