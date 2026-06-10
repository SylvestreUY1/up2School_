import 'dart:io';
import 'package:flutter/foundation.dart' show Uint8List;

abstract class StorageService {
  /// Upload un fichier (depuis un File) et retourne l'URL publique.
  Future<String> uploadFile(File file, String path, String fileName);

  /// Upload un fichier depuis des bytes (Uint8List).
  Future<String> uploadBytes(Uint8List bytes, String path, String fileName);

  /// Supprime un fichier à partir de son URL.
  Future<void> deleteFile(String url);

  /// Récupère l'URL publique d'un fichier à partir de son chemin.
  String getPublicUrl(String path);
}