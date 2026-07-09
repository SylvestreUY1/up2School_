import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../models/ad_model.dart';
import '../models/event.dart';
import '../models/faculty.dart';
import '../models/file.dart';
import '../models/user.dart';

class BackendApiService {
  static final StreamController<void> _sessionExpiredController =
      StreamController<void>.broadcast();

  BackendApiService() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.backendUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 60),
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Certaines routes d'auth (login/refresh) doivent partir sans header.
          if (options.extra['skipAuth'] == true) {
            handler.next(options);
            return;
          }

          final authHeader = await _buildAuthorizationHeader(
            forceFirebaseRefresh: options.extra['forceFirebaseRefresh'] == true,
          );
          if (authHeader != null && authHeader.isNotEmpty) {
            options.headers['Authorization'] = authHeader;
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          // Toute l'application passe par ce point central. On tente donc
          // un unique rafraîchissement de session avant de remonter l'erreur.
          final shouldRetry = error.response?.statusCode == 401 &&
              error.requestOptions.extra['skipRetryOnUnauthorized'] != true &&
              error.requestOptions.extra['hasRetriedUnauthorized'] != true;

          if (shouldRetry) {
            final refreshedToken = await _refreshSessionIfPossible(
              forceFirebaseRefresh: true,
            );
            if (refreshedToken != null && refreshedToken.isNotEmpty) {
              try {
                final retryOptions = error.requestOptions;
                retryOptions.extra['hasRetriedUnauthorized'] = true;
                retryOptions.headers['Authorization'] =
                    'Bearer $refreshedToken';
                final response = await _dio.fetch<dynamic>(retryOptions);
                handler.resolve(response);
                return;
              } catch (_) {
                // On laisse tomber sur l'erreur initiale si la relance échoue.
              }
            }

            print(
              '⚠️  Token invalide ou expiré (401). Rafraîchissement automatique impossible.',
            );
          }

          handler.next(error);
        },
      ),
    );
  }

  static const _authTokenKey = 'auth_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userIdKey = 'user_id';
  static const _userPayloadKey = 'user_payload';
  static String? _sharedAuthToken;
  static String? _sharedRefreshToken;
  static Future<String?>? _sharedRefreshOperation;

  late final Dio _dio;
  String? _authToken;
  String? _refreshToken;

  Dio get dio => _dio;
  static Stream<void> get sessionExpiredStream =>
      _sessionExpiredController.stream;

  Future<void> clearLocalSession({bool notify = false}) async {
    await _clearPersistedSession(notify: notify);
  }

  Future<void> _clearPersistedSession({bool notify = false}) async {
    _authToken = null;
    _refreshToken = null;
    _sharedAuthToken = null;
    _sharedRefreshToken = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_authTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userPayloadKey);

    if (notify && !_sessionExpiredController.isClosed) {
      _sessionExpiredController.add(null);
    }
  }

  Future<String?> _loadPersistedAuthToken() async {
    if (_authToken != null && _authToken!.isNotEmpty) {
      return _authToken;
    }

    if (_sharedAuthToken != null && _sharedAuthToken!.isNotEmpty) {
      _authToken = _sharedAuthToken;
      return _authToken;
    }

    final prefs = await SharedPreferences.getInstance();
    final persistedToken = prefs.getString(_authTokenKey);
    if (persistedToken != null && persistedToken.isNotEmpty) {
      _authToken = persistedToken;
      _sharedAuthToken = persistedToken;
      return persistedToken;
    }

    return null;
  }

  Future<String?> _loadPersistedRefreshToken() async {
    if (_refreshToken != null && _refreshToken!.isNotEmpty) {
      return _refreshToken;
    }

    if (_sharedRefreshToken != null && _sharedRefreshToken!.isNotEmpty) {
      _refreshToken = _sharedRefreshToken;
      return _refreshToken;
    }

    final prefs = await SharedPreferences.getInstance();
    final persistedToken = prefs.getString(_refreshTokenKey);
    if (persistedToken != null && persistedToken.isNotEmpty) {
      _refreshToken = persistedToken;
      _sharedRefreshToken = persistedToken;
      return persistedToken;
    }

    return null;
  }

  bool _tokenExpiresSoon(String token,
      {Duration margin = const Duration(minutes: 2)}) {
    try {
      final segments = token.split('.');
      if (segments.length < 2) return false;
      final normalized = base64Url.normalize(segments[1]);
      final payload = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(base64Url.decode(normalized))) as Map);
      final exp = payload['exp'];
      if (exp is! num) return false;
      final expiry = DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
      return expiry.isBefore(DateTime.now().toUtc().add(margin));
    } catch (_) {
      return false;
    }
  }

  Future<String?> _getFirebaseIdToken({bool forceRefresh = false}) async {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser == null) return null;
      final token = await firebaseUser.getIdToken(forceRefresh);
      if (token != null && token.isNotEmpty) {
        return token;
      }
    } catch (_) {
      // Firebase peut être indisponible au tout début du bootstrap.
    }

    return null;
  }

  Future<String?> _refreshPersistedSession() async {
    final refreshToken = await _loadPersistedRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _clearPersistedSession(notify: true);
      return null;
    }

    // On mutualise le refresh pour éviter plusieurs appels concurrents
    // quand plusieurs requêtes partent au même moment.
    _sharedRefreshOperation ??= () async {
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          '/api/auth/refresh',
          data: {'refreshToken': refreshToken},
          options: Options(
            extra: const {
              'skipAuth': true,
              'skipRetryOnUnauthorized': true,
            },
          ),
        );

        final data = response.data ?? <String, dynamic>{};
        await _persistSession(
          data['token'] as String? ?? '',
          Map<String, dynamic>.from(data['user'] as Map? ?? {}),
          refreshToken: data['refreshToken'] as String?,
        );
        return _authToken;
      } catch (error) {
        if (_shouldClearPersistedSessionOnRefreshFailure(error)) {
          await _clearPersistedSession(notify: true);
        }
        return null;
      }
    }();

    try {
      return await _sharedRefreshOperation;
    } finally {
      _sharedRefreshOperation = null;
    }
  }

  Future<String?> _refreshSessionIfPossible({
    bool forceFirebaseRefresh = false,
  }) async {
    final firebaseToken = await _getFirebaseIdToken(
      forceRefresh: forceFirebaseRefresh,
    );
    if (firebaseToken != null && firebaseToken.isNotEmpty) {
      return firebaseToken;
    }

    if (AppConfig.useFirebaseDataLayer) {
      return null;
    }

    return _refreshPersistedSession();
  }

  Future<String?> _buildAuthorizationHeader({
    bool forceFirebaseRefresh = false,
  }) async {
    // Sur mobile Apple/Android, la source de vérité reste FirebaseAuth.
    final firebaseToken = await _getFirebaseIdToken(
      forceRefresh: forceFirebaseRefresh,
    );
    if (firebaseToken != null && firebaseToken.isNotEmpty) {
      return 'Bearer $firebaseToken';
    }

    if (AppConfig.useFirebaseDataLayer) {
      return null;
    }

    // Sur desktop, on persiste un token backend + un refresh token.
    final persistedToken = await _loadPersistedAuthToken();
    if (persistedToken == null || persistedToken.isEmpty) {
      return null;
    }

    if (_tokenExpiresSoon(persistedToken)) {
      final refreshedToken = await _refreshPersistedSession();
      if (refreshedToken != null && refreshedToken.isNotEmpty) {
        return 'Bearer $refreshedToken';
      }
      return null;
    }

    return 'Bearer $persistedToken';
  }

  Future<void> loadAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString(_authTokenKey);
    _refreshToken = prefs.getString(_refreshTokenKey);
    _sharedAuthToken = _authToken;
    _sharedRefreshToken = _refreshToken;
  }

  Future<UserModel?> getStoredUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userPayloadKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return UserModel.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistSession(String token, Map<String, dynamic> userPayload,
      {String? refreshToken}) async {
    final user = UserModel.fromMap(userPayload);
    final prefs = await SharedPreferences.getInstance();

    _authToken = token;
    _refreshToken = refreshToken ?? _refreshToken;
    _sharedAuthToken = token;
    _sharedRefreshToken = _refreshToken;
    await prefs.setString(_authTokenKey, token);
    if (_refreshToken != null && _refreshToken!.isNotEmpty) {
      await prefs.setString(_refreshTokenKey, _refreshToken!);
    }
    await prefs.setString(_userIdKey, user.id);
    await prefs.setString(_userPayloadKey, jsonEncode(user.toJson()));
  }

  Future<void> _persistUser(Map<String, dynamic> userPayload) async {
    final user = UserModel.fromMap(userPayload);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, user.id);
    await prefs.setString(_userPayloadKey, jsonEncode(user.toJson()));
  }

  String _extractError(Object error, String fallback) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map<String, dynamic>) {
        return data['error']?.toString() ?? fallback;
      }
      return error.message ?? fallback;
    }
    return fallback;
  }

  bool _shouldClearPersistedSessionOnRefreshFailure(Object error) {
    if (error is! DioException) {
      return false;
    }

    final statusCode = error.response?.statusCode;
    if (statusCode == 400 || statusCode == 401 || statusCode == 403) {
      return true;
    }

    final message = _extractError(error, '').toLowerCase();
    return message.contains('refresh token') ||
        message.contains('invalid_grant') ||
        message.contains('invalid refresh') ||
        message.contains('session expired');
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String name,
    String? phone,
    required String faculty,
    required String level,
    required String field,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/auth/register',
        data: {
          'email': email,
          'password': password,
          'name': name,
          'phone': phone,
          'faculty': faculty,
          'level': level,
          'field': field,
        },
        options: Options(
          extra: const {
            'skipAuth': true,
            'skipRetryOnUnauthorized': true,
          },
        ),
      );

      final data = response.data ?? <String, dynamic>{};
      await _persistSession(
        data['token'] as String? ?? '',
        Map<String, dynamic>.from(data['user'] as Map? ?? {}),
        refreshToken: data['refreshToken'] as String?,
      );
      return data;
    } catch (error) {
      throw Exception(_extractError(error, 'Registration error'));
    }
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/auth/login',
        data: {
          'email': email,
          'password': password,
        },
        options: Options(
          extra: const {
            'skipAuth': true,
            'skipRetryOnUnauthorized': true,
          },
        ),
      );

      final data = response.data ?? <String, dynamic>{};
      await _persistSession(
        data['token'] as String? ?? '',
        Map<String, dynamic>.from(data['user'] as Map? ?? {}),
        refreshToken: data['refreshToken'] as String?,
      );
      return data;
    } catch (error) {
      throw Exception(_extractError(error, 'Login error'));
    }
  }

  Future<void> logout() async {
    try {
      await _dio.post(
        '/api/auth/logout',
        options: Options(extra: const {'skipRetryOnUnauthorized': true}),
      );
    } catch (_) {
      // Best effort.
    } finally {
      await _clearPersistedSession(notify: true);
    }
  }

  Future<void> verifyPassword(String password) async {
    try {
      await _dio.post(
        '/api/auth/verify-password',
        data: {'password': password},
      );
    } catch (error) {
      throw Exception(_extractError(error, 'Password verification failed'));
    }
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.post(
        '/api/auth/change-password',
        data: {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
      );
    } catch (error) {
      throw Exception(_extractError(error, 'Password change failed'));
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _dio.post(
        '/api/auth/reset-password',
        data: {'email': email},
        options: Options(
          extra: const {
            'skipAuth': true,
            'skipRetryOnUnauthorized': true,
          },
        ),
      );
    } catch (error) {
      throw Exception(_extractError(error, 'Reset password failed'));
    }
  }

  Future<void> deleteCurrentAccount() async {
    try {
      await _dio.delete('/api/auth/account');
    } catch (error) {
      throw Exception(_extractError(error, 'Account deletion failed'));
    } finally {
      await logout();
    }
  }

  Future<UserModel> getUserProfile(
    String userId, {
    bool forceFirebaseRefresh = false,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/users/$userId',
        options: Options(
          extra: {'forceFirebaseRefresh': forceFirebaseRefresh},
        ),
      );
      final data = response.data ?? <String, dynamic>{};
      await _persistUser(data);
      return UserModel.fromMap(data);
    } catch (error) {
      throw Exception(_extractError(error, 'Profile fetch error'));
    }
  }

  Future<UserModel> updateUserProfile(
    String userId,
    Map<String, dynamic> data, {
    bool forceFirebaseRefresh = false,
  }) async {
    try {
      final response = await _dio.put<Map<String, dynamic>>(
        '/api/users/$userId',
        data: data,
        options: Options(
          extra: {'forceFirebaseRefresh': forceFirebaseRefresh},
        ),
      );
      final updated = response.data ?? <String, dynamic>{};
      await _persistUser(updated);
      return UserModel.fromMap(updated);
    } catch (error) {
      throw Exception(_extractError(error, 'Profile update error'));
    }
  }

  Future<List<Faculty>> getFaculties() async {
    try {
      final response = await _dio.get<List<dynamic>>('/api/faculties');
      return (response.data ?? const [])
          .map(
              (item) => Faculty.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (error) {
      throw Exception(_extractError(error, 'Faculty fetch error'));
    }
  }

  Future<List<Map<String, dynamic>>> getFiles({
    String? faculty,
    String? level,
    String? field,
    String? unit,
    String? type,
    int? page,
    int? pageSize,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/api/files',
        queryParameters: {
          if (faculty != null && faculty.isNotEmpty) 'faculty': faculty,
          if (level != null && level.isNotEmpty) 'level': level,
          if (field != null && field.isNotEmpty) 'field': field,
          if (unit != null && unit.isNotEmpty) 'unit': unit,
          if (type != null && type.isNotEmpty) 'type': type,
          if (page != null) 'page': page,
          if (pageSize != null) 'pageSize': pageSize,
        },
      );

      return (response.data ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (error) {
      throw Exception(_extractError(error, 'Files fetch error'));
    }
  }

  Future<Map<String, dynamic>> getFile(String fileId) async {
    try {
      final response =
          await _dio.get<Map<String, dynamic>>('/api/files/$fileId');
      return response.data ?? <String, dynamic>{};
    } catch (error) {
      throw Exception(_extractError(error, 'File fetch error'));
    }
  }

  Future<void> createFile(FileModel file) async {
    try {
      await _dio.post(
        '/api/files',
        data: file.toMap(),
      );
    } catch (error) {
      throw Exception(_extractError(error, 'Create file error'));
    }
  }

  Future<void> deleteFile(String fileId) async {
    try {
      await _dio.delete('/api/files/$fileId');
    } catch (error) {
      throw Exception(_extractError(error, 'Delete file error'));
    }
  }

  Future<void> updateReadingProgress(
    String fileId,
    String userId,
    double progress,
  ) async {
    try {
      await _dio.put(
        '/api/files/$fileId/reading-progress',
        data: {
          'userId': userId,
          'progress': progress,
        },
      );
    } catch (error) {
      throw Exception(_extractError(error, 'Reading progress update error'));
    }
  }

  Future<void> incrementFileViewCount(String fileId, String userId) async {
    try {
      await _dio.post(
        '/api/files/$fileId/views',
        data: {'userId': userId},
      );
    } catch (error) {
      throw Exception(_extractError(error, 'View count update error'));
    }
  }

  Future<void> toggleFavorite(String fileId, String userId) async {
    try {
      await _dio.post(
        '/api/files/$fileId/favorite',
        data: {'userId': userId},
      );
    } catch (error) {
      throw Exception(_extractError(error, 'Favorite update error'));
    }
  }

  Future<String> getFileDownloadUrl(String fileId) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/storage/download-url/$fileId',
      );
      return response.data?['downloadUrl'] as String? ?? '';
    } catch (error) {
      throw Exception(_extractError(error, 'Download URL error'));
    }
  }

  Future<Map<String, dynamic>> createSubscriptionCheckout({
    required String phone,
    String? name,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/subscriptions/checkout',
        data: {
          'phone': phone,
          if (name != null && name.isNotEmpty) 'name': name,
        },
      );
      return response.data ?? <String, dynamic>{};
    } catch (error) {
      throw Exception(_extractError(error, 'Subscription checkout error'));
    }
  }

  Future<Map<String, dynamic>> getMySubscription() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/subscriptions/me',
      );
      return response.data ?? <String, dynamic>{};
    } catch (error) {
      throw Exception(_extractError(error, 'Subscription fetch error'));
    }
  }

  Future<Map<String, dynamic>> checkSubscriptionTransaction(
    String transactionId,
  ) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/subscriptions/transactions/$transactionId/status',
      );
      return response.data ?? <String, dynamic>{};
    } catch (error) {
      throw Exception(_extractError(error, 'Transaction status error'));
    }
  }

  Future<List<Map<String, dynamic>>> getEvents({
    String? faculty,
    String? level,
    String? field,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/api/events',
        queryParameters: {
          if (faculty != null && faculty.isNotEmpty) 'faculty': faculty,
          if (level != null && level.isNotEmpty) 'level': level,
          if (field != null && field.isNotEmpty) 'field': field,
        },
      );

      return (response.data ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (error) {
      throw Exception(_extractError(error, 'Events fetch error'));
    }
  }

  Future<Map<String, dynamic>> getEvent(String eventId) async {
    try {
      final response =
          await _dio.get<Map<String, dynamic>>('/api/events/$eventId');
      return response.data ?? <String, dynamic>{};
    } catch (error) {
      throw Exception(_extractError(error, 'Event fetch error'));
    }
  }

  Future<void> createEvent(Event event) async {
    try {
      await _dio.post('/api/events', data: event.toMap());
    } catch (error) {
      throw Exception(_extractError(error, 'Create event error'));
    }
  }

  Future<void> deleteEvent(String eventId) async {
    try {
      await _dio.delete('/api/events/$eventId');
    } catch (error) {
      throw Exception(_extractError(error, 'Delete event error'));
    }
  }

  Future<List<UserModel>> getUsers({
    String? role,
    String? query,
  }) async {
    try {
      final response = await _dio.get<List<dynamic>>(
        '/api/users',
        queryParameters: {
          if (role != null && role.isNotEmpty) 'role': role,
          if (query != null && query.isNotEmpty) 'query': query,
        },
      );

      return (response.data ?? const [])
          .map((item) =>
              UserModel.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (error) {
      throw Exception(_extractError(error, 'Users fetch error'));
    }
  }

  Future<void> updateUserRole(String userId, UserRole role) async {
    try {
      await _dio.put(
        '/api/users/$userId/role',
        data: {'role': role.toString().split('.').last},
      );
    } catch (error) {
      throw Exception(_extractError(error, 'User role update error'));
    }
  }

  Future<void> deleteUser(String userId) async {
    try {
      await _dio.delete('/api/users/$userId');
    } catch (error) {
      throw Exception(_extractError(error, 'Delete user error'));
    }
  }

  Future<void> updateLastActivity(String userId) async {
    try {
      await _dio.post('/api/users/$userId/last-activity');
    } catch (error) {
      throw Exception(_extractError(error, 'Update last activity error'));
    }
  }

  Future<void> registerDevice(String deviceId, String platform) async {
    try {
      await _dio.post(
        '/api/notifications/register-device',
        data: {
          'deviceId': deviceId,
          'platform': platform,
        },
      );
    } catch (_) {
      // Best effort.
    }
  }

  Future<void> registerPushToken(String token, String platform) async {
    try {
      await _dio.post(
        '/api/notifications/register-push-token',
        data: {
          'token': token,
          'platform': platform,
        },
      );
    } catch (_) {
      // Best effort.
    }
  }

  Future<void> unregisterPushToken(String token) async {
    try {
      await _dio.post(
        '/api/notifications/unregister-push-token',
        data: {'token': token},
      );
    } catch (_) {
      // Best effort.
    }
  }

  Future<List<Map<String, dynamic>>> pollNotifications() async {
    try {
      final response = await _dio.get<List<dynamic>>('/api/notifications/poll');
      return (response.data ?? const [])
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    try {
      await _dio.post('/api/notifications/mark-read/$notificationId');
    } catch (_) {
      // Best effort.
    }
  }

  Future<List<AdModel>> getActiveAds() async {
    try {
      final response = await _dio.get<List<dynamic>>('/api/ads/active');
      return (response.data ?? const [])
          .map((item) =>
              AdModel.fromMap('', Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (error) {
      throw Exception(_extractError(error, 'Active ads fetch error'));
    }
  }

  Future<List<AdModel>> getAllAds() async {
    try {
      final response = await _dio.get<List<dynamic>>('/api/ads');
      return (response.data ?? const [])
          .map((item) =>
              AdModel.fromMap('', Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (error) {
      throw Exception(_extractError(error, 'Ads fetch error'));
    }
  }

  Future<String> uploadAdImage(FormData formData) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/ads/upload-image',
        data: formData,
      );
      return response.data?['imageUrl'] as String? ?? '';
    } catch (error) {
      throw Exception(_extractError(error, 'Ad image upload error'));
    }
  }

  Future<AdModel> createAd(AdModel ad, String adminUid) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/ads',
        data: {
          ...ad.toMap(),
          'createdBy': adminUid,
        },
      );
      return AdModel.fromMap(
        '',
        Map<String, dynamic>.from(response.data ?? const {}),
      );
    } catch (error) {
      throw Exception(_extractError(error, 'Create ad error'));
    }
  }

  Future<void> deleteAd(String adId) async {
    try {
      await _dio.delete('/api/ads/$adId');
    } catch (error) {
      throw Exception(_extractError(error, 'Delete ad error'));
    }
  }

  Future<void> incrementAdClick(String adId) async {
    try {
      await _dio.post('/api/ads/$adId/click');
    } catch (_) {
      // Best effort.
    }
  }

  Future<bool> isBackendAvailable() async {
    try {
      final response = await _dio.get(
        '/health',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
