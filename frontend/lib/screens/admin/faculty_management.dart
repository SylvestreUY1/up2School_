// faculty_management.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/faculty.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../utils/helpers.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/password_confirmation_dialog.dart'; // <-- ajout

class FacultyManagementScreen extends StatefulWidget {
  const FacultyManagementScreen({super.key});

  @override
  State<FacultyManagementScreen> createState() =>
      _FacultyManagementScreenState();
}

class _FacultyManagementScreenState extends State<FacultyManagementScreen> {
  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  List<Faculty> _faculties = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFaculties();
  }

  Future<void> _loadFaculties() async {
    setState(() => _isLoading = true);
    try {
      _faculties = await _apiService.getFaculties();
    } catch (e) {
      AppHelpers.showSnackBar(context, 'Erreur de chargement: $e',
          isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<bool> _reauthenticateAdmin(String password) async {
    try {
      await _authService.reauthenticate(password);
      return true;
    } catch (e) {
      AppHelpers.showSnackBar(
        context,
        'Mot de passe incorrect',
        isError: true,
      );
      return false;
    }
  }

  // Suppression d'une faculté
  Future<void> _deleteFaculty(Faculty faculty) async {
    final confirmed = await showPasswordConfirmationDialog(
      context: context,
      title: 'Supprimer la faculté',
      message: 'Confirmez votre mot de passe pour supprimer "${faculty.name}".',
      onConfirm: (password) async {
        return await _reauthenticateAdmin(password);
      },
    );

    if (confirmed != true) return;

    final doubleConfirm = await AppHelpers.showConfirmationDialog(
      context,
      'Confirmation finale',
      'Voulez-vous vraiment supprimer définitivement cette faculté ?',
    );

    if (!doubleConfirm) return;

    try {
      await _apiService.deleteFaculty(faculty.id);
      await _loadFaculties();
      AppHelpers.showSnackBar(context, 'Faculté supprimée');
    } catch (e) {
      AppHelpers.showSnackBar(context, 'Erreur: $e', isError: true);
    }
  }

  // Ajout d'un niveau
  Future<void> _addLevel(String facultyId) async {
    final levelController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF307A59),
        title: const Text(
          'Ajouter un niveau',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: levelController,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            labelText: 'Niveau (ex: L3)',
            labelStyle: const TextStyle(color: Colors.white),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white, width: 2),
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.1),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E9366),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final level = levelController.text.trim();
      if (level.isNotEmpty) {
        try {
          await _apiService.addLevel(facultyId, level);
          await _loadFaculties();
          AppHelpers.showSnackBar(context, 'Niveau ajouté');
        } catch (e) {
          AppHelpers.showSnackBar(context, 'Erreur: $e', isError: true);
        }
      }
    }
  }

  // Suppression d'un niveau
  Future<void> _removeLevel(String facultyId, String level) async {
    final confirmed = await showPasswordConfirmationDialog(
      context: context,
      title: 'Supprimer le niveau',
      message: 'Voulez-vous vraiment supprimer le niveau $level ?',
      onConfirm: (password) async {
        return await _reauthenticateAdmin(password);
      },
    );

    if (confirmed != true) return;

    try {
      await _apiService.removeLevel(facultyId, level);
      await _loadFaculties();
      AppHelpers.showSnackBar(context, 'Niveau supprimé');
    } catch (e) {
      AppHelpers.showSnackBar(context, 'Erreur: $e', isError: true);
    }
  }

  // Ajout d'une filière
  Future<void> _addField(String facultyId, String level) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF307A59),
        title: const Text(
          'Ajouter une filière',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            labelText: 'Nom de la filière',
            labelStyle: const TextStyle(color: Colors.white),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white, width: 2),
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.1),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E9366),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final field = controller.text.trim();
      if (field.isNotEmpty) {
        try {
          await _apiService.addField(facultyId, level, field);
          await _loadFaculties();
          AppHelpers.showSnackBar(context, 'Filière ajoutée');
        } catch (e) {
          AppHelpers.showSnackBar(context, 'Erreur: $e', isError: true);
        }
      }
    }
  }

  // Suppression d'une filière
  Future<void> _removeField(
      String facultyId, String level, String field) async {
    final confirmed = await showPasswordConfirmationDialog(
      context: context,
      title: 'Supprimer la filière',
      message: 'Voulez-vous vraiment supprimer la filière $field ?',
      onConfirm: (password) async {
        return await _reauthenticateAdmin(password);
      },
    );

    if (confirmed != true) return;

    try {
      await _apiService.removeField(facultyId, level, field);
      await _loadFaculties();
      AppHelpers.showSnackBar(context, 'Filière supprimée');
    } catch (e) {
      AppHelpers.showSnackBar(context, 'Erreur: $e', isError: true);
    }
  }

  // Ajout d'une unité
  Future<void> _addUnit(String facultyId, String level, String field) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF307A59),
        title: const Text(
          'Ajouter une unité',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
            labelText: 'Nom de l\'unité',
            labelStyle: const TextStyle(color: Colors.white),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.white, width: 2),
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.1),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E9366),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final unit = controller.text.trim();
      if (unit.isNotEmpty) {
        try {
          await _apiService.addUnit(facultyId, level, field, unit);
          await _loadFaculties();
          AppHelpers.showSnackBar(context, 'Unité ajoutée');
        } catch (e) {
          AppHelpers.showSnackBar(context, 'Erreur: $e', isError: true);
        }
      }
    }
  }

  // Suppression d'une unité
  Future<void> _removeUnit(
      String facultyId, String level, String field, String unit) async {
    final confirmed = await showPasswordConfirmationDialog(
      context: context,
      title: 'Supprimer l\'unité',
      message: 'Voulez-vous vraiment supprimer l\'unité $unit ?',
      onConfirm: (password) async {
        return await _reauthenticateAdmin(password);
      },
    );

    if (confirmed != true) return;

    try {
      await _apiService.removeUnit(facultyId, level, field, unit);
      await _loadFaculties();
      AppHelpers.showSnackBar(context, 'Unité supprimée');
    } catch (e) {
      AppHelpers.showSnackBar(context, 'Erreur: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestion des facultés'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF307A59)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _faculties.length,
              itemBuilder: (context, index) {
                final faculty = _faculties[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ExpansionTile(
                    leading: const Icon(Icons.school,
                        color: Color(0xFF2E9366), size: 30),
                    title: Text(
                      faculty.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    subtitle: Text('${faculty.levels.length} niveaux'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteFaculty(faculty),
                        ),
                        const Icon(Icons.expand_more),
                      ],
                    ),
                    children: [
                      const Divider(),
                      ...faculty.levels.map((level) {
                        return Column(
                          children: [
                            Container(
                              color: Colors.grey[100],
                              child: ListTile(
                                title: Row(
                                  children: [
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2E9366)
                                            .withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Center(
                                        child: Text(
                                          'L',
                                          style: TextStyle(
                                            color: Color(0xFF2E9366),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Niveau $level',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.add_circle,
                                          color: Color(0xFF2E9366)),
                                      onPressed: () =>
                                          _addField(faculty.id, level),
                                      tooltip: 'Ajouter une filière',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
                                      onPressed: () =>
                                          _removeLevel(faculty.id, level),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            ...(faculty.fields[level] ?? []).map((field) {
                              return Container(
                                margin: const EdgeInsets.only(left: 32),
                                child: Column(
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.category,
                                          size: 20, color: Colors.orange),
                                      title: Text(
                                        field,
                                        style: const TextStyle(fontSize: 15),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.add_circle,
                                                color: Color(0xFF2E9366),
                                                size: 20),
                                            onPressed: () => _addUnit(
                                                faculty.id, level, field),
                                            tooltip: 'Ajouter une unité',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete,
                                                color: Colors.red, size: 20),
                                            onPressed: () => _removeField(
                                                faculty.id, level, field),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ...(faculty.units[level]?[field] ?? [])
                                        .map((unit) {
                                      return Container(
                                        margin: const EdgeInsets.only(left: 32),
                                        child: ListTile(
                                          leading: const Icon(
                                              Icons.library_books,
                                              size: 18,
                                              color: Colors.blue),
                                          title: Text(
                                            unit,
                                            style:
                                                const TextStyle(fontSize: 14),
                                          ),
                                          trailing: IconButton(
                                            icon: const Icon(Icons.delete,
                                                color: Colors.red, size: 18),
                                            onPressed: () => _removeUnit(
                                                faculty.id, level, field, unit),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                ),
                              );
                            }).toList(),
                          ],
                        );
                      }).toList(),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: ElevatedButton.icon(
                          onPressed: () => _addLevel(faculty.id),
                          icon: const Icon(Icons.add),
                          label: const Text('Ajouter un niveau'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E9366),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
