import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/faculty.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../screens/files/files_list_screen.dart';
import '../../widgets/custom_loading.dart';
import '../../models/default_faculties.dart';
import '../../utils/document_types.dart';

class AdminFileExplorer extends StatefulWidget {
  const AdminFileExplorer({super.key});

  @override
  State<AdminFileExplorer> createState() => _AdminFileExplorerState();
}

class _AdminFileExplorerState extends State<AdminFileExplorer> {
  final ApiService _apiService = ApiService();
  List<Faculty> _faculties = [];
  bool _isLoading = true;

  // Variables pour la navigation en arborescence
  String? _selectedFac;
  String? _selectedLvl;
  String? _selectedFld;
  String? _selectedUnit;
  List<String> _pathHistory = [];

  // Listes pour les sélections
  List<String> _levels = [];
  List<String> _fields = [];
  List<String> _units = [];

  @override
  void initState() {
    super.initState();
    _loadFaculties();
  }

  Future<void> _loadFaculties() async {
    try {
      final apiService = ApiService();
      _faculties = mergeFaculties(
        await apiService.getFaculties(),
        getFallbackFaculties(),
      );

      if (_faculties.isEmpty) {
        print('⚠️ Aucune faculté chargée - Utilisation du fallback');
        _faculties = getFallbackFaculties();
      }
    } catch (e) {
      _faculties = getFallbackFaculties();
      print('❌ Erreur chargement facultés: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _selectFaculty(String facultyName) {
    setState(() {
      _selectedFac = facultyName;
      _selectedLvl = null;
      _selectedFld = null;
      _selectedUnit = null;
      _levels = [];
      _fields = [];
      _units = [];
      _pathHistory = [facultyName];

      final faculty = _faculties.firstWhere(
        (f) => f.name == facultyName,
        orElse: () => _faculties.first,
      );
      _levels = faculty.levels;
    });
  }

  void _selectLevel(String level) {
    setState(() {
      _selectedLvl = level;
      _selectedFld = null;
      _selectedUnit = null;
      _fields = [];
      _units = [];

      if (_selectedFac != null) {
        final faculty = _faculties.firstWhere(
          (f) => f.name == _selectedFac,
          orElse: () => _faculties.first,
        );
        _fields = faculty.fields[level] ?? [];
        _pathHistory = [_selectedFac!, level];
      }
    });
  }

  void _selectField(String field) {
    setState(() {
      _selectedFld = field;
      _selectedUnit = null;
      _units = [];

      if (_selectedFac != null && _selectedLvl != null) {
        final faculty = _faculties.firstWhere(
          (f) => f.name == _selectedFac,
          orElse: () => _faculties.first,
        );

        final levelUnits = faculty.units[_selectedLvl!];
        if (levelUnits != null) {
          _units = levelUnits[field] ?? [];
        }

        _pathHistory = [_selectedFac!, _selectedLvl!, field];
      }
    });
  }

  void _selectUnit(String unit) {
    setState(() {
      _selectedUnit = unit;
      if (_selectedFac != null &&
          _selectedLvl != null &&
          _selectedFld != null) {
        _pathHistory = [_selectedFac!, _selectedLvl!, _selectedFld!, unit];
      }
    });
  }

  void _navigateToPath(int index) {
    if (index == 0) {
      setState(() {
        _selectedFac = null;
        _selectedLvl = null;
        _selectedFld = null;
        _selectedUnit = null;
        _pathHistory = [];
      });
    } else if (index == 1 && _pathHistory.length > 1) {
      setState(() {
        _selectedLvl = null;
        _selectedFld = null;
        _selectedUnit = null;
        _pathHistory = [_pathHistory[0]];
      });
    } else if (index == 2 && _pathHistory.length > 2) {
      setState(() {
        _selectedFld = null;
        _selectedUnit = null;
        _pathHistory = [_pathHistory[0], _pathHistory[1]];
      });
    } else if (index == 3 && _pathHistory.length > 3) {
      setState(() {
        _selectedUnit = null;
        _pathHistory = [_pathHistory[0], _pathHistory[1], _pathHistory[2]];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (authProvider.currentUser?.role != UserRole.admin) {
      return Scaffold(
        appBar: AppBar(title: Text('Accès refusé')),
        body: Center(
          child: Text('Administrateur requis'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Explorateur de fichiers - Admin'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? CustomLoading()
          : Column(
              children: [
                // Barre de navigation (chemin parcouru)
                if (_pathHistory.isNotEmpty)
                  Container(
                    height: 50,
                    color: Colors.grey[100],
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          // Bouton retour
                          if (_selectedFac != null)
                            GestureDetector(
                              onTap: () {
                                if (_selectedUnit != null) {
                                  setState(() {
                                    _selectedUnit = null;
                                    _pathHistory.removeLast();
                                  });
                                } else if (_selectedFld != null) {
                                  setState(() {
                                    _selectedFld = null;
                                    _selectedUnit = null;
                                    _pathHistory = [
                                      _pathHistory[0],
                                      _pathHistory[1]
                                    ];
                                  });
                                } else if (_selectedLvl != null) {
                                  setState(() {
                                    _selectedLvl = null;
                                    _selectedFld = null;
                                    _selectedUnit = null;
                                    _pathHistory = [_pathHistory[0]];
                                  });
                                } else if (_selectedFac != null) {
                                  setState(() {
                                    _selectedFac = null;
                                    _selectedLvl = null;
                                    _selectedFld = null;
                                    _selectedUnit = null;
                                    _pathHistory = [];
                                  });
                                }
                              },
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.1),
                                      blurRadius: 2,
                                      offset: Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  Icons.arrow_back,
                                  size: 18,
                                  color: Color(0xFF307A59),
                                ),
                              ),
                            ),

                          if (_selectedFac != null) SizedBox(width: 12),

                          // Chemin
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  ..._pathHistory.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final item = entry.value;
                                    final isLast =
                                        index == _pathHistory.length - 1;

                                    return Row(
                                      children: [
                                        if (index > 0) ...[
                                          SizedBox(width: 8),
                                          Icon(Icons.chevron_right,
                                              size: 16, color: Colors.grey),
                                          SizedBox(width: 8),
                                        ],
                                        GestureDetector(
                                          onTap: () =>
                                              _navigateToPath(index + 1),
                                          child: Container(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: isLast
                                                  ? Color(0xFF307A59)
                                                      .withOpacity(0.1)
                                                  : Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: isLast
                                                  ? Border.all(
                                                      color: Color(0xFF307A59)
                                                          .withOpacity(0.3))
                                                  : null,
                                            ),
                                            child: Text(
                                              item,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: isLast
                                                    ? Color(0xFF307A59)
                                                    : Colors.grey[700],
                                                fontWeight: isLast
                                                    ? FontWeight.w600
                                                    : FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Corps de l'explorateur
                Expanded(
                  child: _selectedFac == null
                      ? _buildFacultiesList()
                      : _selectedLvl == null
                          ? _buildLevelsList()
                          : _selectedFld == null
                              ? _buildFieldsList()
                              : _selectedUnit == null
                                  ? _buildUnitsList()
                                  : _buildDocumentTypesList(),
                ),
              ],
            ),
    );
  }

  Widget _buildFacultiesList() {
    return ListView(
      padding: EdgeInsets.all(20),
      children: _faculties.map((faculty) {
        return Card(
          elevation: 2,
          child: ListTile(
            onTap: () => _selectFaculty(faculty.name),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Color(0xFF307A59).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.school, color: Color(0xFF307A59)),
            ),
            title: Text(
              faculty.name,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text('${faculty.levels.length} niveaux'),
            trailing: Icon(Icons.chevron_right, color: Color(0xFF307A59)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildLevelsList() {
    return ListView(
      padding: EdgeInsets.all(20),
      children: _levels.map((level) {
        return Card(
          elevation: 2,
          child: ListTile(
            onTap: () => _selectLevel(level),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Color(0xFF307A59).withOpacity(0.1),
                borderRadius: BorderRadius.circular(25),
              ),
              child: Center(
                child: Text(
                  level,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF307A59),
                  ),
                ),
              ),
            ),
            title: Text(
              'Niveau $level',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing: Icon(Icons.chevron_right, color: Color(0xFF307A59)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFieldsList() {
    return ListView(
      padding: EdgeInsets.all(20),
      children: _fields.map((field) {
        return Card(
          elevation: 2,
          child: ListTile(
            onTap: () => _selectField(field),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Color(0xFF307A59).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.category, color: Color(0xFF307A59)),
            ),
            title: Text(
              field,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text('Filière'),
            trailing: Icon(Icons.chevron_right, color: Color(0xFF307A59)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildUnitsList() {
    return ListView(
      padding: EdgeInsets.all(20),
      children: _units.map((unit) {
        return Card(
          elevation: 2,
          child: ListTile(
            onTap: () => _selectUnit(unit),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Color(0xFF307A59).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.library_books, color: Color(0xFF307A59)),
            ),
            title: Text(
              unit,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text('Unité d\'enseignement'),
            trailing: Icon(Icons.chevron_right, color: Color(0xFF307A59)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDocumentTypesList() {
    return ListView(
      padding: EdgeInsets.all(20),
      children: [
        _buildDocumentTypeCard('Cours'),
        SizedBox(height: 4),
        _buildDocumentTypeCard('TD'),
        SizedBox(height: 4),
        _buildDocumentTypeCard('Sujets d\'examen'),
        SizedBox(height: 4),
        _buildDocumentTypeCard('Projets'),
        SizedBox(height: 4),
        _buildDocumentTypeCard('Autres ressources'),
      ],
    );
  }

  Widget _buildDocumentTypeCard(String type) {
    IconData icon;
    switch (type) {
      case 'Cours':
        icon = Icons.menu_book;
      case 'TD':
        icon = Icons.assignment;
      case 'Sujets d\'examen':
        icon = Icons.quiz;
      case 'Projets':
        icon = Icons.work;
      case 'Autres ressources':
        icon = Icons.folder_special;
      default:
        icon = Icons.description;
    }

    return Card(
      elevation: 2,
      child: ListTile(
        onTap: () {
          // Navigation vers l'écran des fichiers avec tous les paramètres
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FilesListScreen(
                faculty: _selectedFac!,
                level: _selectedLvl!,
                field: _selectedFld!,
                unit: _selectedUnit!,
                type: normalizeDocumentType(type),
              ),
            ),
          );
        },
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Color(0xFF307A59).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Color(0xFF307A59)),
        ),
        title: Text(
          type,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text('Documents de $type'),
        trailing: Icon(Icons.chevron_right, color: Color(0xFF307A59)),
      ),
    );
  }
}
