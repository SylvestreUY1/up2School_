import 'dart:async';

/**
 * FICHIER : main.dart
 * RÔLE : C'est le chef d'orchestre ! Ce fichier démarre toute l'application.
 * Il prépare la base de données, les notifications, les couleurs et décide
 * quel écran afficher au lancement (Accueil ou Connexion).
 */

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'firebase_options.dart';
import 'config/app_config.dart';
import 'providers/auth_provider.dart';
import 'providers/locale_provider.dart';
import 'screens/main/home_screen.dart';
import 'models/file.dart';
import 'utils/constants.dart';
import 'services/backend_storage_service.dart';
import 'services/deep_link_service.dart';
import 'services/firebase_storage_service.dart';
import 'services/storage_service_interface.dart';
import 'services/file_manager_service.dart';
import 'l10n/app_localizations.dart';

/**
 * GESTIONNAIRE DES NOTIFICATIONS EN ARRIÈRE-PLAN
 * C'est le code qui s'exécute quand vous recevez un message mais que l'application est FERMÉE.
 */
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // On initialise Firebase pour pouvoir travailler même quand l'app dort
  if (AppConfig.requiresFirebaseInitialization && Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  }
  print('Une notification est arrivée en arrière-plan !');
}

/**
 * LE DÉMARRAGE (MAIN)
 */
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. On réveille les bases de données (Hive pour le cache, Sqflite pour les rappels)
  await Hive.initFlutter();
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(FileModelAdapter());
  if (AppConfig.isDesktop) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 2. On connecte Firebase seulement sur les plateformes qui le supportent.
  if (AppConfig.requiresFirebaseInitialization) {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
  }

  // 3. On prépare les traducteurs de langues
  await initializeDateFormatting();

  // 4. ON LANCE L'APPAREIL PHOTO... non, l'APPLICATION !
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        Provider<StorageService>(
          create: (_) => AppConfig.useBackendStorage
              ? BackendStorageService()
              : FirebaseStorageService(),
        ),
        ProxyProvider<StorageService, FileManagerService>(
          update: (_, storageService, previous) =>
              previous ?? FileManagerService(storageService: storageService),
        ),
        // On ajoute d'autres outils ici si besoin
      ],
      child: const MyApp(),
    ),
  );
  unawaited(DeepLinkService().init());
}

/**
 * LA STRUCTURE DE L'APPLICATION
 * Définit la configuration globale (MaterialApp) et le système de navigation.
 */
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // Cette clé nous permet de changer de page n'importe où sans avoir besoin du "context"
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'Up2School',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppConstants.primaryColor,
            primary: AppConstants.primaryColor,
            secondary: AppConstants.secondaryColor,
            error: AppConstants.errorColor,
          ),
          scaffoldBackgroundColor: AppConstants.backgroundColor,
          appBarTheme: const AppBarTheme(
            backgroundColor: AppConstants.primaryColor,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            iconTheme: IconThemeData(color: Colors.white),
            titleTextStyle: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        locale: localeProvider.locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        localeResolutionCallback: (locale, supportedLocales) {
          return AppLocalizations.resolveLocale(locale);
        },
        home:
            const AuthWrapper(), // On commence par vérifier si l'utilisateur est connecté
      ),
    );
  }
}

/**
 * LE FILTRE DE CONNEXION
 * Si tu es connecté -> Écran d'accueil. Sinon -> Écran de Connexion.
 */
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    if (auth.isInitialized) return const HomeScreen();
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
