import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;

import '../config/app_config.dart';
import '../models/event.dart';
import '../models/faculty.dart';
import '../models/file.dart';
import '../models/user.dart';
import 'backend_api_service.dart';
import 'file_cache_service.dart';

class ApiService {
  ApiService() {
    if (!AppConfig.useBackendDataApi) {
      _firestore = FirebaseFirestore.instance;
    }
  }

  FirebaseFirestore? _firestore;
  final BackendApiService _backendApi = BackendApiService();
  final FileCacheService _fileCache = FileCacheService();

  bool get _useBackend => AppConfig.useBackendDataApi;

  String? _extractStoragePathFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;

    try {
      final parsed = Uri.parse(url);

      if (parsed.path.startsWith('/api/storage/object/')) {
        return Uri.decodeComponent(
          parsed.path.replaceFirst('/api/storage/object/', ''),
        );
      }

      if (parsed.host.contains('firebasestorage.googleapis.com')) {
        final match = RegExp(r'/o/(.+)$').firstMatch(parsed.path);
        if (match != null) {
          return Uri.decodeComponent(match.group(1)!);
        }
      }
    } catch (_) {
      return null;
    }

    if (url.startsWith('gs://')) {
      final parts = url.replaceFirst('gs://', '').split('/');
      if (parts.length > 1) {
        parts.removeAt(0);
        return parts.join('/');
      }
    }

    return null;
  }

  Future<FileModel> normalizeFileForCurrentPlatform(FileModel file) async {
    if (_useBackend) return file;

    if (file.url.isNotEmpty &&
        file.url.contains('firebasestorage.googleapis.com')) {
      return file;
    }

    final storagePath =
        file.storagePath ?? _extractStoragePathFromUrl(file.url);
    if (storagePath == null || storagePath.isEmpty) {
      return file;
    }

    try {
      final downloadUrl = await firebase_storage.FirebaseStorage.instance
          .ref()
          .child(storagePath)
          .getDownloadURL();

      return file.copyWith(
        url: downloadUrl,
        storagePath: storagePath,
      );
    } catch (_) {
      return file.copyWith(storagePath: storagePath);
    }
  }

  Future<List<FileModel>> normalizeFilesForCurrentPlatform(
    List<FileModel> files,
  ) async {
    if (_useBackend || files.isEmpty) return files;
    return Future.wait(files.map(normalizeFileForCurrentPlatform));
  }

  Future<List<Faculty>> getFaculties() async {
    if (_useBackend) {
      return _backendApi.getFaculties();
    }

    try {
      final snapshot = await _firestore!
          .collection('faculties')
          .limit(50)
          .get()
          .timeout(const Duration(seconds: 10));

      return snapshot.docs.map((doc) => Faculty.fromMap(doc.data())).toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<Event>> getEvents({
    String? faculty,
    String? level,
    String? field,
  }) async {
    if (_useBackend) {
      final events = await _backendApi.getEvents(
        faculty: faculty,
        level: level,
        field: field,
      );
      return events.map(Event.fromMap).toList();
    }

    try {
      Query globalQuery =
          _firestore!.collection('events').where('isGlobal', isEqualTo: true);
      final globalSnapshot = await globalQuery
          .orderBy('date', descending: true)
          .get()
          .timeout(const Duration(seconds: 10));

      Query specificQuery =
          _firestore!.collection('events').where('isGlobal', isEqualTo: false);
      if (faculty != null && faculty.isNotEmpty) {
        specificQuery = specificQuery.where('faculty', isEqualTo: faculty);
      }
      if (level != null && level.isNotEmpty) {
        specificQuery = specificQuery.where('level', isEqualTo: level);
      }
      if (field != null && field.isNotEmpty) {
        specificQuery = specificQuery.where('field', isEqualTo: field);
      }

      final specificSnapshot = await specificQuery
          .orderBy('date', descending: true)
          .get()
          .timeout(const Duration(seconds: 10));

      final globalEvents = globalSnapshot.docs
          .map((doc) => Event.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
      final specificEvents = specificSnapshot.docs
          .map((doc) => Event.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
      globalEvents.sort((a, b) => b.date.compareTo(a.date));
      specificEvents.sort((a, b) => b.date.compareTo(a.date));
      return [...globalEvents, ...specificEvents];
    } catch (_) {
      return [];
    }
  }

  Future<FileModel?> getFileById(String fileId) async {
    if (_useBackend) {
      try {
        final file = await _backendApi.getFile(fileId);
        final parsedFile = FileModel.fromMap(file);
        await _fileCache.cacheFile(parsedFile);
        return parsedFile;
      } catch (_) {
        return _fileCache.getCachedFile(fileId);
      }
    }

    try {
      final doc = await _firestore!.collection('files').doc(fileId).get();
      if (!doc.exists) return null;
      final data =
          Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
      final file = FileModel.fromMap(data);
      final normalizedFile = await normalizeFileForCurrentPlatform(file);
      await _fileCache.cacheFile(normalizedFile);
      return normalizedFile;
    } catch (_) {
      return _fileCache.getCachedFile(fileId);
    }
  }

  /// Récupère une URL de téléchargement à durée de vie courte.
  ///
  /// En backend, on évite ainsi de dépendre d'une URL mise en cache
  /// qui aurait expiré entre deux ouvertures de l'application.
  Future<String> getFileDownloadUrl(String fileId) async {
    if (_useBackend) {
      return _backendApi.getFileDownloadUrl(fileId);
    }

    final file = await getFileById(fileId);
    if (file == null) {
      throw Exception('File not found');
    }
    return file.url;
  }

  Future<void> incrementFileViewCount(String fileId, String userId) async {
    if (_useBackend) {
      await _backendApi.incrementFileViewCount(fileId, userId);
      return;
    }

    final docRef = _firestore!.collection('files').doc(fileId);
    await _firestore!.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;
      final data = snapshot.data() as Map<String, dynamic>;
      final viewedBy = List<String>.from(data['viewedBy'] ?? []);
      final currentCount = data['viewCount'] ?? 0;
      if (!viewedBy.contains(userId)) {
        viewedBy.add(userId);
        transaction.update(docRef, {
          'viewedBy': viewedBy,
          'viewCount': currentCount + 1,
        });
      }
    });
  }

  Future<void> markFileAsOpened(String fileId, String userId) async {
    if (_useBackend) {
      await _backendApi.incrementFileViewCount(fileId, userId);
      return;
    }

    await _firestore!.collection('files').doc(fileId).update({
      'lastOpened': DateTime.now().toIso8601String(),
    });
  }

  Future<List<FileModel>> getFiles({
    String? faculty,
    String? level,
    String? field,
    String? unit,
    String? type,
  }) async {
    if (_useBackend) {
      final files = await _backendApi.getFiles(
        faculty: faculty,
        level: level,
        field: field,
        unit: unit,
        type: type,
      );
      return files.map(FileModel.fromMap).toList();
    }

    try {
      Query query = _firestore!.collection('files');
      if (faculty != null && faculty.isNotEmpty) {
        query = query.where('faculty', isEqualTo: faculty);
      }
      if (level != null && level.isNotEmpty) {
        query = query.where('level', isEqualTo: level);
      }
      if (field != null && field.isNotEmpty) {
        query = query.where('field', isEqualTo: field);
      }
      if (unit != null && unit.isNotEmpty) {
        query = query.where('unit', isEqualTo: unit);
      }
      if (type != null && type.isNotEmpty) {
        query = query.where('type', isEqualTo: type);
      }

      final snapshot = await query
          .orderBy('uploadedAt', descending: true)
          .get()
          .timeout(const Duration(seconds: 10));

      final files = snapshot.docs
          .map((doc) => FileModel.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
      return normalizeFilesForCurrentPlatform(files);
    } catch (_) {
      return [];
    }
  }

  Future<List<UserModel>> getDelegates() async {
    if (_useBackend) {
      return _backendApi.getUsers(role: 'delegate');
    }

    try {
      final snapshot = await _firestore!
          .collection('users')
          .where('role', isEqualTo: 'delegate')
          .get()
          .timeout(const Duration(seconds: 10));

      return snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<List<UserModel>> getAllUsers() async {
    if (_useBackend) {
      return _backendApi.getUsers();
    }

    try {
      final snapshot = await _firestore!
          .collection('users')
          .get()
          .timeout(const Duration(seconds: 10));

      return snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> updateUserRole(String userId, UserRole role) async {
    if (_useBackend) {
      await _backendApi.updateUserRole(userId, role);
      return;
    }

    await _firestore!.collection('users').doc(userId).update({
      'role': role.toString().split('.').last,
    });
  }

  Future<void> updateUserAcademicInfo(
    String userId,
    String faculty,
    String level,
    String field,
  ) async {
    if (_useBackend) {
      await _backendApi.updateUserProfile(userId, {
        'faculty': faculty,
        'level': level,
        'field': field,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      return;
    }

    await _firestore!.collection('users').doc(userId).update({
      'faculty': faculty,
      'level': level,
      'field': field,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateUser(UserModel user) async {
    if (_useBackend) {
      await _backendApi.updateUserProfile(user.id, user.toMap());
      return;
    }

    await _firestore!.collection('users').doc(user.id).update(user.toMap());
  }

  Future<void> updateFileReadingProgress(
    String fileId,
    String userId,
    double progress,
  ) async {
    if (_useBackend) {
      await _backendApi.updateReadingProgress(fileId, userId, progress);
      return;
    }

    await _firestore!.collection('files').doc(fileId).update({
      'readingProgress.$userId': progress,
      'lastOpened': DateTime.now().toIso8601String(),
    });
  }

  Future<void> addFile(FileModel file) async {
    if (_useBackend) {
      await _backendApi.createFile(file);
      return;
    }

    await _firestore!.collection('files').doc(file.id).set(file.toMap());
  }

  Future<void> deleteFile(String fileId) async {
    if (_useBackend) {
      await _backendApi.deleteFile(fileId);
      return;
    }

    await _firestore!.collection('files').doc(fileId).delete();
  }

  Future<void> toggleFileFavorite(String fileId, String userId) async {
    if (_useBackend) {
      await _backendApi.toggleFavorite(fileId, userId);
      return;
    }

    final doc = await _firestore!.collection('files').doc(fileId).get();
    if (!doc.exists) return;
    final data = doc.data()!;
    final favorites = List<dynamic>.from(data['favorites'] ?? []);
    if (favorites.contains(userId)) {
      favorites.remove(userId);
    } else {
      favorites.add(userId);
    }
    await _firestore!.collection('files').doc(fileId).update({
      'favorites': favorites,
    });
  }

  Future<void> addEvent(Event event) async {
    if (_useBackend) {
      await _backendApi.createEvent(event);
      return;
    }

    await _firestore!.collection('events').doc(event.id).set(event.toMap());
  }

  Future<void> deleteEvent(String eventId) async {
    if (_useBackend) {
      await _backendApi.deleteEvent(eventId);
      return;
    }

    final doc = await _firestore!.collection('events').doc(eventId).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      final imageUrls = List<String>.from(data['imageUrls'] ?? []);
      for (final url in imageUrls) {
        try {
          final ref = firebase_storage.FirebaseStorage.instance.refFromURL(url);
          await ref.delete();
        } catch (_) {}
      }
      await _firestore!.collection('events').doc(eventId).delete();
    }
  }

  Future<void> deleteUser(String userId) async {
    if (_useBackend) {
      await _backendApi.deleteUser(userId);
      return;
    }

    await _firestore!.collection('users').doc(userId).delete();
  }

  Future<List<UserModel>> getAdmins() async {
    if (_useBackend) {
      return _backendApi.getUsers(role: 'admin');
    }

    try {
      final snapshot = await _firestore!
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();
      return snapshot.docs
          .map((doc) => UserModel.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteFaculty(String facultyId) async {
    if (_useBackend) {
      await _backendApi.deleteFaculty(facultyId);
      return;
    }
    await _firestore!.collection('faculties').doc(facultyId).delete();
  }

  Future<void> addLevel(String facultyId, String level) async {
    if (_useBackend) {
      await _backendApi.addLevel(facultyId, level);
      return;
    }

    await _firestore!.collection('faculties').doc(facultyId).update({
      'levels': FieldValue.arrayUnion([level]),
    });
  }

  Future<void> removeLevel(String facultyId, String level) async {
    if (_useBackend) {
      await _backendApi.removeLevel(facultyId, level);
      return;
    }

    await _firestore!.collection('faculties').doc(facultyId).update({
      'levels': FieldValue.arrayRemove([level]),
    });
  }

  Future<void> deleteUserData(String userId) async {
    if (_useBackend) {
      await _backendApi.deleteUser(userId);
      return;
    }
    await _firestore!.collection('users').doc(userId).delete();
  }

  Future<void> addField(String facultyId, String level, String field) async {
    if (_useBackend) {
      await _backendApi.addField(facultyId, level, field);
      return;
    }

    final docRef = _firestore!.collection('faculties').doc(facultyId);
    await _firestore!.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;
      final data = snapshot.data() as Map<String, dynamic>;
      final fieldsData = data['fields'] as Map<String, dynamic>? ?? {};
      final fields = fieldsData.map(
        (key, value) => MapEntry(
          key,
          value is List ? value.map((e) => e.toString()).toList() : <String>[],
        ),
      );
      final levelFields = List<String>.from(fields[level] ?? const []);
      if (!levelFields.contains(field)) {
        levelFields.add(field);
      }
      fields[level] = levelFields;
      transaction.update(docRef, {'fields': fields});
    });
  }

  Future<void> removeField(
    String facultyId,
    String level,
    String field,
  ) async {
    if (_useBackend) {
      await _backendApi.removeField(facultyId, level, field);
      return;
    }

    final docRef = _firestore!.collection('faculties').doc(facultyId);
    await _firestore!.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;
      final data = snapshot.data() as Map<String, dynamic>;
      final fieldsData = data['fields'] as Map<String, dynamic>? ?? {};
      final fields = fieldsData.map(
        (key, value) => MapEntry(
          key,
          value is List ? value.map((e) => e.toString()).toList() : <String>[],
        ),
      );
      if (fields.containsKey(level)) {
        fields[level] = fields[level]!.where((f) => f != field).toList();
      }
      transaction.update(docRef, {'fields': fields});
    });
  }

  Future<void> addUnit(
    String facultyId,
    String level,
    String field,
    String unit,
  ) async {
    if (_useBackend) {
      await _backendApi.addUnit(facultyId, level, field, unit);
      return;
    }

    final docRef = _firestore!.collection('faculties').doc(facultyId);
    await _firestore!.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;
      final data = snapshot.data() as Map<String, dynamic>;
      final unitsData = data['units'] as Map<String, dynamic>? ?? {};
      final units = <String, Map<String, List<String>>>{};
      unitsData.forEach((levelKey, levelValue) {
        if (levelValue is Map) {
          units[levelKey] = (levelValue as Map).map(
            (fieldKey, fieldValue) => MapEntry(
              fieldKey.toString(),
              fieldValue is List
                  ? fieldValue.map((e) => e.toString()).toList()
                  : <String>[],
            ),
          );
        }
      });
      final levelUnits = units[level] ?? <String, List<String>>{};
      final fieldUnits = List<String>.from(levelUnits[field] ?? const []);
      if (!fieldUnits.contains(unit)) {
        fieldUnits.add(unit);
      }
      levelUnits[field] = fieldUnits;
      units[level] = levelUnits;
      transaction.update(docRef, {'units': units});
    });
  }

  Future<void> removeUnit(
    String facultyId,
    String level,
    String field,
    String unit,
  ) async {
    if (_useBackend) {
      await _backendApi.removeUnit(facultyId, level, field, unit);
      return;
    }

    final docRef = _firestore!.collection('faculties').doc(facultyId);
    await _firestore!.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;
      final data = snapshot.data() as Map<String, dynamic>;
      final unitsData = data['units'] as Map<String, dynamic>? ?? {};
      final units = <String, Map<String, List<String>>>{};
      unitsData.forEach((levelKey, levelValue) {
        if (levelValue is Map) {
          units[levelKey] = (levelValue as Map).map(
            (fieldKey, fieldValue) => MapEntry(
              fieldKey.toString(),
              fieldValue is List
                  ? fieldValue.map((e) => e.toString()).toList()
                  : <String>[],
            ),
          );
        }
      });
      if (units.containsKey(level) && units[level]!.containsKey(field)) {
        units[level]![field] =
            units[level]![field]!.where((u) => u != unit).toList();
      }
      transaction.update(docRef, {'units': units});
    });
  }

  Future<void> updateLastActivity(String userId) async {
    if (_useBackend) {
      await _backendApi.updateLastActivity(userId);
      return;
    }

    await _firestore!.collection('users').doc(userId).update({
      'lastActivity': DateTime.now().toIso8601String(),
    });
  }

  Future<List<FileModel>> getFilesPaginated({
    String? faculty,
    String? level,
    String? field,
    String? unit,
    String? type,
    int page = 0,
    int pageSize = 10,
  }) async {
    if (_useBackend) {
      final files = await _backendApi.getFiles(
        faculty: faculty,
        level: level,
        field: field,
        unit: unit,
        type: type,
        page: page,
        pageSize: pageSize,
      );
      return files.map(FileModel.fromMap).toList();
    }

    try {
      Query query = _firestore!.collection('files');
      if (faculty != null && faculty.isNotEmpty) {
        query = query.where('faculty', isEqualTo: faculty);
      }
      if (level != null && level.isNotEmpty) {
        query = query.where('level', isEqualTo: level);
      }
      if (field != null && field.isNotEmpty) {
        query = query.where('field', isEqualTo: field);
      }
      if (unit != null && unit.isNotEmpty) {
        query = query.where('unit', isEqualTo: unit);
      }
      if (type != null && type.isNotEmpty) {
        query = query.where('type', isEqualTo: type);
      }

      final snapshot = await query
          .orderBy('uploadedAt', descending: true)
          .get()
          .timeout(const Duration(seconds: 10));

      final allFiles = snapshot.docs
          .map((doc) => FileModel.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
      final normalizedFiles = await normalizeFilesForCurrentPlatform(allFiles);

      final start = page * pageSize;
      if (start >= normalizedFiles.length) return [];
      final end = (start + pageSize) > normalizedFiles.length
          ? normalizedFiles.length
          : start + pageSize;
      return normalizedFiles.sublist(start, end);
    } catch (_) {
      return [];
    }
  }
}
