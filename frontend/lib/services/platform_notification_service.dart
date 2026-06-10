import 'notification_service.dart';

class PlatformNotificationService {
  final NotificationService _service = NotificationService();

  Future<void> init({
    required void Function(Map<String, dynamic>) onNotificationReceived,
  }) {
    return _service.init(onNotificationTap: onNotificationReceived);
  }

  Future<bool> requestPermissions() => _service.requestPermissions();

  Future<void> dispose() => _service.dispose();
}
