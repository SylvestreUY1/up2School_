import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/file.dart';

class FileCacheService {
  static const String _boxName = 'fileCache';
  static const String _metadataBoxName = 'fileCacheMetadata';
  static const Duration _ttl = Duration(days: 60); // fraicheur reseau

  Box<FileModel>? _fileBox;
  Box<dynamic>? _metadataBox;
  Future<void>? _initFuture;

  FileCacheService._internal();
  static final FileCacheService _instance = FileCacheService._internal();
  factory FileCacheService() => _instance;

  Future<void> init() async {
    if (_fileBox != null && _metadataBox != null) return;

    _initFuture ??= _openBoxes();
    try {
      await _initFuture;
    } catch (_) {
      _initFuture = null;
      rethrow;
    }
  }

  Future<void> _openBoxes() async {
    _fileBox = Hive.isBoxOpen(_boxName)
        ? Hive.box<FileModel>(_boxName)
        : await Hive.openBox<FileModel>(_boxName);
    _metadataBox = Hive.isBoxOpen(_metadataBoxName)
        ? Hive.box(_metadataBoxName)
        : await Hive.openBox(_metadataBoxName);
  }

  Future<void> _ensureInitialized() => init();

  Box<FileModel> get _files => _fileBox!;
  Box<dynamic> get _metadata => _metadataBox!;

  Future<Map<String, dynamic>?> _readMetadata(String key) async {
    await _ensureInitialized();
    final raw = _metadata.get(key);
    if (raw is! Map) {
      return null;
    }

    try {
      return Map<String, dynamic>.from(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheFile(FileModel file) async {
    await _ensureInitialized();
    await _files.put(file.id, file);
  }

  Future<void> cacheFiles(List<FileModel> files) async {
    await _ensureInitialized();
    for (final file in files) {
      await _files.put(file.id, file);
    }
  }

  Future<FileModel?> getCachedFile(String fileId) async {
    await _ensureInitialized();
    return _files.get(fileId);
  }

  String _getCacheKey({
    required String faculty,
    required String level,
    required String field,
    required String unit,
    String? type,
    int page = 0,
    int pageSize = 20,
  }) {
    return '${faculty}_${level}_${field}_${unit}_${type ?? 'all'}_page${page}_size$pageSize';
  }

  Future<List<FileModel>?> getCachedPage({
    required String faculty,
    required String level,
    required String field,
    required String unit,
    String? type,
    int page = 0,
    int pageSize = 20,
  }) async {
    final key = _getCacheKey(
      faculty: faculty,
      level: level,
      field: field,
      unit: unit,
      type: type,
      page: page,
      pageSize: pageSize,
    );
    final cachedMap = await _readMetadata(key);
    if (cachedMap == null) {
      await _metadata.delete(key);
      return null;
    }

    final timestamp = cachedMap['timestamp'] as int;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - timestamp > _ttl.inMilliseconds) {
      await _metadata.delete(key);
      return null;
    }

    final fileIds =
        (cachedMap['fileIds'] as List?)?.map((id) => id.toString()).toList() ??
            const <String>[];
    final files = <FileModel>[];
    for (final id in fileIds) {
      final file = _files.get(id);
      if (file != null) files.add(file);
    }
    return files;
  }

  /// Récupère le cache MÊME S'IL EST EXPIRÉ (pour fallback offline)
  Future<List<FileModel>?> getCachedPageIgnoreTTL({
    required String faculty,
    required String level,
    required String field,
    required String unit,
    String? type,
    int page = 0,
    int pageSize = 20,
  }) async {
    final key = _getCacheKey(
      faculty: faculty,
      level: level,
      field: field,
      unit: unit,
      type: type,
      page: page,
      pageSize: pageSize,
    );
    final cachedMap = await _readMetadata(key);
    if (cachedMap == null) {
      return null;
    }

    final fileIds =
        (cachedMap['fileIds'] as List?)?.map((id) => id.toString()).toList() ??
            const <String>[];
    final files = <FileModel>[];
    for (final id in fileIds) {
      final file = _files.get(id);
      if (file != null) files.add(file);
    }
    return files.isNotEmpty ? files : null;
  }

  Future<void> cachePage({
    required String faculty,
    required String level,
    required String field,
    required String unit,
    String? type,
    int page = 0,
    int pageSize = 20,
    required List<FileModel> files,
  }) async {
    final key = _getCacheKey(
      faculty: faculty,
      level: level,
      field: field,
      unit: unit,
      type: type,
      page: page,
      pageSize: pageSize,
    );
    await cacheFiles(files);
    // Typage explicite de la map
    await _metadata.put(key, <String, dynamic>{
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'fileIds': files.map((e) => e.id).toList(),
    });
  }

  Future<void> invalidateAll() async {
    await _ensureInitialized();
    await _files.clear();
    await _metadata.clear();
  }

  Future<void> invalidateFilters({
    required String faculty,
    required String level,
    required String field,
    required String unit,
    String? type,
  }) async {
    final prefix = _getCacheKey(
      faculty: faculty,
      level: level,
      field: field,
      unit: unit,
      type: type,
      page: 0,
      pageSize: 0,
    ).split('_page')[0];
    await _ensureInitialized();
    final keysToDelete = _metadata.keys
        .where((key) => key.toString().startsWith(prefix))
        .toList();
    for (final key in keysToDelete) {
      await _metadata.delete(key);
    }
  }

  Future<void> cleanExpiredCache() async {
    await _ensureInitialized();
    final keysToDelete = <String>[];

    for (final key in _metadata.keys) {
      final entryMap = await _readMetadata(key.toString());
      if (entryMap == null) {
        keysToDelete.add(key.toString());
        continue;
      }

      final fileIds = entryMap['fileIds'];
      if (fileIds is! List) {
        keysToDelete.add(key.toString());
      }
    }

    for (final key in keysToDelete) {
      await _metadata.delete(key);
    }
  }
}
