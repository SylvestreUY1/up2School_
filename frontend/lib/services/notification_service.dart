import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../main.dart';
import '../models/event.dart';
import '../models/file.dart';
import '../providers/locale_provider.dart';
import '../services/local_event_storage.dart';
import '../screens/files/file_viewer_screen.dart';
import '../screens/files/files_list_screen.dart';
import 'api_service.dart';
import 'backend_api_service.dart';
import 'desktop_notification_service.dart';

class NotificationService {
  factory NotificationService() => _instance;

  NotificationService._internal();

  static final NotificationService _instance = NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final BackendApiService _backendApi = BackendApiService();
  final ApiService _apiService = ApiService();

  FirebaseMessaging? _fcm;
  DesktopWebSocketNotificationService? _wsService;
  DesktopPollingNotificationService? _pollingService;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  bool _initialized = false;
  bool? _androidExactAlarmPermissionGranted;
  void Function(Map<String, dynamic>)? _notificationListener;
  Locale _locale = AppLocalizations.supportedLocales.first;
  final Map<int, Timer> _desktopReminderTimers = {};

  AppLocalizations get _strings {
    final context = MyApp.navigatorKey.currentContext;
    if (context != null) {
      return context.l10n;
    }
    return AppLocalizations.forLocale(_locale);
  }

  Future<void> init({
    void Function(Map<String, dynamic>)? onNotificationTap,
  }) async {
    if (_initialized) {
      _notificationListener = onNotificationTap ?? _notificationListener;
      return;
    }

    _notificationListener = onNotificationTap;
    tz.initializeTimeZones();
    await _configureLocalTimezone();
    _locale = await LocalePreferences.effectiveLocale();
    await _initLocalNotifications();

    if (AppConfig.usesFirebaseMessaging) {
      _fcm = FirebaseMessaging.instance;
      await _initFirebaseMessaging();
    }

    _initialized = true;
  }

  Future<void> _configureLocalTimezone() async {
    try {
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone));
      print('[NOTIF] Fuseau local configuré: $localTimezone');
    } catch (e) {
      // On garde le fuseau par défaut si le nom remonté par la plateforme
      // n'est pas exploitable, mais on le journalise pour le diagnostic.
      print('[NOTIF] Fuseau local indisponible, fallback utilisé: $e');
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    final linuxSettings = LinuxInitializationSettings(
      defaultActionName: _strings.openNotification,
    );

    final settings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
    );

    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        try {
          final data = jsonDecode(payload) as Map<String, dynamic>;
          _handleNotificationData(data);
        } catch (_) {}
      },
    );

    final channel = AndroidNotificationChannel(
      'high_importance_channel',
      _strings.importantNotificationsChannelName,
      description: _strings.importantNotificationsChannelDescription,
      importance: Importance.high,
    );
    final reminderChannel = AndroidNotificationChannel(
      'reminder_channel',
      _strings.reminderChannelName,
      description: _strings.reminderChannelDescription,
      importance: Importance.high,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(reminderChannel);

    if (Platform.isAndroid) {
      final androidPlugin =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      _androidExactAlarmPermissionGranted =
          await androidPlugin?.requestExactAlarmsPermission() ?? true;
    }
  }

  Future<void> _initFirebaseMessaging() async {
    final granted = await requestPermissions().timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );
    if (!granted) return;

    try {
      await _fcm!.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      print('[NOTIF] Présentation FCM indisponible: $e');
    }

    _messageSubscription = FirebaseMessaging.onMessage.listen(_onRemoteMessage);
    _openedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _onRemoteMessage,
    );
    _tokenRefreshSubscription = _fcm!.onTokenRefresh.listen((token) async {
      await _syncPushToken(token);
    });

    try {
      final initialMessage = await _fcm!.getInitialMessage().timeout(
            const Duration(seconds: 5),
          );
      if (initialMessage != null) {
        _onRemoteMessage(initialMessage);
      }
    } catch (e) {
      print('[NOTIF] Message initial indisponible: $e');
    }

    try {
      final token = await _fcm!.getToken().timeout(const Duration(seconds: 5));
      if (token != null && token.isNotEmpty) {
        await _syncPushToken(token);
      }
    } catch (e) {
      print('[NOTIF] Token FCM indisponible: $e');
    }
  }

  Future<void> registerCurrentDevice(String userId) async {
    await init();

    if (AppConfig.usesFirebaseMessaging) {
      try {
        final token = await _fcm?.getToken().timeout(
              const Duration(seconds: 5),
            );
        if (token != null && token.isNotEmpty) {
          await saveTokenToFirestore(userId, token);
        }
      } catch (e) {
        print('[NOTIF] Enregistrement token ignoré: $e');
      }
    }

    if (AppConfig.useBackendNotificationState) {
      try {
        final deviceId = await _getOrCreateDeviceId();
        await _backendApi.registerDevice(deviceId, AppConfig.platformName);

        if (AppConfig.isDesktop && !AppConfig.usesApplePushNotifications) {
          await _startDesktopNotificationChannel(userId);
        }
      } catch (e) {
        print('[NOTIF] Canal desktop indisponible: $e');
      }
    }
  }

  Future<void> unregisterCurrentDevice(String userId) async {
    if (AppConfig.usesFirebaseMessaging) {
      try {
        final token = await _fcm?.getToken().timeout(
              const Duration(seconds: 5),
            );
        if (token != null && token.isNotEmpty) {
          await removeTokenFromFirestore(userId, token);
        }
      } catch (e) {
        print('[NOTIF] Suppression token ignorée: $e');
      }
    }
    await disposeDesktopChannel();
  }

  Future<void> _startDesktopNotificationChannel(String userId) async {
    await disposeDesktopChannel();

    if (AppConfig.notificationStrategy == NotificationStrategy.websocket) {
      _wsService = DesktopWebSocketNotificationService();
      await _wsService!.connect(userId);
      _wsService!.notifications.listen(_onDesktopNotification);
      return;
    }

    _pollingService = DesktopPollingNotificationService(
      onNotification: _onDesktopNotification,
      apiCall: _backendApi.pollNotifications,
    );
    _pollingService!.startPolling(userId);
  }

  Future<void> disposeDesktopChannel() async {
    await _wsService?.disconnect();
    _wsService?.dispose();
    _wsService = null;
    _pollingService?.stopPolling();
    _pollingService = null;
  }

  Future<void> _syncPushToken(String token) async {
    if (AppConfig.useBackendNotificationState) {
      try {
        await _backendApi.registerPushToken(token, AppConfig.platformName);
      } catch (e) {
        print('[NOTIF] Sync push token backend ignoré: $e');
      }
      return;
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null && userId.isNotEmpty) {
      await saveTokenToFirestore(userId, token);
    }
  }

  Future<void> saveTokenToFirestore(String userId, String token) async {
    if (AppConfig.useBackendNotificationState) {
      try {
        await _backendApi.registerPushToken(token, AppConfig.platformName);
      } catch (e) {
        print('[NOTIF] Push token backend ignoré: $e');
      }
      return;
    }
  }

  Future<void> removeTokenFromFirestore(String userId, String token) async {
    if (AppConfig.useBackendNotificationState) {
      try {
        await _backendApi.unregisterPushToken(token);
      } catch (e) {
        print('[NOTIF] Unregister push token backend ignoré: $e');
      }
      return;
    }
  }

  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      try {
        final androidPlugin =
            _localNotifications.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        final notificationsGranted =
            await androidPlugin?.requestNotificationsPermission() ?? true;
        _androidExactAlarmPermissionGranted =
            await androidPlugin?.requestExactAlarmsPermission() ?? true;
        return notificationsGranted;
      } catch (e) {
        print('[NOTIF] Permission Android indisponible: $e');
        return false;
      }
    }

    if (AppConfig.usesFirebaseMessaging) {
      try {
        final settings = await _fcm!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        return settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;
      } catch (e) {
        print('[NOTIF] Permission FCM indisponible: $e');
        return false;
      }
    }

    return true;
  }

  void _onRemoteMessage(RemoteMessage message) {
    final data = _messageToData(message);
    final shouldShowLocalNotification =
        Platform.isAndroid || message.notification == null;

    if (shouldShowLocalNotification) {
      _showLocalNotification(
        title: data['title']?.toString() ?? _strings.newNotification,
        body: data['body']?.toString() ?? '',
        data: data,
      );
    }
    _handleNotificationData(data);
  }

  Map<String, dynamic> _messageToData(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);
    final notification = message.notification;

    if ((data['title'] == null || data['title'].toString().isEmpty) &&
        notification?.title != null) {
      data['title'] = notification!.title;
    }
    if ((data['body'] == null || data['body'].toString().isEmpty) &&
        notification?.body != null) {
      data['body'] = notification!.body;
    }

    return data;
  }

  void _onDesktopNotification(Map<String, dynamic> data) {
    _showLocalNotification(
      title: data['title']?.toString() ?? _strings.newNotification,
      body: data['body']?.toString() ?? '',
      data: data,
    );
    _handleNotificationData(data);
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    final expandedBody = _expandedNotificationBody(body, data);

    await _localNotifications.show(
      data.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          _strings.importantNotificationsChannelName,
          channelDescription: _strings.importantNotificationsChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_icon',
          styleInformation: BigTextStyleInformation(
            expandedBody,
            contentTitle: title,
          ),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        linux: LinuxNotificationDetails(),
      ),
      payload: jsonEncode(data),
    );
  }

  String _expandedNotificationBody(String body, Map<String, dynamic> data) {
    final description = data['description']?.toString().trim() ?? '';
    if (description.isNotEmpty && description.length > body.trim().length) {
      return description;
    }
    return body;
  }

  void _handleNotificationData(Map<String, dynamic> data) {
    _notificationListener?.call(data);
    final type = data['type']?.toString();
    final id = data['id']?.toString();

    if (type == 'event' && id != null) {
      _saveEventLocally(data);
      MyApp.navigatorKey.currentState?.pushNamed('/events');
      return;
    }

    if (type == 'file' && id != null) {
      _navigateToFile(id);
    }
  }

  Future<void> _saveEventLocally(Map<String, dynamic> data) async {
    final event = Event(
      id: data['id']?.toString() ?? '',
      title: data['title']?.toString() ?? '',
      description: data['description']?.toString() ?? '',
      date: DateTime.tryParse(data['date']?.toString() ?? '') ?? DateTime.now(),
      location: data['location']?.toString() ?? '',
      faculty: data['faculty']?.toString() ?? '',
      level: data['level']?.toString() ?? '',
      field: data['field']?.toString() ?? '',
      createdBy: '',
      createdAt: DateTime.now(),
      imageUrls: const [],
      isGlobal: data['isGlobal'] == true || data['isGlobal'] == 'true',
    );

    await LocalEventStorage().insertEvent(event);
    await scheduleReminder(event, 48);
    await scheduleReminder(event, 12);
    await scheduleReminder(event, 1);
  }

  bool _isReminderAlreadyHandled(Event event, int hoursBefore) {
    switch (hoursBefore) {
      case 48:
        return event.reminder48hSent;
      case 12:
        return event.reminder12hSent;
      case 1:
        return event.reminder1hSent;
      default:
        return false;
    }
  }

  String _reminderFlagForHours(int hoursBefore) {
    switch (hoursBefore) {
      case 48:
        return 'reminder48hSent';
      case 12:
        return 'reminder12hSent';
      case 1:
        return 'reminder1hSent';
      default:
        throw ArgumentError('Unsupported reminder window: $hoursBefore');
    }
  }

  Future<void> scheduleReminder(Event event, int hoursBefore) async {
    try {
      final now = DateTime.now();
      final localEventDate =
          event.date.isUtc ? event.date.toLocal() : event.date;
      final scheduledDate = localEventDate.subtract(
        Duration(hours: hoursBefore),
      );
      final timeUntilEvent = localEventDate.difference(now);
      final reminderAlreadySent = _isReminderAlreadyHandled(event, hoursBefore);

      print(
        '[REMINDER] Programmation rappel: ${event.title}, dans $hoursBefore heures',
      );
      print(
        '[REMINDER] Date event: $localEventDate, Date rappel: $scheduledDate, Maintenant: $now',
      );

      if (reminderAlreadySent) {
        print(
          '[REMINDER] ⚠️ Rappel déjà traité pour ${event.title} ($hoursBefore heures)',
        );
        return;
      }

      if (scheduledDate.isBefore(now)) {
        final shouldShowImmediate = localEventDate.isAfter(now) &&
            ((hoursBefore == 48 &&
                    timeUntilEvent <= const Duration(hours: 48) &&
                    timeUntilEvent > const Duration(hours: 12)) ||
                (hoursBefore == 12 &&
                    timeUntilEvent <= const Duration(hours: 12) &&
                    timeUntilEvent > const Duration(hours: 1)) ||
                (hoursBefore == 1 &&
                    timeUntilEvent <= const Duration(hours: 1)));

        if (shouldShowImmediate) {
          await _showImmediateReminder(event, hoursBefore);
        } else {
          print(
            '[REMINDER] ⚠️ Fenêtre dépassée sans rappel immédiat: $scheduledDate < $now',
          );
        }
        return;
      }

      final tzScheduledDate = tz.TZDateTime.from(scheduledDate, tz.local);
      final androidScheduleMode = (_androidExactAlarmPermissionGranted ?? false)
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;

      final notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          'reminder_channel',
          _strings.reminderChannelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_icon',
          styleInformation: BigTextStyleInformation(
            _strings.reminderBody(event.title, hoursBefore),
            contentTitle: _strings.reminderTitle(event.title),
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        linux: const LinuxNotificationDetails(),
      );

      if (Platform.isLinux || Platform.isWindows) {
        final notificationId = event.id.hashCode + hoursBefore;
        _desktopReminderTimers[notificationId]?.cancel();
        _desktopReminderTimers[notificationId] = Timer(
          scheduledDate.difference(now),
          () async {
            _desktopReminderTimers.remove(notificationId);
            await _showImmediateReminder(event, hoursBefore);
          },
        );

        print(
          '[REMINDER] ✓ Rappel desktop programmé en mémoire: ${event.title} pour $scheduledDate',
        );
        return;
      }

      await _localNotifications.zonedSchedule(
        event.id.hashCode + hoursBefore,
        _strings.reminderTitle(event.title),
        _strings.reminderBody(event.title, hoursBefore),
        tzScheduledDate,
        notificationDetails,
        androidScheduleMode: androidScheduleMode,
      );

      print(
        '[REMINDER] ✓ Rappel programmé: ${event.title} pour $tzScheduledDate',
      );
    } catch (e) {
      print('[REMINDER] ✗ Erreur programmation: $e');
    }
  }

  Future<void> _showImmediateReminder(Event event, int hoursBefore) async {
    final notificationId = event.id.hashCode + hoursBefore;

    final notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'reminder_channel',
        _strings.reminderChannelName,
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_stat_icon',
        styleInformation: BigTextStyleInformation(
          _strings.reminderBody(
            event.title,
            hoursBefore,
            immediate: true,
          ),
          contentTitle: _strings.reminderTitle(event.title, immediate: true),
        ),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
      linux: LinuxNotificationDetails(),
    );

    await _localNotifications.show(
      notificationId,
      _strings.reminderTitle(event.title, immediate: true),
      _strings.reminderBody(
        event.title,
        hoursBefore,
        immediate: true,
      ),
      notificationDetails,
      payload: jsonEncode({
        'type': 'event',
        'id': event.id,
        'title': event.title,
        'description': event.description,
        'date': event.date.toIso8601String(),
        'location': event.location,
        'faculty': event.faculty,
        'level': event.level,
        'field': event.field,
        'isGlobal': event.isGlobal.toString(),
      }),
    );

    final reminderFlag = _reminderFlagForHours(hoursBefore);
    await LocalEventStorage().updateReminderSent(event.id, reminderFlag);
    print(
      '[REMINDER] ✓ Notification immédiate affichée pour ${event.title} ($hoursBefore heures)',
    );
  }

  Future<void> cancelReminders(Event event) async {
    for (final hoursBefore in [48, 12, 1]) {
      final notificationId = event.id.hashCode + hoursBefore;
      _desktopReminderTimers.remove(notificationId)?.cancel();
      await _localNotifications.cancel(notificationId);
    }
  }

  Future<void> _navigateToFile(String fileId) async {
    final FileModel? file = await _apiService.getFileById(fileId);
    if (file == null) {
      final context = MyApp.navigatorKey.currentContext;
      if (context == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.fileNotFound),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    MyApp.navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => FilesListScreen(
          faculty: file.faculty,
          level: file.level,
          field: file.field,
          unit: file.unit,
          type: file.type,
        ),
      ),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      MyApp.navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => FileViewerScreen(file: file)),
      );
    });
  }

  Future<String> _getOrCreateDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('desktop_device_id');
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final generated =
        '${Platform.operatingSystem}-${DateTime.now().millisecondsSinceEpoch}';
    await prefs.setString('desktop_device_id', generated);
    return generated;
  }

  Future<void> dispose() async {
    await disposeDesktopChannel();
    await _messageSubscription?.cancel();
    await _openedAppSubscription?.cancel();
    await _tokenRefreshSubscription?.cancel();
  }
}
