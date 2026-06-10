import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../models/faculty.dart';
import '../../models/default_faculties.dart';
import '../../l10n/app_localizations.dart';
import 'auth_form_theme.dart';
import '../../utils/helpers.dart';

/// Écran d'inscription.
///
/// Ce widget agrège à la fois les informations de compte et
/// les informations académiques, car ces données conditionnent
/// ensuite les contenus visibles dans l'application.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();

  List<Faculty> _faculties = sanitizeFaculties(getFallbackFaculties());
  String? _selectedFaculty;
  String? _selectedLevel;
  String? _selectedField;
  List<String> _levels = [];
  List<String> _fields = [];
  bool _isLoading = false;
  final bool _loadingFaculties = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Centralise le style des listes déroulantes pour réduire la duplication.
  InputDecoration _dropdownDecoration(String label, IconData icon) {
    return AuthFormTheme.inputDecoration(label: label, icon: icon);
  }

  @override
  void initState() {
    super.initState();
    _loadFaculties();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadFaculties() async {
    try {
      final apiService = ApiService();
      final remoteFaculties = mergeFaculties(
        sanitizeFaculties(await apiService.getFaculties()),
        getFallbackFaculties(),
      );

      if (remoteFaculties.isEmpty) {
        print(
          '⚠️ Aucune faculté distante chargée dans l\'inscription - utilisation du catalogue local',
        );
        return;
      }

      if (!mounted) return;
      setState(() {
        _faculties = remoteFaculties;
      });
      print(
          '✅ FACULTÉS DISTANTES CHARGÉES POUR INSCRIPTION (${_faculties.length})');
    } catch (e) {
      print('❌ Erreur chargement facultés distantes pour inscription: $e');
    }
  }

  Future<void> _register() async {
    final l10n = context.l10n;
    if (!_formKey.currentState!.validate()) return;

    // Les menus académiques restent obligatoires car ils déterminent
    // le ciblage des événements, fichiers et notifications.
    if (_selectedFaculty == null ||
        _selectedLevel == null ||
        _selectedField == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.selectAcademicPath),
          backgroundColor: const Color.fromARGB(255, 255, 162, 155),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.register(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        name: _nameController.text.trim(),
        faculty: _selectedFaculty!,
        level: _selectedLevel!,
        field: _selectedField!,
      );
      if (mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppHelpers.userFriendlyErrorMessage(
              e,
              fallback: l10n.registerErrorDefault,
            ),
          ),
          backgroundColor: const Color.fromARGB(255, 255, 162, 155),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'UY1-lib',
          style: TextStyle(
              fontFamily: 'Aclonica',
              fontSize: 38,
              fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        // AJOUTER SafeArea
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                Text(
                  l10n.register,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 30),
                TextFormField(
                  controller: _nameController,
                  decoration: AuthFormTheme.inputDecoration(
                    label: l10n.fullName,
                    icon: Icons.person,
                  ),
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l10n.enterFullName;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _emailController,
                  decoration: AuthFormTheme.inputDecoration(
                    label: l10n.email,
                    icon: Icons.email,
                  ),
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l10n.enterEmail;
                    }
                    if (!value.contains('@') || !value.contains('.')) {
                      return l10n.invalidEmail;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _passwordController,
                  decoration: AuthFormTheme.inputDecoration(
                    label: l10n.password,
                    icon: Icons.lock,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.white.withOpacity(0.7),
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  obscureText: _obscurePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l10n.enterNewPassword;
                    }
                    if (value.length < 6) {
                      return l10n.passwordTooShort;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: AuthFormTheme.inputDecoration(
                    label: l10n.confirmPassword,
                    icon: Icons.lock,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: Colors.white.withOpacity(0.7),
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  obscureText: _obscureConfirmPassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return l10n.confirmYourPassword;
                    }
                    if (value != _passwordController.text) {
                      return l10n.passwordsDoNotMatch;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 30),
                Text(
                  l10n.academicInformation,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),

                // SECTION FACULTÉ
                if (_loadingFaculties)
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  )
                else
                  DropdownButtonFormField<String>(
                    decoration: _dropdownDecoration(l10n.faculty, Icons.school),
                    dropdownColor: const Color(0xFF2E9366),
                    value: _selectedFaculty,
                    items: _faculties
                        .map((faculty) => DropdownMenuItem<String>(
                              value: faculty.name,
                              child: Text(
                                faculty.name,
                                style: const TextStyle(color: Colors.white),
                                overflow: TextOverflow
                                    .ellipsis, // AJOUTER CETTE LIGNE
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedFaculty = value;
                        _selectedLevel = null;
                        _selectedField = null;
                        _levels = [];
                        _fields = [];

                        if (value != null) {
                          final faculty =
                              _faculties.firstWhere((f) => f.name == value);
                          _levels = faculty.levels;
                        }
                      });
                    },
                    style: const TextStyle(color: Colors.white),
                    icon:
                        const Icon(Icons.arrow_drop_down, color: Colors.white),
                    validator: (value) {
                      if (value == null) {
                        return l10n.selectFaculty;
                      }
                      return null;
                    },
                    isExpanded: true,
                  ),

                const SizedBox(height: 20),

                // SECTION NIVEAU
                if (_selectedFaculty != null)
                  DropdownButtonFormField<String>(
                    decoration: _dropdownDecoration(l10n.level, Icons.grade),
                    dropdownColor: const Color(0xFF2E9366),
                    value: _selectedLevel,
                    items: _levels
                        .map((level) => DropdownMenuItem<String>(
                              value: level,
                              child: Text(
                                level,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedLevel = value;
                        _selectedField = null;
                        _fields = [];

                        if (value != null && _selectedFaculty != null) {
                          final faculty = _faculties
                              .firstWhere((f) => f.name == _selectedFaculty);
                          _fields = faculty.fields[value] ?? [];
                        }
                      });
                    },
                    style: const TextStyle(color: Colors.white),
                    icon:
                        const Icon(Icons.arrow_drop_down, color: Colors.white),
                    validator: (value) {
                      if (value == null) {
                        return l10n.selectLevel;
                      }
                      return null;
                    },
                    isExpanded: true,
                  ),

                const SizedBox(height: 20),

                // SECTION FILIÈRE
                if (_selectedLevel != null && _fields.isNotEmpty)
                  DropdownButtonFormField<String>(
                    decoration: _dropdownDecoration(l10n.field, Icons.category),
                    dropdownColor: const Color(0xFF2E9366),
                    value: _selectedField,
                    items: _fields
                        .map((field) => DropdownMenuItem<String>(
                              value: field,
                              child: Text(
                                field,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedField = value;
                      });
                    },
                    style: const TextStyle(color: Colors.white),
                    icon:
                        const Icon(Icons.arrow_drop_down, color: Colors.white),
                    validator: (value) {
                      if (value == null) {
                        return l10n.selectField;
                      }
                      return null;
                    },
                    isExpanded: true, // AJOUTER CETTE LIGNE
                  ),

                // Message si aucune filière disponible
                if (_selectedLevel != null && _fields.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      l10n.noFieldAvailableForLevel,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),

                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : ElevatedButton(
                          onPressed: _register,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E9366),
                            foregroundColor:
                                const Color.fromARGB(255, 255, 255, 255),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          child: Text(
                            l10n.signUp,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    Navigator.popUntil(context, (route) => route.isFirst);
                  },
                  style: TextButton.styleFrom(
                    overlayColor: Colors.white.withOpacity(0.1),
                  ),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '${l10n.alreadyHaveAccount} ',
                          style: const TextStyle(
                            color: Color(0xFF222222),
                          ),
                        ),
                        TextSpan(
                          text: l10n.signIn,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
