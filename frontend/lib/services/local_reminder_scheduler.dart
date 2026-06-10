import '../models/event.dart';
import '../services/notification_service.dart';
import '../services/local_event_storage.dart';

/// Service pour programmer les rappels locaux des événements existants
class LocalReminderScheduler {
  static final LocalReminderScheduler _instance =
      LocalReminderScheduler._internal();

  factory LocalReminderScheduler() => _instance;

  LocalReminderScheduler._internal();

  /// Initialise les rappels pour tous les événements non expirés
  Future<void> initializeReminders() async {
    try {
      print('[SCHEDULER] Initialisation des rappels...');

      // Récupère tous les événements depuis la base locale
      final storage = LocalEventStorage();
      final events = await storage.getAllEvents();

      if (events.isEmpty) {
        print('[SCHEDULER] Aucun événement trouvé.');
        return;
      }

      final now = DateTime.now();
      int scheduledCount = 0;
      int skippedCount = 0;

      // Programme les rappels pour chaque événement
      for (final event in events) {
        // Vérifie que l'événement n'est pas expiré
        if (event.date.isBefore(now)) {
          print('[SCHEDULER] ⏭️  Événement expiré: "${event.title}"');
          skippedCount++;
          continue;
        }

        // Programme les rappels (48h, 12h et 1h avant)
        for (final hoursBefore in [48, 12, 1]) {
          try {
            await NotificationService().scheduleReminder(event, hoursBefore);
            scheduledCount++;
          } catch (e) {
            print('[SCHEDULER] ✗ Erreur programmation rappel: $e');
            skippedCount++;
          }
        }
      }

      print(
          '[SCHEDULER] ✓ Initialisation complétée: $scheduledCount rappels programmés, $skippedCount ignorés');
    } catch (e) {
      print('[SCHEDULER] ✗ Erreur initialisation reminders: $e');
    }
  }

  /// Reprogramme les rappels après un changement d'événement
  Future<void> reschedulForEvent(Event event) async {
    try {
      print('[SCHEDULER] Reprogrammation rappels pour: "${event.title}"');

      // Annule les anciens rappels
      await NotificationService().cancelReminders(event);

      final now = DateTime.now();

      // Réinsère les nouveaux rappels
      if (event.date.isAfter(now)) {
        for (final hoursBefore in [48, 12, 1]) {
          await NotificationService().scheduleReminder(event, hoursBefore);
        }
        print('[SCHEDULER] ✓ Rappels reprogrammés pour: "${event.title}"');
      }
    } catch (e) {
      print('[SCHEDULER] ✗ Erreur reprogrammation: $e');
    }
  }

  /// Annule tous les rappels d'un événement
  Future<void> cancelForEvent(Event event) async {
    try {
      await NotificationService().cancelReminders(event);
      print('[SCHEDULER] ✓ Rappels annulés pour: "${event.title}"');
    } catch (e) {
      print('[SCHEDULER] ✗ Erreur annulation: $e');
    }
  }
}
