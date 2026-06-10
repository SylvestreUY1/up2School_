import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/app_config.dart';

/// Desktop notification service using WebSocket
class DesktopWebSocketNotificationService {
  late WebSocketChannel _channel;
  final StreamController<Map<String, dynamic>> _notificationStream =
      StreamController.broadcast();
  bool _isConnected = false;
  Timer? _reconnectTimer;
  String? _userId;

  Stream<Map<String, dynamic>> get notifications => _notificationStream.stream;
  bool get isConnected => _isConnected;

  /// Connect to WebSocket server
  Future<void> connect(String userId) async {
    if (_isConnected) return;

    _userId = userId;

    try {
      final url = Uri.parse('${AppConfig.webSocketUrl}/notifications');
      _channel = WebSocketChannel.connect(url);

      // Send authentication
      _channel.sink.add(jsonEncode({
        'type': 'auth',
        'userId': userId,
      }));

      // Listen to messages
      _channel.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message as String);
            if (data['type'] == 'notification') {
              _notificationStream
                  .add(Map<String, dynamic>.from(data['data'] as Map));
            }
          } catch (e) {
            print('WebSocket message parsing error: $e');
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
          _isConnected = false;
          _attemptReconnect();
        },
        onDone: () {
          print('WebSocket disconnected');
          _isConnected = false;
          _attemptReconnect();
        },
      );

      _isConnected = true;
      print('✅ WebSocket connected');
    } catch (e) {
      print('❌ WebSocket connection failed: $e');
      _attemptReconnect();
    }
  }

  /// Attempt to reconnect
  void _attemptReconnect() {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) {
      return;
    }

    print('🔄 Attempting to reconnect in 5 seconds...');
    _reconnectTimer = Timer(const Duration(seconds: 5), () async {
      if (_userId != null && !_isConnected) {
        await connect(_userId!);
      }
    });
  }

  /// Disconnect
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    await _channel.sink.close();
    _isConnected = false;
    print('WebSocket disconnected');
  }

  /// Dispose resources
  void dispose() {
    _reconnectTimer?.cancel();
    _notificationStream.close();
  }
}

/// Desktop notification service using HTTP polling
class DesktopPollingNotificationService {
  final Function(Map<String, dynamic>) onNotification;
  Timer? _pollTimer;
  bool _isRunning = false;
  String? _userId;
  final Duration _pollInterval;
  final Function? apiCall;

  DesktopPollingNotificationService({
    required this.onNotification,
    Duration pollInterval = const Duration(seconds: 5),
    this.apiCall,
  }) : _pollInterval = pollInterval;

  /// Start polling for notifications
  void startPolling(String userId) {
    if (_isRunning) return;

    _userId = userId;
    _isRunning = true;

    print('🔄 Starting notification polling every ${_pollInterval.inSeconds}s');

    _pollTimer = Timer.periodic(_pollInterval, (_) async {
      await _poll();
    });

    // Poll immediately
    _poll();
  }

  /// Perform a single poll
  Future<void> _poll() async {
    try {
      if (apiCall != null) {
        final notifications = await apiCall!();
        if (notifications is List) {
          for (var notif in notifications) {
            onNotification(Map<String, dynamic>.from(notif as Map));
          }
        }
      }
    } catch (e) {
      print('Polling error: $e');
    }
  }

  /// Stop polling
  void stopPolling() {
    _pollTimer?.cancel();
    _isRunning = false;
    print('Polling stopped');
  }

  bool get isRunning => _isRunning;
}

/// Platform notification service factory
class PlatformNotificationServiceFactory {
  static DesktopWebSocketNotificationService? createWebSocketService() {
    if (AppConfig.notificationStrategy == NotificationStrategy.websocket) {
      return DesktopWebSocketNotificationService();
    }
    return null;
  }

  static DesktopPollingNotificationService? createPollingService({
    required Function(Map<String, dynamic>) onNotification,
    required Function apiCall,
  }) {
    if (AppConfig.notificationStrategy == NotificationStrategy.polling) {
      return DesktopPollingNotificationService(
        onNotification: onNotification,
        apiCall: apiCall,
      );
    }
    return null;
  }
}
