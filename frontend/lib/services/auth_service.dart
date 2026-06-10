import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/user.dart';
import '../utils/academic_targeting.dart';
import 'backend_api_service.dart';

class AuthService {
  factory AuthService() => _instance;

  AuthService._internal() {
    if (AppConfig.usesFirebaseMessaging) {
      _fcm = FirebaseMessaging.instance;
    }

    if (AppConfig.useFirebaseDataLayer) {
      _auth = FirebaseAuth.instance;
    }

    if (!AppConfig.useFirebaseDataLayer) {
      _bootstrapDesktopSession();
    }
  }

  static final AuthService _instance = AuthService._internal();
  static const _cachedFirebaseUserKey = 'cached_firebase_user_payload';

  FirebaseAuth? _auth;
  FirebaseMessaging? _fcm;
  final BackendApiService _backendApi = BackendApiService();
  final StreamController<UserModel?> _desktopAuthController =
      StreamController<UserModel?>.broadcast();

  StreamSubscription<User?>? _firebaseSubscription;
  StreamSubscription<void>? _backendSessionExpiredSubscription;

  Future<void> _bootstrapDesktopSession() async {
    await _backendApi.loadAuthToken();
    final storedUser = await _backendApi.getStoredUser();
    _desktopAuthController.add(storedUser);

    _backendSessionExpiredSubscription ??=
        BackendApiService.sessionExpiredStream.listen((_) {
      _desktopAuthController.add(null);
    });
  }

  Future<void> _cacheFirebaseUser(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cachedFirebaseUserKey,
      jsonEncode(user.toJson()),
    );
  }

  Future<void> _clearCachedFirebaseUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedFirebaseUserKey);
  }

  Future<UserModel?> _getCachedFirebaseUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedFirebaseUserKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return UserModel.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<UserModel?> _getBestAvailableMobileUser({
    String? expectedUserId,
  }) async {
    final cachedUser = await _getCachedFirebaseUser();
    if (cachedUser != null &&
        (expectedUserId == null || cachedUser.id == expectedUserId)) {
      return cachedUser;
    }

    final storedUser = await _backendApi.getStoredUser();
    if (storedUser != null &&
        (expectedUserId == null || storedUser.id == expectedUserId)) {
      return storedUser;
    }

    return null;
  }

  Future<void> _persistMobileBackendSession({
    required String email,
    required String password,
  }) async {
    try {
      await _backendApi.login(email: email, password: password);
    } catch (e) {
      print('[AUTH] Persistance backend mobile indisponible: $e');
    }
  }

  Future<UserModel?> _resolveFirebaseUserProfile(User firebaseUser) async {
    try {
      final user = await _backendApi
          .getUserProfile(firebaseUser.uid)
          .timeout(const Duration(seconds: 8));
      await _cacheFirebaseUser(user);
      return user;
    } catch (e) {
      print('[AUTH] Profil backend indisponible, fallback cache: $e');
    }

    final cachedUser = await _getCachedFirebaseUser();
    if (cachedUser != null && cachedUser.id == firebaseUser.uid) {
      return cachedUser;
    }

    return null;
  }

  Future<UserModel?> getCachedCurrentUser() async {
    if (!AppConfig.useFirebaseDataLayer) {
      return _backendApi.getStoredUser();
    }

    final firebaseUser = _auth?.currentUser;
    if (firebaseUser == null) {
      return _getCachedFirebaseUser();
    }

    return _getBestAvailableMobileUser(expectedUserId: firebaseUser.uid);
  }

  bool get hasActiveAuthenticatedSession {
    if (!AppConfig.useFirebaseDataLayer) {
      return true;
    }
    return _auth?.currentUser != null;
  }

  Future<UserModel?> signInWithEmail(String email, String password) async {
    if (!AppConfig.useFirebaseDataLayer) {
      final response =
          await _backendApi.login(email: email, password: password);
      final user = UserModel.fromMap(
        Map<String, dynamic>.from(response['user'] as Map? ?? {}),
      );
      _desktopAuthController.add(user);
      return user;
    }

    try {
      final userCredential = await _auth!.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = await _resolveFirebaseUserProfile(userCredential.user!);
      if (user == null) {
        throw 'Profil utilisateur introuvable sur le backend';
      }
      await _cacheFirebaseUser(user);
      await _persistMobileBackendSession(email: email, password: password);
      print('[AUTH] Login réussi pour ${user.email}');
      return user;
    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseAuthError(e);
    }
  }

  Future<UserModel?> registerWithEmail({
    required String email,
    required String password,
    required String name,
    String? phone,
    required String faculty,
    required String level,
    required String field,
  }) async {
    if (!AppConfig.useFirebaseDataLayer) {
      final response = await _backendApi.register(
        email: email,
        password: password,
        name: name,
        phone: phone,
        faculty: faculty,
        level: level,
        field: field,
      );
      final user = UserModel.fromMap(
        Map<String, dynamic>.from(response['user'] as Map? ?? {}),
      );
      _desktopAuthController.add(user);
      return user;
    }

    try {
      final userCredential = await _auth!.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final uid = userCredential.user!.uid;
      final newUser = UserModel(
        id: uid,
        email: email,
        name: name,
        phone: phone,
        role: UserRole.student,
        faculty: faculty,
        level: level,
        field: field,
        createdAt: DateTime.now(),
      );

      final syncedUser =
          await _backendApi.updateUserProfile(uid, newUser.toMap());
      await _cacheFirebaseUser(syncedUser);
      await _persistMobileBackendSession(email: email, password: password);
      print('[AUTH] Registration réussie pour ${syncedUser.email}');
      return syncedUser;
    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseAuthError(e);
    }
  }

  Future<void> signOut() async {
    if (!AppConfig.useFirebaseDataLayer) {
      final storedUser = await _backendApi.getStoredUser();
      if (storedUser != null) {
        await _unsubscribeFromTopics(storedUser);
      }
      await _backendApi.logout();
      _desktopAuthController.add(null);
      return;
    }

    final user = _auth!.currentUser;
    if (user != null) {
      final userModel = await _resolveFirebaseUserProfile(user);
      if (userModel != null) {
        await _unsubscribeFromTopics(userModel);
      }
    }
    await _backendApi.logout();
    await _auth!.signOut();
    await _clearCachedFirebaseUser();
  }

  Stream<UserModel?> get authStateChanges {
    if (!AppConfig.useFirebaseDataLayer) {
      return _desktopAuthController.stream;
    }

    return _auth!.authStateChanges().asyncMap((user) async {
      if (user == null) {
        await _clearCachedFirebaseUser();
        await _backendApi.clearLocalSession(notify: true);
        return null;
      }
      return _resolveFirebaseUserProfile(user);
    });
  }

  Future<UserModel?> updateAcademicInfo(
    String userId,
    String faculty,
    String level,
    String field,
  ) async {
    if (!AppConfig.useFirebaseDataLayer) {
      final oldUser = await _backendApi.getStoredUser();
      if (oldUser != null) {
        await _unsubscribeFromTopics(oldUser);
      }

      final updated = await _backendApi.updateUserProfile(userId, {
        'faculty': faculty,
        'level': level,
        'field': field,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      await _subscribeToTopics(updated);
      _desktopAuthController.add(updated);
      return updated;
    }

    final oldUser = await refreshCurrentUserProfile();
    if (oldUser != null) {
      await _unsubscribeFromTopics(oldUser);
    }

    final newUser = await _backendApi.updateUserProfile(userId, {
      'faculty': faculty,
      'level': level,
      'field': field,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await _cacheFirebaseUser(newUser);
    await _subscribeToTopics(newUser);
    return newUser;
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    if (!AppConfig.useFirebaseDataLayer) {
      await _backendApi.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      return;
    }

    try {
      final user = _auth!.currentUser;
      if (user == null) throw 'Aucun utilisateur connecté';
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseAuthError(e);
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    if (!AppConfig.useFirebaseDataLayer) {
      await _backendApi.sendPasswordResetEmail(email);
      return;
    }

    try {
      await _auth!.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleFirebaseAuthError(e);
    }
  }

  Future<void> reauthenticate(String password) async {
    if (!AppConfig.useFirebaseDataLayer) {
      await _backendApi.verifyPassword(password);
      return;
    }

    final user = _auth!.currentUser;
    if (user == null) throw 'Aucun utilisateur connecté';
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: password,
    );
    await user.reauthenticateWithCredential(credential);
  }

  Future<UserModel?> refreshCurrentUserProfile() async {
    if (!AppConfig.useFirebaseDataLayer) {
      final storedUser = await _backendApi.getStoredUser();
      if (storedUser == null) return null;
      final refreshed = await _backendApi.getUserProfile(storedUser.id);
      _desktopAuthController.add(refreshed);
      return refreshed;
    }

    final user = _auth?.currentUser;
    if (user == null) {
      await _clearCachedFirebaseUser();
      await _backendApi.clearLocalSession(notify: true);
      return null;
    }

    final refreshed = await _backendApi.getUserProfile(user.uid);
    await _cacheFirebaseUser(refreshed);
    _desktopAuthController.add(refreshed);
    return refreshed;
  }

  Future<void> deleteAccount() async {
    if (!AppConfig.useFirebaseDataLayer) {
      await _backendApi.deleteCurrentAccount();
      _desktopAuthController.add(null);
      return;
    }

    final user = _auth!.currentUser;
    if (user == null) throw 'Aucun utilisateur connecté';

    final userModel = await _resolveFirebaseUserProfile(user);
    if (userModel != null) {
      await _unsubscribeFromTopics(userModel);
    }

    await _backendApi.deleteCurrentAccount();
    await _auth!.signOut();
    await _clearCachedFirebaseUser();
  }

  List<String> _generateTopics(UserModel user) {
    return AcademicTargeting.buildUserTopics(user);
  }

  Future<void> syncNotificationSubscriptions(UserModel user) async {
    if (!AppConfig.usesFirebaseMessaging) {
      return;
    }

    if (Platform.isLinux || Platform.isWindows) {
      return;
    }

    try {
      await _subscribeToTopics(user);
    } catch (e) {
      print('[AUTH] Erreur sync topics: $e');
    }
  }

  Future<void> _requestPermissionsAndSubscribe(UserModel user) async {
    try {
      // Demander les permissions de notification
      final granted = await _requestNotificationPermissions();
      print('[AUTH] Permissions notifications: $granted');

      if (!granted) {
        print('[AUTH] ⚠️  Permissions refusées, pas de subscriptions FCM');
        return;
      }

      // Attendre un peu pour que les permissions soient bien complètement acceptées
      await Future.delayed(const Duration(milliseconds: 500));

      // S'abonner aux topics
      await _subscribeToTopics(user);
    } catch (e) {
      print('[AUTH] Erreur permissions/subscribe: $e');
    }
  }

  Future<bool> _requestNotificationPermissions() async {
    if (Platform.isLinux || Platform.isWindows) {
      return true; // Desktop toujours "accepté"
    }

    if (!AppConfig.usesFirebaseMessaging) {
      return false;
    }

    try {
      if (Platform.isAndroid) {
        // Sur Android 13+, demander la permission runtime
        final permission = await Permission.notification.request();
        final isGranted = permission.isGranted;
        print('[AUTH] Android notification permission: $isGranted');
        return isGranted;
      } else if (Platform.isIOS) {
        // Sur iOS, demander via Firebase
        final settings = await _fcm!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        final granted =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
                settings.authorizationStatus == AuthorizationStatus.provisional;
        print('[AUTH] iOS notification permission: $granted');
        return granted;
      }
    } catch (e) {
      print('[AUTH] Erreur demande permissions: $e');
    }
    return false;
  }

  Future<void> _subscribeToTopics(UserModel user) async {
    if (!AppConfig.usesFirebaseMessaging || _fcm == null) {
      return;
    }

    // Linux et Windows restent sur le canal backend.
    if (Platform.isLinux || Platform.isWindows) {
      print('[DEBUG] Desktop platform: FCM non supporté');
      return;
    }

    print('[DEBUG] Abonnement aux topics pour ${user.email}');
    for (final topic in _generateTopics(user)) {
      try {
        print('[DEBUG] Abonnement au topic: $topic');
        await _fcm!.subscribeToTopic(topic);
        print('[DEBUG] ✓ Abonné au topic: $topic');
      } catch (e) {
        print('[DEBUG] Erreur abonnement $topic: $e');
      }
    }
  }

  Future<void> _unsubscribeFromTopics(UserModel user) async {
    if (!AppConfig.usesFirebaseMessaging || _fcm == null) {
      return;
    }

    if (Platform.isLinux || Platform.isWindows) {
      return;
    }

    for (final topic in _generateTopics(user)) {
      try {
        await _fcm!.unsubscribeFromTopic(topic);
      } catch (_) {}
    }
  }

  void dispose() {
    _firebaseSubscription?.cancel();
    _backendSessionExpiredSubscription?.cancel();
    _desktopAuthController.close();
  }

  String _handleFirebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'Aucun utilisateur trouvé avec cet email';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Mot de passe incorrect';
      case 'email-already-in-use':
        return 'Cet email est déjà utilisé';
      case 'weak-password':
        return 'Le mot de passe est trop faible';
      case 'invalid-email':
        return 'Email invalide';
      case 'user-disabled':
        return 'Ce compte a été désactivé';
      default:
        return 'Erreur d\'authentification: ${e.message}';
    }
  }
}
