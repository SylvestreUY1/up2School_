import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart' as firebase_storage;
import '../models/file.dart';

class StorageService {
  static const bool USE_MOCK_MODE =
      true; // Mettre à false pour utiliser Firebase

  // Références Firebase (uniquement si non mock)
  final FirebaseFirestore? _firestore =
      USE_MOCK_MODE ? null : FirebaseFirestore.instance;
  final firebase_storage.FirebaseStorage? _storage =
      USE_MOCK_MODE ? null : firebase_storage.FirebaseStorage.instance;

  // Récupère les fichiers avec filtres optionnels
  Future<List<FileModel>> getFiles({
    String? faculty,
    String? level,
    String? field,
    String? unit,
    String? type,
  }) async {
    // Mode Firebase
    try {
      print('🔥 [Firestore] Récupération des fichiers avec filtres');
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

      final snapshot = await query.get();
      print('🔥 Fichiers trouvés: ${snapshot.docs.length}');

      return snapshot.docs
          .map((doc) => FileModel.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('❌ Erreur récupération fichiers Firestore: $e');
      return [];
    }
  }

  // Upload d'un fichier vers le stockage
  Future<String> uploadFile(File file, String fileName, String userId) async {
    // Mode Firebase
    try {
      print('🔥 [Firebase Storage] Upload de $fileName');
      final storageRef =
          _storage!.ref().child('files').child(userId).child(fileName);

      final uploadTask = await storageRef.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      print('✅ Fichier uploadé: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      print('❌ Erreur upload Firebase Storage: $e');
      rethrow;
    }
  }

  // Ajoute un fichier (métadonnées)
  Future<void> addFile(FileModel file) async {
    // Mode Firebase
    try {
      print('🔥 [Firestore] Ajout fichier: ${file.id}');
      await _firestore!.collection('files').doc(file.id).set(file.toMap());
    } catch (e) {
      print('❌ Erreur ajout fichier Firestore: $e');
      rethrow;
    }
  }

  // Supprime un fichier du stockage et des métadonnées
  Future<void> deleteFile(String fileId, String fileUrl) async {
    // Mode Firebase
    try {
      // Supprimer les métadonnées Firestore
      await _firestore!.collection('files').doc(fileId).delete();
      print('🔥 Métadonnées supprimées de Firestore');

      // Supprimer le fichier du Storage
      final storageRef = _storage!.refFromURL(fileUrl);
      await storageRef.delete();
      print('🔥 Fichier supprimé du Storage');
    } catch (e) {
      print('❌ Erreur suppression fichier: $e');
      rethrow;
    }
  }

  // Ajoute ou retire un favori
  Future<void> toggleFavorite(String fileId, String userId) async {
    // Mode Firebase
    try {
      final docRef = _firestore!.collection('files').doc(fileId);
      await _firestore!.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);
        if (!snapshot.exists) return;

        final data = snapshot.data() as Map<String, dynamic>;
        List<String> favorites = List<String>.from(data['favorites'] ?? []);

        if (favorites.contains(userId)) {
          favorites.remove(userId);
        } else {
          favorites.add(userId);
        }

        transaction.update(docRef, {'favorites': favorites});
      });
      print('🔥 Favori mis à jour');
    } catch (e) {
      print('❌ Erreur toggle favori: $e');
      rethrow;
    }
  }
}
