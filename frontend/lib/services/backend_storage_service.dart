import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'backend_api_service.dart';
import 'storage_service_interface.dart';

class BackendStorageService implements StorageService {
  BackendStorageService({BackendApiService? api}) : _api = api ?? BackendApiService();

  final BackendApiService _api;

  @override
  Future<String> uploadFile(File file, String path, String fileName) async {
    final formData = FormData.fromMap({
      'path': path,
      'file': await MultipartFile.fromFile(file.path, filename: fileName),
    });

    final response = await _api.dio.post<Map<String, dynamic>>(
      '/api/storage/upload',
      data: formData,
    );
    return response.data?['downloadUrl'] as String? ?? '';
  }

  @override
  Future<String> uploadBytes(
    Uint8List bytes,
    String path,
    String fileName,
  ) async {
    final formData = FormData.fromMap({
      'path': path,
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
    });

    final response = await _api.dio.post<Map<String, dynamic>>(
      '/api/storage/upload',
      data: formData,
    );
    return response.data?['downloadUrl'] as String? ?? '';
  }

  @override
  Future<void> deleteFile(String url) async {
    await _api.dio.delete(
      '/api/storage/object',
      data: {'url': url},
    );
  }

  @override
  String getPublicUrl(String path) => path;
}
