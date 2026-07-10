import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/default_faculties.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../models/faculty.dart';

class EditAcademicScreen extends StatefulWidget {
  const EditAcademicScreen({super.key});

  @override
  State<EditAcademicScreen> createState() => _EditAcademicScreenState();
}

class _EditAcademicScreenState extends State<EditAcademicScreen> {
  final ApiService _apiService = ApiService();
  List<Faculty> _faculties = sanitizeFaculties(getFallbackFaculties());
  String? _selectedFaculty;
  String? _selectedLevel;
  String? _selectedField;
  List<String> _levels = [];
  List<String> _fields = [];
  bool _isLoading = true; // true dès le début pour éviter un rendu avant _loadData()
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final remoteFaculties = mergeFaculties(
        sanitizeFaculties(await _apiService.getFaculties()),
        getFallbackFaculties(),
      );
      if (remoteFaculties.isNotEmpty) {
        _faculties = remoteFaculties;
      }

      // Récupérer l'utilisateur actuel
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final user = authProvider.currentUser;

      if (user != null) {
        // Normaliser les chaînes vides en null pour éviter le crash du DropdownButton
        _selectedFaculty =
            (user.faculty?.trim().isNotEmpty == true) ? user.faculty : null;
        _selectedLevel =
            (user.level?.trim().isNotEmpty == true) ? user.level : null;
        _selectedField =
            (user.field?.trim().isNotEmpty == true) ? user.field : null;

        // Charger les niveaux si faculté déjà définie
        if (_selectedFaculty != null) {
          final faculty = _faculties.firstWhere(
              (f) => f.name == _selectedFaculty,
              orElse: () => _faculties.first);
          _levels = faculty.levels;
        }

        // Charger les filières si niveau déjà défini
        if (_selectedLevel != null && _selectedFaculty != null) {
          final faculty = _faculties.firstWhere(
              (f) => f.name == _selectedFaculty,
              orElse: () => _faculties.first);
          _fields = faculty.fields[_selectedLevel!] ?? [];

          // Si la filière stockée n'est plus dans la liste, la réinitialiser
          if (_selectedField != null && !_fields.contains(_selectedField)) {
            _selectedField = null;
          }
        }
      }
    } catch (e) {
      print(
          'Erreur chargement données distantes, catalogue local conservé: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveChanges() async {
    if (_selectedFaculty == null ||
        _selectedLevel == null ||
        _selectedField == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner toutes les informations'),
          backgroundColor: Color(0xFFFF6C6C),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.updateAcademicInfo(
        faculty: _selectedFaculty!,
        level: _selectedLevel!,
        field: _selectedField!,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informations académiques mises à jour avec succès'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur'),
          backgroundColor: const Color(0xFFFF6C6C),
        ),
      );
    } finally {
      setState(() {
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Modifier mes informations académiques',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF307A59),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      backgroundColor: const Color(0xFF307A59),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: Colors.white, // Spinner en blanc
                strokeWidth: 3.0,
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Mettez à jour vos informations académiques lorsque vous changez de niveau ou de parcours.',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Faculté
                  const Text(
                    'Faculté',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'Sélectionnez votre faculté',
                      labelStyle: const TextStyle(color: Colors.white70),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: Colors.white), // Bordure blanche
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: Colors.white), // Bordure blanche
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: Colors.white,
                            width: 2), // Bordure blanche plus épaisse
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    dropdownColor: const Color(0xFF307A59),
                    icon:
                        const Icon(Icons.arrow_drop_down, color: Colors.white),
                    value: _selectedFaculty,
                    items: _faculties
                        .map((faculty) => DropdownMenuItem<String>(
                              value: faculty.name,
                              child: Text(
                                faculty.name,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedFaculty = value;
                        _selectedLevel = null;
                        _selectedField = null;
                        _fields = [];

                        if (value != null) {
                          final faculty =
                              _faculties.firstWhere((f) => f.name == value);
                          _levels = faculty.levels;
                        }
                      });
                    },
                    isExpanded: true,
                  ),

                  const SizedBox(height: 20),

                  // Niveau
                  if (_selectedFaculty != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Niveau',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: 'Sélectionnez votre niveau',
                            labelStyle: const TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Colors.white),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Colors.white),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: Colors.white, width: 2),
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.1),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                          style: const TextStyle(color: Colors.white),
                          dropdownColor: const Color(0xFF307A59),
                          icon: const Icon(Icons.arrow_drop_down,
                              color: Colors.white),
                          value: _selectedLevel,
                          items: _levels
                              .map((level) => DropdownMenuItem<String>(
                                    value: level,
                                    child: Text(
                                      'Niveau $level',
                                      style:
                                          const TextStyle(color: Colors.white),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedLevel = value;
                              _selectedField = null;

                              if (value != null) {
                                final faculty = _faculties.firstWhere(
                                    (f) => f.name == _selectedFaculty);
                                _fields = faculty.fields[value] ?? [];
                              }
                            });
                          },
                          isExpanded: true,
                        ),
                      ],
                    ),

                  const SizedBox(height: 20),

                  // Filière
                  if (_selectedLevel != null && _fields.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Filière / Spécialité',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(
                            labelText: 'Sélectionnez votre filière',
                            labelStyle: const TextStyle(color: Colors.white70),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Colors.white),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Colors.white),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: Colors.white, width: 2),
                            ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.1),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 16,
                            ),
                          ),
                          style: const TextStyle(color: Colors.white),
                          dropdownColor: const Color(0xFF307A59),
                          icon: const Icon(Icons.arrow_drop_down,
                              color: Colors.white),
                          value: _selectedField,
                          items: _fields
                              .map((field) => DropdownMenuItem<String>(
                                    value: field,
                                    child: Text(
                                      field,
                                      style:
                                          const TextStyle(color: Colors.white),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              _selectedField = value;
                            });
                          },
                          isExpanded: true,
                        ),
                      ],
                    ),

                  // Message si pas de filières disponibles
                  if (_selectedLevel != null && _fields.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(
                        'Aucune filière disponible pour ce niveau',
                        style: TextStyle(
                          color: Colors.red[200],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),

                  const SizedBox(height: 40),

                  // Boutons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: const BorderSide(color: Colors.white),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Annuler',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saving ? null : _saveChanges,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF307A59),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _saving
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: const Color(
                                        0xFF307A59), // Spinner vert pour le bouton
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Enregistrer',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
