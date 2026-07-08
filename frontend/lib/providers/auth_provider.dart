import 'dart:async';
import 'package:flutter/foundation.dart'; // pour kDebugMode
import '../models/user.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  final ApiService _apiService = ApiService();
  final NotificationService _notificationService = NotificationService();

  UserModel? _currentUser;
  bool _isLoading = false;
  bool _isInitialized = false;
  bool _disposed = false;
  bool _notificationSyncInProgress = false;
  String? _notificationSyncUserId;
  final Completer<void> _initCompleter = Completer<void>();

  StreamSubscription<UserModel?>? _authSubscription;

  // ================= GETTERS =================

  UserModel? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  bool get isInitialized => _isInitialized;
  Future<void> get initializationDone => _initCompleter.future;

  // ================= CONSTRUCTEUR =================

  AuthProvider() {
    _initialize();
  }

  // ================= INITIALISATION =================

  Future<void> _initialize() async {
    try {
      final cachedUser = await _authService.getCachedCurrentUser();
      if (cachedUser != null) {
        _currentUser = cachedUser;
        if (_authService.hasActiveAuthenticatedSession) {
          unawaited(_syncNotificationState(cachedUser));
          unawaited(_refreshUserFromBackendSilently());
        }
      }

      final completer = Completer<void>();
      _authSubscription = _authService.authStateChanges.listen(
        (user) async {
          _currentUser = user;
          _safeNotifyListeners();
          if (!completer.isCompleted) completer.complete();

          if (user != null) {
            unawaited(_syncNotificationState(user));
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
      );
      if (cachedUser != null && !completer.isCompleted) {
        completer.complete();
      }
      await completer.future.timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint(
        'Erreur lors de l\'initialisation de l\'authentification : $e',
      );
    } finally {
      _isInitialized = true;
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
      _safeNotifyListeners();
    }
  }

  Future<void> _syncNotificationState(UserModel user) async {
    if (_notificationSyncInProgress && _notificationSyncUserId == user.id) {
      return;
    }

    _notificationSyncInProgress = true;
    _notificationSyncUserId = user.id;

    try {
      await _notificationService.registerCurrentDevice(user.id);
      await _authService.syncNotificationSubscriptions(user);
    } catch (e) {
      debugPrint('Synchronisation notifications ignorée: $e');
    } finally {
      _notificationSyncInProgress = false;
    }
  }

  void _safeNotifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  // ================= AUTHENTIFICATION =================

  Future<void> signIn(String email, String password) async {
    _isLoading = true;
    _safeNotifyListeners();

    try {
      final user = await _authService.signInWithEmail(email, password);
      if (user != null) {
        _currentUser = user;
        final refreshed = await _authService.refreshCurrentUserProfile();
        if (refreshed != null) {
          _currentUser = refreshed;
        }
        unawaited(_syncNotificationState(user));
      }
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<void> signInWithGoogle() async {
    _isLoading = true;
    _safeNotifyListeners();

    try {
      final user = await _authService.signInWithGoogle();
      if (user != null) {
        _currentUser = user;
        final refreshed = await _authService.refreshCurrentUserProfile();
        if (refreshed != null) {
          _currentUser = refreshed;
        }
        unawaited(_syncNotificationState(user));
      }
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  /// Utilisé par l'écran d'inscription:
  /// on authentifie Google/Firebase puis on pré-remplit l'UI.
  Future<Map<String, String?>> beginGoogleRegistration() async {
    _isLoading = true;
    _safeNotifyListeners();

    try {
      return await _authService.beginGoogleRegistration();
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  /// Finalise l'inscription après Google: on complète le profil backend
  /// avec le nom + les infos académiques.
  Future<void> registerWithGoogle({
    required String name,
    required String faculty,
    required String level,
    required String field,
  }) async {
    _isLoading = true;
    _safeNotifyListeners();

    try {
      final user = await _authService.completeGoogleRegistration(
        name: name,
        faculty: faculty,
        level: level,
        field: field,
      );
      if (user != null) {
        _currentUser = user;
        unawaited(_syncNotificationState(user));
      }
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String name,
    String? phone,
    required String faculty,
    required String level,
    required String field,
  }) async {
    _isLoading = true;
    _safeNotifyListeners();

    try {
      final user = await _authService.registerWithEmail(
        email: email,
        password: password,
        name: name,
        phone: phone,
        faculty: faculty,
        level: level,
        field: field,
      );
      if (user != null) {
        _currentUser = user;
        unawaited(_syncNotificationState(user));
      }
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<void> signOut() async {
    _isLoading = true;
    _safeNotifyListeners();

    try {
      final userId = _currentUser?.id;

      await _authService.signOut();

      if (userId != null) {
        await _notificationService.unregisterCurrentDevice(userId);
      }

      _currentUser = null;
      _notificationSyncUserId = null;
      _safeNotifyListeners();
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<void> reauthenticate(String password) async {
    await _authService.reauthenticate(password);
  }

  Future<void> deleteAccount() async {
    _isLoading = true;
    _safeNotifyListeners();

    try {
      await _authService.deleteAccount();
      _currentUser = null;
      _safeNotifyListeners();
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<void> updateAcademicInfo({
    required String faculty,
    required String level,
    required String field,
  }) async {
    if (_currentUser == null) return;

    _isLoading = true;
    _safeNotifyListeners();

    try {
      final updated = await _authService.updateAcademicInfo(
        _currentUser!.id,
        faculty,
        level,
        field,
      );
      if (updated != null) {
        _currentUser = updated;
        unawaited(_syncNotificationState(updated));
      }
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<UserModel?> refreshCurrentUser() async {
    final refreshed = await _authService.refreshCurrentUserProfile();
    if (refreshed != null) {
      _currentUser = refreshed;
      _safeNotifyListeners();
    }
    return refreshed;
  }

  Future<void> _refreshUserFromBackendSilently() async {
    try {
      final refreshed = await _authService.refreshCurrentUserProfile();
      if (refreshed != null) {
        _currentUser = refreshed;
        _safeNotifyListeners();
      }
    } catch (e) {
      debugPrint('Rafraichissement silencieux du profil ignore: $e');
    }
  }

  // ================= MOT DE PASSE =================

  Future<void> resetPassword(String email) async {
    _isLoading = true;
    _safeNotifyListeners();
    try {
      await _authService.sendPasswordResetEmail(email);
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    _isLoading = true;
    _safeNotifyListeners();

    try {
      await _authService.changePassword(currentPassword, newPassword);
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  // ================= DEBUG =================

  Future<void> debugSessionStatus() async {
    if (kDebugMode) {
      debugPrint('===== AUTH STATUS =====');
      debugPrint('Initialisé: $_isInitialized');
      debugPrint('Authentifié: $isAuthenticated');
      debugPrint('Utilisateur: ${_currentUser?.email}');
      debugPrint('=======================');
    }
  }

  // ============== Met à jour la dernière activité de l'utilisateur via le backend ==============
  Future<void> updateLastActivity() async {
    if (_currentUser == null) return;

    final prefs = await SharedPreferences.getInstance();
    final lastUpdateKey = 'last_activity_update_${_currentUser!.id}';
    final lastUpdateMillis = prefs.getInt(lastUpdateKey);
    final now = DateTime.now().millisecondsSinceEpoch;
    final twoWeeksInMillis = 14 * 24 * 60 * 60 * 1000;

    if (lastUpdateMillis == null || now - lastUpdateMillis > twoWeeksInMillis) {
      try {
        await _apiService.updateLastActivity(_currentUser!.id);
        await prefs.setInt(lastUpdateKey, now);
        print('lastActivity mis à jour');
      } catch (e) {
        print('Erreur mise à jour lastActivity: $e');
      }
    } else {
      // Pas besoin de log pour chaque vérification
      // print('Pas de mise à jour lastActivity (moins de 14 jours)');
    }
  }

  // ================= CLEANUP =================

  @override
  void dispose() {
    _disposed = true;
    _authSubscription?.cancel();
    _authService.dispose();
    _notificationService.dispose();
    super.dispose();
  }
}
