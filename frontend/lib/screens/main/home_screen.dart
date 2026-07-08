/**
 * FICHIER : home_screen.dart
 * RÔLE : C'est l'écran d'accueil, le menu principal de l'application.
 * Il permet de naviguer dans les facultés (FS, FSJP, FSEG, etc.),
 * de choisir son niveau et de trouver ses cours.
 */
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/faculty.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/constants.dart';
import '../auth/login_screen.dart';
import 'files_screen.dart';
import 'events_screen.dart';
import 'profile_screen.dart';
import '../../widgets/custom_loading.dart';
import 'package:up2school/screens/files/files_list_screen.dart';
import '../../screens/admin/admin_panel.dart';
import '../../models/default_faculties.dart';
import '../../screens/main/admin_ads_screen.dart';
import '../../widgets/rotating_ad_banner.dart';
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/document_types.dart';

// Classe SelectionDialog (inchangée)
class SelectionDialog extends StatefulWidget {
  final List<Faculty> faculties;
  final Function(SelectionData) onSelectionComplete;

  const SelectionDialog({
    super.key,
    required this.faculties,
    required this.onSelectionComplete,
  });

  @override
  State<SelectionDialog> createState() => _SelectionDialogState();
}

class _SelectionDialogState extends State<SelectionDialog> {
  String? _selectedFaculty;
  String? _selectedLevel;
  String? _selectedField;
  String? _selectedUnit;
  String _selectedType = 'cours';

  List<String> _levels = [];
  List<String> _fields = [];
  List<String> _units = [];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AlertDialog(
      title: Text(l10n.selectYourTrack),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              decoration: InputDecoration(labelText: l10n.faculty),
              value: _selectedFaculty,
              items: widget.faculties
                  .map(
                    (faculty) => DropdownMenuItem(
                      value: faculty.name,
                      child: Text(faculty.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _selectedFaculty = value;
                  _selectedLevel = null;
                  _selectedField = null;
                  _selectedUnit = null;
                  if (value != null) {
                    final faculty = widget.faculties.firstWhere(
                      (f) => f.name == value,
                    );
                    _levels = faculty.levels;
                  }
                });
              },
            ),
            if (_selectedFaculty != null)
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: l10n.level),
                value: _selectedLevel,
                items: _levels
                    .map(
                      (level) =>
                          DropdownMenuItem(value: level, child: Text(level)),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedLevel = value;
                    _selectedField = null;
                    _selectedUnit = null;
                    if (value != null) {
                      final faculty = widget.faculties.firstWhere(
                        (f) => f.name == _selectedFaculty,
                      );
                      _fields = faculty.fields[value] ?? [];
                    }
                  });
                },
              ),
            if (_selectedLevel != null)
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: l10n.field),
                value: _selectedField,
                items: _fields
                    .map(
                      (field) =>
                          DropdownMenuItem(value: field, child: Text(field)),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedField = value;
                    _selectedUnit = null;
                    if (value != null) {
                      final faculty = widget.faculties.firstWhere(
                        (f) => f.name == _selectedFaculty,
                      );
                      final levelUnits = faculty.units[_selectedLevel!];
                      if (levelUnits != null) {
                        _units = levelUnits[value] ?? [];
                      }
                    }
                  });
                },
              ),
            if (_selectedField != null)
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: l10n.teachingUnit,
                ),
                value: _selectedUnit,
                items: _units
                    .map(
                      (unit) =>
                          DropdownMenuItem(value: unit, child: Text(unit)),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedUnit = value;
                  });
                },
              ),
            if (_selectedUnit != null)
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: l10n.documentType,
                ),
                value: _selectedType,
                items: [
                  DropdownMenuItem(
                    value: 'cours',
                    child: Text(l10n.documentTypeLabel('cours')),
                  ),
                  DropdownMenuItem(
                    value: 'td',
                    child: Text(l10n.documentTypeLabel('td')),
                  ),
                  DropdownMenuItem(
                    value: 'sujets',
                    child: Text(l10n.documentTypeLabel('sujets')),
                  ),
                  DropdownMenuItem(
                    value: 'projets',
                    child: Text(l10n.documentTypeLabel('projets')),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedType = value!;
                  });
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _selectedFaculty != null &&
                  _selectedLevel != null &&
                  _selectedField != null &&
                  _selectedUnit != null
              ? () {
                  widget.onSelectionComplete(
                    SelectionData(
                      faculty: _selectedFaculty!,
                      level: _selectedLevel!,
                      field: _selectedField!,
                      unit: _selectedUnit!,
                      type: _selectedType,
                    ),
                  );
                }
              : null,
          child: Text(l10n.validate),
        ),
      ],
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  SelectionData? _selectionData;
  List<Faculty> _faculties = sanitizeFaculties(getFallbackFaculties());
  final bool _isLoading = false;
  String? _lastAcademicWorkspaceKey;

  // Variables pour la navigation en arborescence
  String? _selectedFac;
  String? _selectedLvl;
  String? _selectedFld;
  String? _selectedUnit;

  /**
   * LE FIL D'ARIANE (Navigation en miettes de pain)
   * On stocke le chemin de navigation actuel : Faculté > Niveau > Filière > Unité
   */
  List<String> _pathHistory = [];

  // Listes pour les sélections
  List<String> _levels = [];
  List<String> _fields = [];
  List<String> _units = [];

  final List<Widget> _screens = [
    const FilesScreen(),
    const EventsScreen(),
    const ProfileScreen(),
  ];

  bool _isWideDesktopLayout(BuildContext context) {
    return MediaQuery.of(context).size.width >= 1024;
  }

  bool _useDesktopShell(BuildContext context) {
    return MediaQuery.of(context).size.width >= 800;
  }

  List<String> _documentTypeCodes() => const [
        'cours',
        'td',
        'sujets',
        'projets',
        'autres',
      ];

  String _documentTypeLabel(BuildContext context, String code) =>
      context.l10n.documentTypeLabel(code);

  Widget _buildResponsiveExplorerList({
    required int itemCount,
    required Widget Function(BuildContext context, int index) itemBuilder,
  }) {
    final useGrid = _isWideDesktopLayout(context);

    if (!useGrid) {
      return ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: itemCount,
        itemBuilder: itemBuilder,
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 360,
        mainAxisExtent: 128,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshFacultiesFromApi();
  }

  // Détecte le retour au premier plan
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateLastActivity();
    }
  }

  // Méthode pour mettre à jour lastActivity via AuthProvider
  Future<void> _updateLastActivity() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.updateLastActivity();
  }

  void _onEventsPressed() {
    _updateLastActivity();
    setState(() {
      _selectedIndex = 1;
    });
  }

  void _openHomeWorkspace() {
    _updateLastActivity();
    if (_selectedIndex == 1) {
      _onReturnToEventList();
    }

    setState(() {
      _selectedIndex = 0;
      _openDefaultHomeWorkspaceForUser(
        Provider.of<AuthProvider>(context, listen: false).currentUser,
      );
    });
    _onReturnToFacultiesList();
  }

  void _openProfile(AuthProvider authProvider) {
    _updateLastActivity();
    if (authProvider.currentUser != null) {
      setState(() {
        _selectedIndex = 2;
      });
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
  }

  void _applyFaculties(List<Faculty> faculties) {
    _faculties = faculties;

    if (_selectedFac == null) {
      return;
    }

    Faculty? selectedFaculty;
    for (final faculty in _faculties) {
      if (faculty.name == _selectedFac) {
        selectedFaculty = faculty;
        break;
      }
    }

    if (selectedFaculty == null) {
      _selectedFac = null;
      _selectedLvl = null;
      _selectedFld = null;
      _selectedUnit = null;
      _levels = [];
      _fields = [];
      _units = [];
      _pathHistory = [];
      return;
    }

    _levels = selectedFaculty.levels;

    if (_selectedLvl == null || !_levels.contains(_selectedLvl)) {
      _selectedLvl = null;
      _selectedFld = null;
      _selectedUnit = null;
      _fields = [];
      _units = [];
      _pathHistory = [_selectedFac!];
      return;
    }

    _fields = selectedFaculty.fields[_selectedLvl!] ?? [];

    if (_selectedFld == null || !_fields.contains(_selectedFld)) {
      _selectedFld = null;
      _selectedUnit = null;
      _units = [];
      _pathHistory = [_selectedFac!, _selectedLvl!];
      return;
    }

    final levelUnits = selectedFaculty.units[_selectedLvl!];
    _units = levelUnits?[_selectedFld!] ?? [];

    if (_selectedUnit == null || !_units.contains(_selectedUnit)) {
      _selectedUnit = null;
      _pathHistory = [_selectedFac!, _selectedLvl!, _selectedFld!];
      return;
    }

    _pathHistory = [
      _selectedFac!,
      _selectedLvl!,
      _selectedFld!,
      _selectedUnit!
    ];
  }

  /**
   * ESPACE DE TRAVAIL ACADÉMIQUE
   * Définit une clé unique pour l'espace académique par défaut de l'étudiant
   */
  String? _academicWorkspaceKey(UserModel? user) {
    if (!_shouldDefaultToAcademicUnits(user)) {
      return null;
    }
    return '${user!.id}|${user.faculty}|${user.level}|${user.field}';
  }

  bool _shouldDefaultToAcademicUnits(UserModel? user) {
    if (user == null) return false;
    if (user.role != UserRole.student && user.role != UserRole.delegate) {
      return false;
    }
    return (user.faculty?.trim().isNotEmpty ?? false) &&
        (user.level?.trim().isNotEmpty ?? false) &&
        (user.field?.trim().isNotEmpty ?? false);
  }

  Faculty? _findFacultyByName(String? facultyName) {
    if (facultyName == null || facultyName.isEmpty) return null;
    for (final faculty in _faculties) {
      if (faculty.name == facultyName) {
        return faculty;
      }
    }
    return null;
  }

  void _openDefaultHomeWorkspaceForUser(UserModel? user) {
    if (!_shouldDefaultToAcademicUnits(user)) {
      _selectedFac = null;
      _selectedLvl = null;
      _selectedFld = null;
      _selectedUnit = null;
      _levels = [];
      _fields = [];
      _units = [];
      _pathHistory = [];
      return;
    }

    final faculty = _findFacultyByName(user!.faculty);
    final level = user.level!;
    final field = user.field!;

    if (faculty == null) {
      _selectedFac = null;
      _selectedLvl = null;
      _selectedFld = null;
      _selectedUnit = null;
      _levels = [];
      _fields = [];
      _units = [];
      _pathHistory = [];
      return;
    }

    final List<String> levels = faculty.levels;
    final List<String> fields = levels.contains(level)
        ? (faculty.fields[level] ?? <String>[])
        : <String>[];
    final List<String> units = fields.contains(field)
        ? (faculty.units[level]?[field] ?? <String>[])
        : <String>[];

    _selectedFac = faculty.name;
    _selectedLvl = levels.contains(level) ? level : null;
    _selectedFld =
        _selectedLvl != null && fields.contains(field) ? field : null;
    _selectedUnit = null;
    _levels = levels;
    _fields = _selectedLvl != null ? fields : <String>[];
    _units = _selectedFld != null ? units : <String>[];

    if (_selectedFld != null) {
      _pathHistory = [faculty.name, _selectedLvl!, _selectedFld!];
    } else if (_selectedLvl != null) {
      _pathHistory = [faculty.name, _selectedLvl!];
    } else {
      _pathHistory = [faculty.name];
    }
  }

  void _syncAcademicWorkspace(UserModel? user) {
    final newKey = _academicWorkspaceKey(user);
    if (_lastAcademicWorkspaceKey == newKey) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _lastAcademicWorkspaceKey = newKey;
        if (_selectedIndex == 0 || newKey == null) {
          _openDefaultHomeWorkspaceForUser(user);
        }
      });
    });
  }

  Future<void> _refreshFacultiesFromApi() async {
    try {
      final apiService = ApiService();
      final remoteFaculties = mergeFaculties(
        sanitizeFaculties(await apiService.getFaculties()),
        getFallbackFaculties(),
      );

      if (remoteFaculties.isEmpty) {
        print(
            '⚠️ Aucune faculté distante chargée - utilisation du catalogue local');
        return;
      }

      if (!mounted) return;
      setState(() {
        _applyFaculties(remoteFaculties);
      });
    } catch (e) {
      print(
          '❌ Erreur chargement facultés distantes, catalogue local conservé: $e');
    }
  }

  void _onReturnToFacultiesList() {
    // Aucune publicité
  }

  void _onReturnToEventList() {
    // Aucune publicité
  }

  void _showSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => SelectionDialog(
        faculties: _faculties,
        onSelectionComplete: (selection) {
          setState(() {
            _selectionData = selection;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  // Navigation avec mise à jour de l'activité
  void _selectFaculty(String facultyName) {
    _updateLastActivity();
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
    _updateLastActivity();
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
    _updateLastActivity();
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
    _updateLastActivity();
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
    _updateLastActivity();

    setState(() {
      if (index == 0) {
        // Retour à la liste de toutes les facultés
        _selectedFac = null;
        _selectedLvl = null;
        _selectedFld = null;
        _selectedUnit = null;
        _pathHistory = [];
        _onReturnToFacultiesList();
      } else if (index == 1) {
        // On clique sur la Faculté : on réinitialise tout le reste
        _selectedLvl = null;
        _selectedFld = null;
        _selectedUnit = null;
        _pathHistory = [_pathHistory[0]];
      } else if (index == 2 && _pathHistory.length >= 2) {
        // On clique sur le Niveau : on réinitialise Filière et Unité
        _selectedFld = null;
        _selectedUnit = null;
        _pathHistory = [_pathHistory[0], _pathHistory[1]];
      } else if (index == 3 && _pathHistory.length >= 3) {
        // On clique sur la Filière : on réinitialise l'Unité
        _selectedUnit = null;
        _pathHistory = [_pathHistory[0], _pathHistory[1], _pathHistory[2]];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final isAdmin = authProvider.currentUser?.role == UserRole.admin;
        _syncAcademicWorkspace(authProvider.currentUser);
        if (authProvider.currentUser == null && _selectedIndex == 2) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _selectedIndex = 0;
                _openDefaultHomeWorkspaceForUser(null);
              });
            }
          });
        }
        return WillPopScope(
          onWillPop: _onWillPop,
          child: _useDesktopShell(context)
              ? _buildDesktopScaffold(authProvider, isAdmin)
              : _buildMobileScaffold(authProvider, isAdmin),
        );
      },
    );
  }

  Widget _buildMobileScaffold(AuthProvider authProvider, bool isAdmin) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    return Scaffold(
      key: ValueKey(authProvider.currentUser?.id ?? 'guest'),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _isWideDesktopLayout(context) ? 1320 : double.infinity,
          ),
          child: Column(
            children: [
              Container(
                height: statusBarHeight,
                width: double.infinity,
                color: AppConstants.lightPrimaryColor,
              ),
              Container(
                height: 60,
                width: double.infinity,
                color: AppConstants.primaryColor,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildIconButton(
                      icon: Icons.home,
                      onPressed: _openHomeWorkspace,
                      isActive: _selectedIndex == 0,
                      margin: const EdgeInsets.only(left: 16),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          isAdmin ? '' : 'UY1-lib',
                          style: const TextStyle(
                            fontFamily: 'Aclonica',
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        if (isAdmin)
                          _buildIconButton(
                            icon: Icons.campaign,
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const AdminAdsScreen(),
                                ),
                              );
                            },
                            isActive: false,
                          ),
                        _buildIconButton(
                          icon: Icons.event,
                          onPressed: _onEventsPressed,
                          isActive: _selectedIndex == 1,
                        ),
                        if (isAdmin)
                          _buildIconButton(
                            icon: Icons.admin_panel_settings,
                            onPressed: () => _navigateToAdminPanel(context),
                            isActive: false,
                          ),
                        _buildIconButton(
                          icon: Icons.person,
                          onPressed: () => _openProfile(authProvider),
                          isActive: _selectedIndex == 2,
                        ),
                        const SizedBox(width: 16),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              if (_selectedIndex == 0 && _pathHistory.isNotEmpty)
                _buildPathHistoryBar(isDesktop: false),
              Expanded(child: _buildMainWorkspace()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopScaffold(AuthProvider authProvider, bool isAdmin) {
    return Scaffold(
      key: ValueKey('desktop-${authProvider.currentUser?.id ?? 'guest'}'),
      backgroundColor: const Color.fromARGB(255, 34, 87, 63),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1480),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildDesktopSidebar(authProvider, isAdmin),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      children: [
                        _buildDesktopHeader(authProvider),
                        const SizedBox(height: 20),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF2F7958),
                                  Color(0xFF28674B),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.12),
                                  blurRadius: 28,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                if (_selectedIndex == 0 &&
                                    _pathHistory.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      20,
                                      20,
                                      20,
                                      0,
                                    ),
                                    child: _buildPathHistoryBar(
                                      isDesktop: true,
                                    ),
                                  ),
                                Expanded(child: _buildMainWorkspace()),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopSidebar(AuthProvider authProvider, bool isAdmin) {
    final user = authProvider.currentUser;
    final l10n = context.l10n;

    return Container(
      width: 300,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF1F5A42),
            Color.fromARGB(255, 19, 157, 95),
          ],
        ),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.dashboard_customize_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'UY1-lib',
                          style: TextStyle(
                            fontFamily: 'Aclonica',
                            fontSize: 24,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.appOverview,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: Colors.white.withOpacity(0.72),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 26),
                  _buildDesktopNavItem(
                    icon: Icons.dashboard_outlined,
                    activeIcon: Icons.dashboard_rounded,
                    title: l10n.resources,
                    subtitle: _pathHistory.isEmpty
                        ? l10n.browseLibrary
                        : l10n.pathProgress(_pathHistory.length, 4),
                    isActive: _selectedIndex == 0,
                    badge: _pathHistory.isEmpty
                        ? null
                        : '${_pathHistory.length}/4',
                    onTap: _openHomeWorkspace,
                  ),
                  const SizedBox(height: 12),
                  _buildDesktopNavItem(
                    icon: Icons.event_note_outlined,
                    activeIcon: Icons.event_note_rounded,
                    title: l10n.events,
                    subtitle: l10n.eventsTracking,
                    isActive: _selectedIndex == 1,
                    onTap: _onEventsPressed,
                  ),
                  const SizedBox(height: 12),
                  _buildDesktopNavItem(
                    icon: user == null
                        ? Icons.login_outlined
                        : Icons.person_outline,
                    activeIcon:
                        user == null ? Icons.login_rounded : Icons.person,
                    title: user == null ? l10n.login : l10n.profile,
                    subtitle: user == null
                        ? l10n.accessYourAccount
                        : l10n.settingsAndSubscription,
                    isActive: _selectedIndex == 2,
                    onTap: () => _openProfile(authProvider),
                  ),
                  if (isAdmin) ...[
                    const SizedBox(height: 28),
                    Text(
                      l10n.administration,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.68),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDesktopNavItem(
                      icon: Icons.campaign_outlined,
                      activeIcon: Icons.campaign_rounded,
                      title: l10n.announcements,
                      subtitle: l10n.manageCampaigns,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AdminAdsScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _buildDesktopNavItem(
                      icon: Icons.admin_panel_settings_outlined,
                      activeIcon: Icons.admin_panel_settings_rounded,
                      title: l10n.adminConsole,
                      subtitle: l10n.usersAndStructures,
                      onTap: () => _navigateToAdminPanel(context),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user?.name ?? l10n.guestSession,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _roleLabel(user?.role),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopHeader(AuthProvider authProvider) {
    final user = authProvider.currentUser;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF307A59),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppConstants.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        _currentSectionIcon(),
                        color: const Color(0xFFFFFFFF),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _currentSectionTitle(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Color.fromARGB(255, 255, 255, 255),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 60),
                  child: Text(
                    _currentSectionSubtitle(user),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: Color(0xFF5D7267),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 255, 255, 255),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.laptop_mac_rounded,
                  size: 18,
                  color: Color(0xFF456354),
                ),
                const SizedBox(width: 8),
                Text(
                  user == null
                      ? context.l10n.desktopMode
                      : context.l10n.roleOnDesktop(_roleLabel(user.role)),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF375646),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isActive = false,
    String? badge,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color:
                isActive ? Colors.white.withOpacity(0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isActive
                  ? Colors.white.withOpacity(0.14)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.white.withOpacity(0.14)
                      : Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isActive ? activeIcon : icon,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Colors.white.withOpacity(0.68),
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null)
                Container(
                  margin: const EdgeInsets.only(left: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPathHistoryBar({required bool isDesktop}) {
    if (!isDesktop) {
      return Container(
        height: 40,
        color: Colors.grey[100],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              if (_selectedFac != null)
                GestureDetector(
                  onTap: _goBackInExplorer,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_back,
                      size: 16,
                      color: Color(0xFF307A59),
                    ),
                  ),
                ),
              if (_selectedFac != null) const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ..._pathHistory.asMap().entries.map((entry) {
                        final index = entry.key;
                        final item = entry.value;
                        final displayText =
                            index == 0 ? _getFacultyAbbreviation(item) : item;
                        final isLast = index == _pathHistory.length - 1;

                        return Row(
                          children: [
                            if (index > 0) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 8),
                            ],
                            GestureDetector(
                              onTap: () => _navigateToPath(index + 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isLast
                                      ? AppConstants.primaryColor
                                          .withOpacity(0.1)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: isLast
                                      ? Border.all(
                                          color: const Color(0xFF307A59)
                                              .withOpacity(0.3),
                                        )
                                      : null,
                                  boxShadow: isLast
                                      ? []
                                      : [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.05),
                                            blurRadius: 1,
                                            offset: const Offset(0, 1),
                                          ),
                                        ],
                                ),
                                child: Text(
                                  displayText,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isLast
                                        ? AppConstants.primaryColor
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
              if (_pathHistory.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppConstants.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_pathHistory.length}/4',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppConstants.primaryColor,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final backgroundColor =
        isDesktop ? Colors.white.withOpacity(0.12) : Colors.grey[100]!;
    final chipColor = isDesktop ? Colors.white.withOpacity(0.14) : Colors.white;
    final accentColor = isDesktop ? Colors.white : AppConstants.primaryColor;
    final mutedColor =
        isDesktop ? Colors.white.withOpacity(0.72) : Colors.grey[700]!;
    final dividerColor =
        isDesktop ? Colors.white.withOpacity(0.5) : Colors.grey;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(isDesktop ? 20 : 0),
        border: isDesktop
            ? Border.all(color: Colors.white.withOpacity(0.08))
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            if (_selectedFac != null)
              GestureDetector(
                onTap: _goBackInExplorer,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: chipColor,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    Icons.arrow_back,
                    size: 16,
                    color: accentColor,
                  ),
                ),
              ),
            if (_selectedFac != null) const SizedBox(width: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ..._pathHistory.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final displayText =
                          index == 0 ? _getFacultyAbbreviation(item) : item;
                      final isLast = index == _pathHistory.length - 1;

                      return Row(
                        children: [
                          if (index > 0) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: dividerColor,
                            ),
                            const SizedBox(width: 8),
                          ],
                          GestureDetector(
                            onTap: () => _navigateToPath(index + 1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: isLast
                                    ? chipColor
                                    : (isDesktop
                                        ? Colors.white.withOpacity(0.08)
                                        : Colors.white),
                                borderRadius: BorderRadius.circular(16),
                                border: isLast
                                    ? Border.all(
                                        color: isDesktop
                                            ? Colors.white.withOpacity(0.12)
                                            : AppConstants.primaryColor
                                                .withOpacity(0.3),
                                      )
                                    : null,
                              ),
                              child: Text(
                                displayText,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isLast ? accentColor : mutedColor,
                                  fontWeight: isLast
                                      ? FontWeight.w700
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
            if (_pathHistory.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(left: 12),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: chipColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${_pathHistory.length}/4',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainWorkspace() {
    final isDesktop = _useDesktopShell(context);

    return Column(
      children: [
        if (_selectedIndex == 0 || _selectedIndex == 1)
          isDesktop
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: SizedBox(
                    height: 100, // ← Ajustez selon vos besoins (80, 100, 120)
                    child: const RotatingAdBanner(),
                  ),
                )
              : const RotatingAdBanner(),
        Expanded(
          child: _isLoading
              ? const CustomLoading()
              : _selectedIndex != 0
                  ? _screens[_selectedIndex]
                  : _buildFileExplorer(),
        ),
      ],
    );
  }

  void _goBackInExplorer() {
    if (_selectedUnit != null) {
      setState(() {
        _selectedUnit = null;
        _pathHistory.removeLast();
      });
    } else if (_selectedFld != null) {
      setState(() {
        _selectedFld = null;
        _selectedUnit = null;
        _pathHistory = [_pathHistory[0], _pathHistory[1]];
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
      _onReturnToFacultiesList();
    }
    _updateLastActivity();
  }

  IconData _currentSectionIcon() {
    switch (_selectedIndex) {
      case 1:
        return Icons.event_note_rounded;
      case 2:
        return Icons.person_rounded;
      default:
        return Icons.dashboard_rounded;
    }
  }

  String _currentSectionTitle() {
    final l10n = context.l10n;
    switch (_selectedIndex) {
      case 1:
        return l10n.eventsSpace;
      case 2:
        return l10n.profileSpace;
      default:
        if (_selectedUnit != null) {
          return _selectedUnit!;
        }
        if (_selectedFld != null) {
          return _selectedFld!;
        }
        if (_selectedLvl != null) {
          return l10n.levelLabel(_selectedLvl!);
        }
        if (_selectedFac != null) {
          return _selectedFac!;
        }
        return l10n.universityLibrary;
    }
  }

  String _currentSectionSubtitle(UserModel? user) {
    final l10n = context.l10n;
    switch (_selectedIndex) {
      case 1:
        return l10n.eventsSpaceDescription;
      case 2:
        return user == null
            ? l10n.guestProfileDescription
            : l10n.profileDescription;
      default:
        if (_pathHistory.isEmpty) {
          return l10n.libraryExplorerDescription;
        }
        return l10n.currentProgress(_pathHistory.join(' / '));
    }
  }

  String _roleLabel(UserRole? role) {
    return context.l10n.roleLabel(role?.name ?? 'guest');
  }

  TextStyle get _explorerCardTitleStyle => const TextStyle(
        fontFamily: 'Aclonica',
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.15,
        letterSpacing: 0,
        color: AppConstants.primaryColor,
      );

  TextStyle get _explorerBadgeTextStyle => const TextStyle(
        fontFamily: 'Aclonica',
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        color: AppConstants.primaryColor,
      );

  Widget _buildFileExplorer() {
    if (_selectedFac == null) {
      return _buildFacultiesList();
    } else if (_selectedLvl == null) {
      return _buildLevelsList();
    } else if (_selectedFld == null) {
      return _buildFieldsList();
    } else if (_selectedUnit == null) {
      return _buildUnitsList();
    } else {
      return _buildDocumentTypesList();
    }
  }

  Widget _buildFacultiesList() {
    return _buildResponsiveExplorerList(
      itemCount: _faculties.length,
      itemBuilder: (context, index) {
        final faculty = _faculties[index];
        return _buildFacultyCard(
          abbreviation: _getFacultyAbbreviation(faculty.name),
          fullName: faculty.name,
          faculty: faculty,
        );
      },
    );
  }

  Widget _buildLevelsList() {
    return _buildResponsiveExplorerList(
      itemCount: _levels.length,
      itemBuilder: (context, index) {
        final level = _levels[index];
        return _buildLevelCard(level);
      },
    );
  }

  Widget _buildFieldsList() {
    return _buildResponsiveExplorerList(
      itemCount: _fields.length,
      itemBuilder: (context, index) {
        final field = _fields[index];
        return _buildFieldCard(field);
      },
    );
  }

  Widget _buildUnitsList() {
    return _buildResponsiveExplorerList(
      itemCount: _units.length,
      itemBuilder: (context, index) {
        final unit = _units[index];
        return _buildUnitCard(unit);
      },
    );
  }

  Widget _buildDocumentTypesList() {
    final types = _documentTypeCodes();
    return _buildResponsiveExplorerList(
      itemCount: types.length,
      itemBuilder: (context, index) {
        final type = types[index];
        return _buildDocumentTypeCard(type);
      },
    );
  }

  String _getFacultyAbbreviation(String fullName) {
    if (fullName.toLowerCase().contains('arts') &&
        fullName.toLowerCase().contains('lettres') &&
        fullName.toLowerCase().contains('humaines')) {
      return 'FALSH';
    }
    if (fullName.toLowerCase().contains('sciences') &&
        (fullName.toLowerCase().contains('éducation') ||
            fullName.toLowerCase().contains('education'))) {
      return 'FSE';
    }
    if (fullName.toLowerCase().contains('sciences') &&
        !fullName.toLowerCase().contains('éducation') &&
        !fullName.toLowerCase().contains('education')) {
      return 'FS';
    }

    final words = fullName.split(' ');
    final capitalWords = words
        .where((word) => word.isNotEmpty && word[0] == word[0].toUpperCase())
        .toList();

    if (capitalWords.length >= 2) {
      return capitalWords.take(2).map((word) => word[0]).join().toUpperCase();
    }

    return fullName
        .substring(0, fullName.length < 4 ? fullName.length : 4)
        .toUpperCase();
  }

  Widget _buildFacultyCard({
    required String abbreviation,
    required String fullName,
    required Faculty faculty,
  }) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selectFaculty(fullName),
        child: ListTile(
          dense: true,
          leading: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                abbreviation,
                style: _explorerBadgeTextStyle,
              ),
            ),
          ),
          title: Text(
            abbreviation,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _explorerCardTitleStyle,
          ),
          subtitle: Text(
            fullName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
          trailing: const Icon(Icons.chevron_right, color: Color(0xFF307A59)),
        ),
      ),
    );
  }

  Widget _buildLevelCard(String level) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selectLevel(level),
        child: ListTile(
          dense: true,
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                level,
                style: _explorerBadgeTextStyle.copyWith(fontSize: 16),
              ),
            ),
          ),
          title: Text(
            context.l10n.levelLabel(level),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _explorerCardTitleStyle,
          ),
          subtitle: Text(
            context.l10n.licenseMaster,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right, color: Color(0xFF307A59)),
        ),
      ),
    );
  }

  Widget _buildFieldCard(String field) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selectField(field),
        child: ListTile(
          dense: true,
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.category, color: Color(0xFF307A59)),
          ),
          title: Text(
            field,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _explorerCardTitleStyle,
          ),
          subtitle: Text(
            context.l10n.field,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right, color: Color(0xFF307A59)),
        ),
      ),
    );
  }

  Widget _buildUnitCard(String unit) {
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _selectUnit(unit),
        child: ListTile(
          dense: true,
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.library_books, color: Color(0xFF307A59)),
          ),
          title: Text(
            unit,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _explorerCardTitleStyle,
          ),
          subtitle: Text(
            context.l10n.teachingUnit,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right, color: Color(0xFF307A59)),
        ),
      ),
    );
  }

  void _navigateToDocumentType(String type) {
    // Navigation directe sans aucune publicité
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
  }

  Widget _buildDocumentTypeCard(String type) {
    IconData icon;
    switch (type) {
      case 'cours':
        icon = Icons.menu_book;
        break;
      case 'td':
        icon = Icons.assignment;
        break;
      case 'sujets':
        icon = Icons.quiz;
        break;
      case 'projets':
        icon = Icons.work;
        break;
      case 'autres':
        icon = Icons.folder_special;
        break;
      default:
        icon = Icons.description;
    }

    final label = _documentTypeLabel(context, type);

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _updateLastActivity(); // Mise à jour avant navigation
          _navigateToDocumentType(type);
        },
        child: ListTile(
          dense: true,
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppConstants.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF307A59)),
          ),
          title: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _explorerCardTitleStyle,
          ),
          subtitle: Text(
            context.l10n.documentsOf(label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right, color: Color(0xFF307A59)),
        ),
      ),
    );
  }

  void _navigateToAdminPanel(BuildContext context) {
    _updateLastActivity();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentUser?.role == UserRole.admin) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => AdminPanelScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.adminOnlyAccess),
          backgroundColor: Color(0xFFFF6C6C),
        ),
      );
    }
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    bool isActive = false,
    EdgeInsetsGeometry margin = const EdgeInsets.symmetric(horizontal: 8),
  }) {
    return Container(
      margin: margin,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(25),
              splashColor: AppConstants.primaryColor.withOpacity(0.2),
              highlightColor: Colors.transparent,
              child: Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22.5),
                  border: Border.all(
                    color: isActive
                        ? AppConstants.primaryColor
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Icon(icon, color: AppConstants.primaryColor, size: 24),
              ),
            ),
          ),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: isActive ? 30 : 0,
            height: isActive ? 2 : 0,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(1.5),
              boxShadow: [
                BoxShadow(color: Colors.white.withOpacity(0.5), blurRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _onWillPop() async {
    if (_selectedIndex == 0) {
      if (_selectedUnit != null) {
        setState(() {
          _selectedUnit = null;
          _pathHistory.removeLast();
        });
        return false;
      } else if (_selectedFld != null) {
        setState(() {
          _selectedFld = null;
          _selectedUnit = null;
          _pathHistory = _pathHistory.take(2).toList();
        });
        return false;
      } else if (_selectedLvl != null) {
        setState(() {
          _selectedLvl = null;
          _selectedFld = null;
          _selectedUnit = null;
          _pathHistory = _pathHistory.take(1).toList();
        });
        return false;
      } else if (_selectedFac != null) {
        setState(() {
          _openDefaultHomeWorkspaceForUser(
            Provider.of<AuthProvider>(context, listen: false).currentUser,
          );
        });
        _onReturnToFacultiesList();
        return false;
      }
    } else if (_selectedIndex == 1) {
      setState(() {
        _selectedIndex = 0;
        _openDefaultHomeWorkspaceForUser(
          Provider.of<AuthProvider>(context, listen: false).currentUser,
        );
      });
      _onReturnToEventList();
      return false;
    } else {
      setState(() {
        _selectedIndex = 0;
        _openDefaultHomeWorkspaceForUser(
          Provider.of<AuthProvider>(context, listen: false).currentUser,
        );
      });
      _onReturnToFacultiesList();
      return false;
    }
    return true;
  }
}
