import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../services/ad_service.dart';
import '../../services/api_service.dart';
import '../../models/ad_model.dart';
import '../../models/faculty.dart';
import '../../models/default_faculties.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import '../../utils/academic_targeting.dart';
import '../../utils/helpers.dart';

class AdminAdsScreen extends StatefulWidget {
  const AdminAdsScreen({super.key});

  @override
  State<AdminAdsScreen> createState() => _AdminAdsScreenState();
}

class _AdminAdsScreenState extends State<AdminAdsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(
        title: const Text("Admin - Publicités"),
        backgroundColor: const Color(0xFF307A59),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: const Color.fromARGB(255, 197, 197, 197),
          indicatorColor: const Color.fromARGB(255, 255, 255, 255),
          tabs: const [
            Tab(text: "Liste des publicités"),
            Tab(text: "Créer une publicité"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          const AdsListTab(),
          const CreateAdTab(),
        ],
      ),
    );
  }
}

// ====================
// Onglet Liste des publicités
// ====================
class AdsListTab extends StatefulWidget {
  const AdsListTab({super.key});

  @override
  State<AdsListTab> createState() => _AdsListTabState();
}

class _AdsListTabState extends State<AdsListTab> {
  final AdService _adService = AdService();
  List<AdModel> _ads = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAds();
  }

  Future<void> _loadAds() async {
    setState(() => _isLoading = true);
    try {
      final snapshot = await _adService.getAllAds();
      if (!mounted) return;
      setState(() => _ads = snapshot);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppHelpers.userFriendlyErrorMessage(
            e,
            fallback:
                'Les publicités n’ont pas pu être chargées pour le moment.',
          )),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteAd(AdModel ad) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Supprimer la publicité"),
        content: Text("Voulez-vous vraiment supprimer \"${ad.title}\" ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Annuler"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Supprimer", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _adService.deleteAd(ad.id);
      _loadAds();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Publicité supprimée")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppHelpers.userFriendlyErrorMessage(
            e,
            fallback: 'La publicité n’a pas pu être supprimée. Réessayez.',
          )),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }
    if (_ads.isEmpty) {
      return const Center(
        child: Text(
          "Aucune publicité pour le moment.",
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _ads.length,
      itemBuilder: (context, index) {
        final ad = _ads[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: const Color.fromARGB(
              156, 118, 242, 166), // couleur du pad d'une annonce
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                ad.imageUrl,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image, color: Colors.white70),
              ),
            ),
            title: Text(
              ad.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              "Clics: ${ad.clicks}\n"
              "Du ${_formatDate(ad.startDate)} au ${_formatDate(ad.endDate)}\n"
              "${AcademicTargeting.describeAudience(isGlobal: ad.isGlobal, faculty: ad.faculty, level: ad.level, field: ad.field)}",
              style: const TextStyle(color: Color.fromARGB(255, 255, 255, 255)),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete,
                  color: Color.fromARGB(255, 255, 255, 255)),
              onPressed: () => _deleteAd(ad),
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return "—";
    return "${date.day}/${date.month}/${date.year}";
  }
}

// ====================
// Onglet Création d'une publicité
// ====================
class CreateAdTab extends StatefulWidget {
  const CreateAdTab({super.key});

  @override
  State<CreateAdTab> createState() => _CreateAdTabState();
}

class _CreateAdTabState extends State<CreateAdTab> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _targetUrlController = TextEditingController();
  final AdService _adService = AdService();
  final ApiService _apiService = ApiService();

  File? _selectedImage;
  bool _isLoading = false;
  bool _isPreparingImage = false;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isGlobal = true;
  List<Faculty> _faculties = [];
  bool _loadingFaculties = true;
  String? _selectedFaculty;
  String? _selectedLevel;
  String? _selectedField;
  List<String> _levels = [];
  List<String> _fields = [];

  bool get _hasRequiredFields =>
      _titleController.text.trim().isNotEmpty &&
      _hasValidTargetUrl &&
      _selectedImage != null &&
      _selectedImage!.existsSync() &&
      _startDate != null &&
      _endDate != null &&
      !_endDate!.isBefore(_startDate!) &&
      (_isGlobal ||
          (_selectedFaculty != null &&
              _selectedLevel != null &&
              _selectedField != null));

  bool get _isSubmitEnabled => !_isLoading && _hasRequiredFields;

  bool get _hasValidTargetUrl {
    final uri = Uri.tryParse(_targetUrlController.text.trim());
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime _endOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day, 23, 59, 59, 999);

  /// Convertit les erreurs backend techniques en message actionnable pour
  /// l'admin. Cela évite d'exposer directement les détails du token/Firebase.
  String _buildPublishErrorMessage(Object error) {
    final message = error.toString();
    final normalized = message.toLowerCase();
    if (normalized.contains('token') || normalized.contains('401')) {
      return 'Votre session a expiré. Reconnectez-vous puis réessayez.';
    }
    if (normalized.contains('admin access required') ||
        normalized.contains('403')) {
      return 'Cette action est réservée aux administrateurs.';
    }
    return message.replaceFirst('Exception: ', '');
  }

  Future<void> _pickImage() async {
    try {
      setState(() => _isPreparingImage = true);
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: false,
      );
      if (!mounted) return;
      if (result != null && result.files.single.path != null) {
        final pickedFile = File(result.files.single.path!);
        final optimizedImage = await _adService.optimizeImageForAd(pickedFile);
        if (!mounted) return;
        setState(() => _selectedImage = optimizedImage);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur sélection image: $e")),
      );
    } finally {
      if (mounted) {
        setState(() => _isPreparingImage = false);
      }
    }
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final now = DateTime.now();
    final firstAllowedDate = DateTime(now.year, now.month, now.day);
    final fallbackEndDate = firstAllowedDate.add(const Duration(days: 7));
    final initialDate = isStartDate
        ? (_startDate ?? firstAllowedDate)
        : (_endDate ?? fallbackEndDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(firstAllowedDate)
          ? firstAllowedDate
          : initialDate,
      firstDate: firstAllowedDate,
      lastDate: firstAllowedDate.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF307A59),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF307A59),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = _startOfDay(picked);
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = null;
          }
        } else {
          final normalizedEndDate = _endOfDay(picked);
          if (_startDate != null && normalizedEndDate.isBefore(_startDate!)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content:
                    Text("La date de fin doit être après la date de début"),
              ),
            );
            return;
          }
          _endDate = normalizedEndDate;
        }
      });
    }
  }

  Future<void> _publishAd() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    final formIsValid = _formKey.currentState?.validate() ?? false;
    if (!formIsValid || !_hasRequiredFields) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isGlobal
                ? "Tous les champs sont obligatoires (titre, lien, image, dates)"
                : "Tous les champs sont obligatoires, y compris le ciblage academique",
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final currentUser = authProvider.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Session utilisateur indisponible. Reconnectez-vous."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_selectedImage == null || !_selectedImage!.existsSync()) {
        throw Exception(
            'Image introuvable. Veuillez la sélectionner à nouveau.');
      }

      final imageUrl = await _adService.uploadImage(_selectedImage!);

      final ad = AdModel(
        id: '',
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        imageUrl: imageUrl,
        targetUrl: _targetUrlController.text.trim(),
        faculty: _isGlobal ? '' : (_selectedFaculty ?? ''),
        level: _isGlobal ? '' : (_selectedLevel ?? ''),
        field: _isGlobal ? '' : (_selectedField ?? ''),
        isGlobal: _isGlobal,
        startDate: _startDate,
        endDate: _endDate,
      );

      await _adService.createAd(ad, currentUser.id);

      if (!mounted) return;

      _titleController.clear();
      _descriptionController.clear();
      _targetUrlController.clear();
      setState(() {
        _selectedImage = null;
        _startDate = null;
        _endDate = null;
        _isGlobal = true;
        _selectedFaculty = null;
        _selectedLevel = null;
        _selectedField = null;
        _levels = [];
        _fields = [];
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Publicité publiée avec succès"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_buildPublishErrorMessage(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.removeListener(_handleFieldChange);
    _targetUrlController.removeListener(_handleFieldChange);
    _titleController.dispose();
    _descriptionController.dispose();
    _targetUrlController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_handleFieldChange);
    _targetUrlController.addListener(_handleFieldChange);
    _loadFaculties();
  }

  Future<void> _loadFaculties() async {
    try {
      final faculties = mergeFaculties(
        _sanitizeFaculties(await _apiService.getFaculties()),
        getFallbackFaculties(),
      );
      if (!mounted) return;
      setState(() {
        _faculties = faculties.isNotEmpty
            ? faculties
            : _sanitizeFaculties(getFallbackFaculties());
        _loadingFaculties = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _faculties = _sanitizeFaculties(getFallbackFaculties());
        _loadingFaculties = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Erreur chargement des filieres: $e")),
      );
    }
  }

  List<Faculty> _sanitizeFaculties(List<Faculty> faculties) {
    final seenNames = <String>{};
    return faculties.where((faculty) {
      final name = faculty.name.trim();
      if (name.isEmpty || seenNames.contains(name)) {
        return false;
      }
      seenNames.add(name);
      return true;
    }).toList();
  }

  void _handleFieldChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Créer une publicité',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            _buildTextField(
              _titleController,
              "Titre *",
              Icons.title,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Le titre est obligatoire';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _buildTextField(
              _descriptionController,
              "Description",
              Icons.description,
              maxLines: 3,
            ),
            const SizedBox(height: 20),
            _buildAudienceSection(),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: (_isLoading || _isPreparingImage) ? null : _pickImage,
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _selectedImage == null
                        ? const Color.fromARGB(255, 255, 255, 255)
                            .withOpacity(0.8)
                        : Colors.white.withOpacity(0.7),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _selectedImage == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isPreparingImage)
                              const SizedBox(
                                width: 34,
                                height: 34,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.6,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            else
                              Icon(
                                Icons.image,
                                size: 40,
                                color: Colors.white70,
                              ),
                            const SizedBox(height: 8),
                            Text(
                                _isPreparingImage
                                    ? "Preparation de l'image..."
                                    : "Cliquez pour choisir une image",
                                style: TextStyle(color: Colors.white70)),
                            const SizedBox(height: 8),
                            const Text(
                              'Image obligatoire',
                              style: TextStyle(
                                color: Color.fromARGB(255, 255, 255, 255),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          _selectedImage!,
                          fit: BoxFit.cover,
                          cacheWidth: 720,
                          filterQuality: FilterQuality.low,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.broken_image,
                              color: Colors.white70,
                              size: 40,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            _buildTextField(
              _targetUrlController,
              "Lien de redirection *",
              Icons.link,
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) {
                  return 'Le lien est obligatoire';
                }
                final uri = Uri.tryParse(text);
                final isValidHttpUrl = uri != null &&
                    uri.hasScheme &&
                    (uri.scheme == 'http' || uri.scheme == 'https') &&
                    uri.host.isNotEmpty;
                if (!isValidHttpUrl) {
                  return 'Entrez une URL valide (http/https)';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            _buildDatePicker("Date de début *", _startDate, true),
            const SizedBox(height: 16),
            _buildDatePicker("Date de fin *", _endDate, false),
            if (_startDate == null || _endDate == null)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Les dates de début et de fin sont obligatoires',
                  style: TextStyle(
                      color: Color.fromARGB(255, 255, 255, 255), fontSize: 12),
                ),
              ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: (_isSubmitEnabled && !_isPreparingImage)
                          ? _publishAd
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E9366),
                        disabledBackgroundColor:
                            const Color(0xFF2E9366).withOpacity(0.45),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white70,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                      ),
                      child: const Text(
                        'Publier la publicité',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller, String label, IconData icon,
      {int maxLines = 1, String? Function(String?)? validator}) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      cursorColor: Colors.white,
      maxLines: maxLines,
      validator: validator,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white),
        prefixIcon: Icon(icon, color: Colors.white),
        errorStyle: const TextStyle(color: Colors.redAccent),
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
    );
  }

  Widget _buildAudienceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Annonce globale (visible par tous)',
            style: TextStyle(color: Colors.white),
          ),
          value: _isGlobal,
          onChanged: _isLoading
              ? null
              : (value) {
                  setState(() {
                    _isGlobal = value ?? true;
                    if (_isGlobal) {
                      _selectedFaculty = null;
                      _selectedLevel = null;
                      _selectedField = null;
                      _levels = [];
                      _fields = [];
                    }
                  });
                },
          activeColor: Colors.white,
          checkColor: const Color(0xFF307A59),
        ),
        if (_isGlobal)
          const Text(
            'Cette publicite sera visible par tous les utilisateurs connectes.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          )
        else if (_loadingFaculties)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          )
        else ...[
          const SizedBox(height: 12),
          _buildDropdownField(
            value: _selectedFaculty,
            label: 'Faculte *',
            icon: Icons.school,
            items: _faculties
                .map(
                  (faculty) => DropdownMenuItem<String>(
                    value: faculty.name,
                    child: Text(
                      faculty.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedFaculty = value;
                _selectedLevel = null;
                _selectedField = null;
                _levels = [];
                _fields = [];
                if (value != null) {
                  final faculty = _faculties.firstWhere((f) => f.name == value);
                  _levels = faculty.levels;
                }
              });
            },
          ),
          const SizedBox(height: 16),
          _buildDropdownField(
            value: _selectedLevel,
            label: 'Niveau *',
            icon: Icons.grade,
            items: _levels
                .map(
                  (level) => DropdownMenuItem<String>(
                    value: level,
                    child: Text(
                      'Niveau $level',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                )
                .toList(),
            onChanged: _selectedFaculty == null
                ? null
                : (value) {
                    setState(() {
                      _selectedLevel = value;
                      _selectedField = null;
                      _fields = [];
                      if (value != null && _selectedFaculty != null) {
                        final faculty = _faculties.firstWhere(
                          (f) => f.name == _selectedFaculty,
                        );
                        _fields = faculty.fields[value] ?? [];
                      }
                    });
                  },
          ),
          const SizedBox(height: 16),
          _buildDropdownField(
            value: _selectedField,
            label: 'Filiere *',
            icon: Icons.account_tree_outlined,
            items: _fields
                .map(
                  (field) => DropdownMenuItem<String>(
                    value: field,
                    child: Text(
                      field,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                )
                .toList(),
            onChanged: _selectedLevel == null
                ? null
                : (value) {
                    setState(() => _selectedField = value);
                  },
          ),
          const SizedBox(height: 8),
          const Text(
            'Le ciblage specifique reprend la meme logique que les evenements: faculte, niveau et filiere.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildDropdownField({
    required String? value,
    required String label,
    required IconData icon,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?>? onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      items: items,
      onChanged: _isLoading ? null : onChanged,
      style: const TextStyle(color: Colors.white),
      dropdownColor: const Color(0xFF2E9366),
      icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white),
        prefixIcon: Icon(icon, color: Colors.white),
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
      isExpanded: true,
    );
  }

  Widget _buildDatePicker(
      String label, DateTime? selectedDate, bool isStartDate) {
    return GestureDetector(
      onTap: _isLoading ? null : () => _selectDate(context, isStartDate),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withOpacity(0.7)),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white.withOpacity(0.1),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, color: Colors.white70),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                selectedDate == null
                    ? label
                    : "$label : ${selectedDate.day}/${selectedDate.month}/${selectedDate.year}",
                style: TextStyle(
                    color:
                        selectedDate == null ? Colors.white70 : Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
