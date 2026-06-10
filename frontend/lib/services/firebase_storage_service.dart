import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import 'package:flutter/foundation.dart';
import 'storage_service_interface.dart';

class FirebaseStorageService implements StorageService {
  final firebase_storage.FirebaseStorage _storage =
      firebase_storage.FirebaseStorage.instance;
  final String bucketName;

  FirebaseStorageService({this.bucketName = 'university-files'});

  @override
  Future<String> uploadFile(File file, String path, String fileName) async {
    try {
      final fullPath = '$path/$fileName';
      final ref = _storage.ref().child(fullPath);
      await ref.putFile(file);
      return await ref.getDownloadURL();
    } catch (e) {
      print('Erreur upload Firebase Storage: $e');
      rethrow;
    }
  }

  @override
  Future<String> uploadBytes(
    Uint8List bytes,
    String path,
    String fileName,
  ) async {
    try {
      final fullPath = '$path/$fileName';
      final ref = _storage.ref().child(fullPath);
      await ref.putData(bytes);
      return await ref.getDownloadURL();
    } catch (e) {
      print('❌ Erreur upload bytes Firebase Storage: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteFile(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
    } catch (e) {
      print('❌ Erreur suppression Firebase Storage: $e');
      rethrow;
    }
  }

  @override
  String getPublicUrl(String path) {
    throw UnimplementedError('Use uploadFile and getDownloadURL instead');
  }
}
