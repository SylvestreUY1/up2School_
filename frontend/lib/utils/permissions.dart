/**
 * FICHIER : permissions.dart
 * RÔLE : C'est le carnet de règles de l'application.
 * Il définit qui a le droit de faire quoi. 
 * Par exemple : un étudiant ne peut pas supprimer un cours, seul l'admin le peut.
 */
import 'package:flutter/material.dart';
import '../models/event.dart';
import '../models/file.dart';
import '../models/user.dart';

class Permissions {
  /**
   * CRÉATION D'ÉVÉNEMENTS
   * Seuls les admins et les délégués (pour leur propre filière) peuvent créer des événements.
   */
  static bool canCreateEvent(UserRole role, String? field) {
    if (role == UserRole.delegate && (field == null || field.isEmpty))
      return false;
    return role == UserRole.delegate || role == UserRole.admin;
  }

  /**
   * TÉLÉCHARGEMENT DE FICHIERS
   * Un étudiant ne peut télécharger que les cours qui correspondent à SA faculté et SON niveau.
   */
  static bool canDownloadFile(UserModel? user, FileModel file) {
    if (user == null || user.role == UserRole.guest) return false;
    if (user.role == UserRole.admin) return true; // L'admin peut tout voir

    // L'étudiant doit être dans la bonne filière pour télécharger
    if (user.role == UserRole.delegate || user.role == UserRole.student) {
      return user.faculty == file.faculty &&
          user.level == file.level &&
          user.field == file.field;
    }
    return false;
  }

  static bool canDeleteFile(UserModel? user, FileModel file) {
    if (user == null) return false;
    if (user.role == UserRole.admin) return true;

    final isOwner = file.uploadedBy == user.id || file.uploadedBy == user.email;
    if (isOwner) return true;

    if (user.role != UserRole.delegate) return false;

    final isFromSameField = user.faculty == file.faculty &&
        user.level == file.level &&
        user.field == file.field;
    final isRecent = DateTime.now().difference(file.uploadedAt).inDays <= 15;

    return isFromSameField && isRecent;
  }

  static bool canDeleteEvent(UserModel? user, Event event) {
    if (user == null) return false;
    if (user.role == UserRole.admin) return true;

    final isOwner = event.createdBy == user.id || event.createdBy == user.email;
    if (isOwner) return true;

    if (user.role != UserRole.delegate || event.isGlobal) return false;

    final userFaculty = user.faculty?.trim().toLowerCase() ?? '';
    final userLevel = user.level?.trim().toLowerCase() ?? '';
    final userField = user.field?.trim().toLowerCase() ?? '';
    if (userFaculty.isEmpty || userLevel.isEmpty || userField.isEmpty) {
      return false;
    }

    return event.faculty.trim().toLowerCase() == userFaculty &&
        event.level.trim().toLowerCase() == userLevel &&
        event.field.trim().toLowerCase() == userField;
  }

  /**
   * ACCÈS AU PANNEAU D'ADMINISTRATION
   * Réservé uniquement aux administrateurs suprêmes.
   */
  static bool canAccessAdminPanel(UserRole role) {
    return role == UserRole.admin;
  }

  // Petit traducteur pour afficher le nom du rôle joliment
  static String getRoleLabel(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'Administrateur';
      case UserRole.delegate:
        return 'Délégué';
      case UserRole.student:
        return 'Étudiant';
      case UserRole.guest:
        return 'Invité';
    }
  }

  // Choisit une couleur pour chaque grade (Rouge pour admin, bleu pour étudiant...)
  static Color getRoleColor(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return Colors.red;
      case UserRole.delegate:
        return Colors.green;
      case UserRole.student:
        return Colors.blue;
      case UserRole.guest:
        return Colors.grey;
    }
  }
}
