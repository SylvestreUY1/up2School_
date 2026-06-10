import '../models/event.dart';
import '../models/file.dart';
import 'api_service.dart';
import 'backend_api_service.dart';

class PlatformDataService {
  final ApiService _apiService = ApiService();
  final BackendApiService _backendApi = BackendApiService();

  Future<List<FileModel>> getFiles({
    String? faculty,
    String? level,
    String? field,
    String? unit,
    String? type,
  }) {
    return _apiService.getFiles(
      faculty: faculty,
      level: level,
      field: field,
      unit: unit,
      type: type,
    );
  }

  Future<FileModel?> getFile(String fileId) => _apiService.getFileById(fileId);

  Future<String> getFileDownloadUrl(String fileId) async {
    final file = await _apiService.getFileById(fileId);
    return file?.url ?? '';
  }

  Stream<List<FileModel>>? getFilesStream({
    required String faculty,
    required String level,
    required String field,
  }) {
    return null;
  }

  Future<List<Event>> getEvents({
    String? faculty,
    String? level,
    String? field,
  }) {
    return _apiService.getEvents(
      faculty: faculty,
      level: level,
      field: field,
    );
  }

  Future<Event?> getEvent(String eventId) async {
    final events = await _apiService.getEvents();
    try {
      return events.firstWhere((event) => event.id == eventId);
    } catch (_) {
      return null;
    }
  }

  Stream<List<Event>>? getEventsStream() {
    return null;
  }

  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final user = await _backendApi.getUserProfile(userId);
      return user.toMap();
    } catch (_) {
      return null;
    }
  }

  Future<void> updateUserProfile(
    String userId,
    Map<String, dynamic> data,
  ) async {
    await _backendApi.updateUserProfile(userId, data);
  }
}
