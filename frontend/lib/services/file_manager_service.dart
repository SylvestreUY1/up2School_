import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../models/file.dart';
import '../models/user.dart';
import '../utils/permissions.dart';
import '../utils/file_filters.dart';
import '../utils/document_types.dart';
import 'storage_service_interface.dart';
import 'api_service.dart';
import 'file_cache_service.dart';

class FileManagerService {
  final StorageService _storageService;
  final ApiService _apiService = ApiService();
  final Dio _dio = Dio();
  final FileCacheService _cache = FileCacheService();

  FileManagerService({required StorageService storageService})
      : _storageService = storageService;

  // ==================== MÉTHODES AVEC CACHE ====================

  /// Centralise le répertoire applicatif pour éviter les divergences
  /// entre téléchargement, ouverture et suppression locale.
  Future<String> _documentsPath() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  /// Les listes de fichiers peuvent être relues depuis le cache pendant
  /// plusieurs semaines. En backend, l'URL embarquée peut donc contenir
  /// un jeton d'accès périmé. On redemande une URL fraîche juste avant
  /// l'ouverture ou le téléchargement effectif du document.
  Future<String> getFreshFileUrl(FileModel file) async {
    if (!AppConfig.useBackendForProtectedFiles || file.id.isEmpty) {
      final normalized =
          await _apiService.normalizeFileForCurrentPlatform(file);
      return normalized.url;
    }

    return _apiService.getFileDownloadUrl(file.id);
  }

  /// Récupère une page de fichiers avec cache (TTL 2 mois)
  /// Fallback au cache même expiré en cas d'erreur d'authentification
  Future<List<FileModel>> getFilesWithPagination({
    required String faculty,
    required String level,
    required String field,
    required String unit,
    String? type,
    int page = 0,
    int pageSize = 20,
    String? userId,
    FileFilter filter = FileFilter.all,
    bool forceRefresh = false,
  }) async {
    final normalizedType = normalizeDocumentType(type);

    // 1. Essayer le cache valide d'abord, meme avec backend protege.
    if (!forceRefresh) {
      final cached = await _cache.getCachedPage(
        faculty: faculty,
        level: level,
        field: field,
        unit: unit,
        type: normalizedType,
        page: page,
        pageSize: pageSize,
      );
      if (cached != null) {
        final normalizedCached =
            await _apiService.normalizeFilesForCurrentPlatform(cached);
        return _applyFilters(normalizedCached, filter, userId);
      }
    }

    // 2. Récupérer depuis Firestore / API Backend
    try {
      final files = await _apiService.getFilesPaginated(
        faculty: faculty,
        level: level,
        field: field,
        unit: unit,
        type: normalizedType,
        page: page,
        pageSize: pageSize,
      );

      await _cache.cachePage(
        faculty: faculty,
        level: level,
        field: field,
        unit: unit,
        type: normalizedType,
        page: page,
        pageSize: pageSize,
        files: files,
      );

      return _applyFilters(files, filter, userId);
    } catch (e) {
      // 3. En cas d'erreur (notamment 401 - token invalide),
      // retourner le cache expiré comme fallback offline
      print('⚠️  Erreur API: $e - Utilisation du cache comme fallback');

      final cachedFallback = await _cache.getCachedPageIgnoreTTL(
        faculty: faculty,
        level: level,
        field: field,
        unit: unit,
        type: normalizedType,
        page: page,
        pageSize: pageSize,
      );

      if (cachedFallback != null && cachedFallback.isNotEmpty) {
        print('✅ Cache utilisé en fallback offline');
        final normalizedCached =
            await _apiService.normalizeFilesForCurrentPlatform(cachedFallback);
        return _applyFilters(normalizedCached, filter, userId);
      }

      // Sinon, re-lever l'exception
      rethrow;
    }
  }

  /// Lit immédiatement une page depuis le cache local.
  ///
  /// Utile pour afficher quelque chose sans attendre le réseau, puis lancer
  /// une synchronisation silencieuse en arrière-plan.
  Future<List<FileModel>> getCachedFilesPage({
    required String faculty,
    required String level,
    required String field,
    required String unit,
    String? type,
    int page = 0,
    int pageSize = 20,
    String? userId,
    FileFilter filter = FileFilter.all,
    bool ignoreTTL = true,
  }) async {
    final normalizedType = normalizeDocumentType(type);

    final cached = ignoreTTL
        ? await _cache.getCachedPageIgnoreTTL(
            faculty: faculty,
            level: level,
            field: field,
            unit: unit,
            type: normalizedType,
            page: page,
            pageSize: pageSize,
          )
        : await _cache.getCachedPage(
            faculty: faculty,
            level: level,
            field: field,
            unit: unit,
            type: normalizedType,
            page: page,
            pageSize: pageSize,
          );

    if (cached == null || cached.isEmpty) {
      return const <FileModel>[];
    }

    final normalizedCached =
        await _apiService.normalizeFilesForCurrentPlatform(cached);
    return _applyFilters(normalizedCached, filter, userId);
  }

  List<FileModel> _applyFilters(
      List<FileModel> files, FileFilter filter, String? userId) {
    switch (filter) {
      case FileFilter.favorites:
        if (userId == null) return [];
        return files.where((file) => file.favorites.contains(userId)).toList();
      case FileFilter.recent:
        return files.where((file) => file.lastOpened != null).toList()
          ..sort((a, b) => b.lastOpened!.compareTo(a.lastOpened!));
      case FileFilter.all:
        return files;
    }
  }

  // ==================== MÉTHODES D'AJOUT / SUPPRESSION ====================

  Future<void> addFile({
    required File file,
    required String fileName,
    required String name,
    required String faculty,
    required String level,
    required String field,
    required String unit,
    required String type,
    required UserModel user,
  }) async {
    if (user.role != UserRole.delegate && user.role != UserRole.admin) {
      throw 'Seuls les délégués et administrateurs peuvent ajouter des fichiers';
    }
    if (user.role == UserRole.delegate) {
      if (user.faculty == null || user.level == null || user.field == null) {
        throw 'Vos informations académiques sont incomplètes';
      }
      if (user.faculty != faculty ||
          user.level != level ||
          user.field != field) {
        throw 'Vous ne pouvez ajouter des fichiers que dans votre propre filière (${user.field}, Niveau ${user.level})';
      }
    }

    final fileUrl =
        await _storageService.uploadFile(file, 'files/${user.id}', fileName);
    final fileSize = file.lengthSync();

    final newFile = FileModel(
      id: 'file_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      url: fileUrl,
      fileName: fileName,
      fileType: fileName.split('.').last.toLowerCase(),
      faculty: faculty,
      level: level,
      field: field,
      unit: unit,
      type: normalizeDocumentType(type),
      uploadedAt: DateTime.now(),
      uploadedBy: user.id,
      favorites: [],
      downloadCount: 0,
      viewCount: 0,
      readingProgress: {},
      lastOpened: null,
      viewedBy: [],
      size: fileSize,
    );

    await _apiService.addFile(newFile);

    // Invalider le cache pour cette combinaison de filtres
    await _cache.invalidateFilters(
      faculty: faculty,
      level: level,
      field: field,
      unit: unit,
      type: normalizeDocumentType(type),
    );
  }

  Future<void> deleteFile({
    required FileModel file,
    required UserModel user,
  }) async {
    // Vérification des droits
    if (user.role != UserRole.admin && user.role != UserRole.delegate) {
      throw 'Vous n\'avez pas les permissions nécessaires';
    }
    if (!Permissions.canDeleteFile(user, file)) {
      throw 'Vous ne pouvez supprimer que les fichiers autorisés pour votre rôle';
    }

    try {
      if (AppConfig.useBackendStorage) {
        await _apiService.deleteFile(file.id);
      } else {
        final resolvedFile =
            await _apiService.normalizeFileForCurrentPlatform(file);
        await _storageService.deleteFile(resolvedFile.url);
        await _apiService.deleteFile(file.id);
      }

      // Supprimer la copie locale si elle existe
      if (await isFileDownloaded(file)) {
        final localPath = '${await _documentsPath()}/${file.fileName}';
        final localFile = File(localPath);
        if (await localFile.exists()) {
          await localFile.delete();
        }
      }

      // Invalider le cache pour cette combinaison de filtres
      await _cache.invalidateFilters(
        faculty: file.faculty,
        level: file.level,
        field: file.field,
        unit: file.unit,
        type: normalizeDocumentType(file.type),
      );
    } catch (e) {
      print('❌ Erreur suppression fichier: $e');
      rethrow;
    }
  }

  // ==================== AUTRES MÉTHODES (sans cache) ====================

  Future<void> deleteLocalFile(FileModel file) async {
    try {
      final localPath = '${await _documentsPath()}/${file.fileName}';
      final localFile = File(localPath);
      if (await localFile.exists()) {
        await localFile.delete();
      } else {
        throw 'Fichier local introuvable';
      }
    } catch (e) {
      print('❌ Erreur suppression locale: $e');
      rethrow;
    }
  }

  Future<void> updateReadingProgress({
    required String fileId,
    required String userId,
    required double progress,
  }) async {
    try {
      await _apiService.updateFileReadingProgress(fileId, userId, progress);
    } catch (e) {
      print('Erreur mise à jour progression: $e');
    }
  }

  Future<void> incrementViewCount(String fileId, String userId) async {
    try {
      await _apiService.incrementFileViewCount(fileId, userId);
    } catch (e) {
      print('Erreur incrémentation vues: $e');
    }
  }

  Future<void> toggleFavorite({
    required String fileId,
    required String userId,
  }) async {
    try {
      await _apiService.toggleFileFavorite(fileId, userId);
    } catch (e) {
      print('Erreur toggle favori: $e');
      rethrow;
    }
  }

  Future<String?> downloadFile(
    FileModel file, {
    required UserModel? user,
    ProgressCallback? onReceiveProgress,
  }) async {
    if (kIsWeb) return null;
    if (!Permissions.canDownloadFile(user, file)) {
      throw user == null || user.role == UserRole.guest
          ? 'Connectez-vous pour télécharger des fichiers.'
          : 'Vous ne pouvez télécharger que les fichiers de votre filière et de votre niveau.';
    }
    try {
      final resolvedFile =
          await _apiService.normalizeFileForCurrentPlatform(file);
      final remoteUrl = await getFreshFileUrl(resolvedFile);
      final filePath = '${await _documentsPath()}/${resolvedFile.fileName}';
      await _dio.download(
        remoteUrl,
        filePath,
        onReceiveProgress: onReceiveProgress ??
            (received, total) {
              if (total != -1) {
                print('${(received / total * 100).toStringAsFixed(0)}%');
              }
            },
      );
      await _cache.cacheFile(resolvedFile.copyWith(localPath: filePath));
      return filePath;
    } catch (e) {
      print('Erreur téléchargement: $e');
      rethrow;
    }
  }

  Future<String?> prepareFileForViewing(
    FileModel file, {
    ProgressCallback? onReceiveProgress,
  }) async {
    if (kIsWeb) return null;

    try {
      final resolvedFile =
          await _apiService.normalizeFileForCurrentPlatform(file);
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final viewerCacheDirectory =
          Directory('${documentsDirectory.path}/viewer_cache');

      if (!await viewerCacheDirectory.exists()) {
        await viewerCacheDirectory.create(recursive: true);
      }

      final filePath =
          '${viewerCacheDirectory.path}/${resolvedFile.id}_${resolvedFile.fileName}';
      final localFile = File(filePath);

      if (await localFile.exists() && await localFile.length() > 0) {
        return filePath;
      }

      final remoteUrl = await getFreshFileUrl(resolvedFile);
      await _dio.download(
        remoteUrl,
        filePath,
        onReceiveProgress: onReceiveProgress,
      );

      return filePath;
    } catch (e) {
      print('Erreur préparation lecture fluide: $e');
      return null;
    }
  }

  Future<bool> isFileDownloaded(FileModel file) async {
    if (kIsWeb) return false;
    try {
      final filePath = '${await _documentsPath()}/${file.fileName}';
      final localFile = File(filePath);
      return await localFile.exists();
    } catch (e) {
      print('Erreur vérification fichier: $e');
      return false;
    }
  }

  Future<void> openDownloadedFile(FileModel file) async {
    if (kIsWeb) return;
    try {
      final filePath = '${await _documentsPath()}/${file.fileName}';
      final localFile = File(filePath);
      if (await localFile.exists()) {
        final result = await OpenFilex.open(filePath);
        if (result.type != ResultType.done) {
          throw result.message;
        }
      } else {
        throw 'Fichier non trouvé localement';
      }
    } catch (e) {
      print('Erreur ouverture fichier: $e');
      rethrow;
    }
  }
}
