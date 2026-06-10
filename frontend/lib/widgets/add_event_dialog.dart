/**
 * FICHIER : add_event_dialog.dart
 * RÔLE : Une grande boîte de dialogue pour créer des événements (conférences, examens, fêtes, etc.).
 * Elle permet aux délégués et aux administrateurs de partager des infos importantes.
 * On peut y ajouter un titre, une description, une date, un lieu et même des images.
 */
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import '../models/event.dart';
import '../models/user.dart';
import '../models/faculty.dart';
import '../models/default_faculties.dart';
import '../services/api_service.dart';
import '../services/storage_service_interface.dart';
import '../utils/helpers.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/app_config.dart';
import '../main.dart';

class AddEventDialog extends StatefulWidget {
  final UserModel user;           // L'utilisateur qui crée l'événement
  final VoidCallback onEventCreated; // Fonction à appeler quand la création est finie

  const AddEventDialog({
    super.key,
    required this.user,
    required this.onEventCreated,
  });

  @override
  State<AddEventDialog> createState() => _AddEventDialogState();
}

class _AddEventDialogState extends State<AddEventDialog> {
  // Les "clés" et "contrôleurs" pour gérer les champs de texte du formulaire
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();

  bool _isDateFormattingInitialized = false;
  bool _isGlobal = false; // Est-ce que tout le monde voit l'événement ou juste une filière ?
  List<File> _selectedImages = []; // Liste des photos choisies sur le téléphone
  bool _uploadingImages = false;
  bool _isSubmitting = false;

  // Date et heure par défaut (demain à la même heure)
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = TimeOfDay.now();

  final ApiService _apiService = ApiService();

  // Variables pour les menus déroulants (Faculté, Niveau, Filière)
  List<Faculty> _faculties = [];
  bool _loadingFaculties = true;
  String? _selectedFaculty;
  String? _selectedLevel;
  String? _selectedField;
  List<String> _levels = [];
  List<String> _fields = [];

  @override
  void initState() {
    super.initState();
    _initializeDateFormatting();
    if (widget.user.role == UserRole.admin) {
      _loadFaculties();
    }
  }

  Future<void> _initializeDateFormatting() async {
    await initializeDateFormatting('fr_FR', null);
    if (!mounted) return;
    setState(() {
      _isDateFormattingInitialized = true;
    });
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
      print('Erreur chargement facultés: $e');
      if (!mounted) return;
      setState(() {
        _faculties = _sanitizeFaculties(getFallbackFaculties());
        _loadingFaculties = false;
      });
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

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    // Demander la permission de stockage (pour Android < 10)
    if (await Permission.storage.request().isGranted) {
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: true,
        );
        if (result != null) {
          setState(() {
            _selectedImages = result.paths.map((path) => File(path!)).toList();
          });
        }
      } catch (e) {
        print('Erreur sélection images: $e');
        _showErrorDialog('Erreur lors de la sélection des images');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Permission de stockage refusée'),
            backgroundColor: Color(0xFFFF6C6C)),
      );
    }
  }

  Future<List<String>> _uploadImages() async {
    // Seuls les admins peuvent uploader des images
    if (widget.user.role != UserRole.admin) {
      return [];
    }

    if (_selectedImages.isEmpty) return [];
    if (mounted) {
      setState(() => _uploadingImages = true);
    }

    final storageService = context.read<StorageService>();
    List<String> urls = [];

    try {
      for (var image in _selectedImages) {
        final fileName =
            'event_${DateTime.now().millisecondsSinceEpoch}_${image.path.split('/').last}';
        final path = 'events/${widget.user.id}';
        final url = await storageService.uploadFile(image, path, fileName);
        urls.add(url);
      }
    } catch (e) {
      print('Erreur upload images: $e');
      if (mounted) {
        _showErrorDialog('Erreur lors de l\'upload des images');
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingImages = false);
      }
    }
    return urls;
  }

  /**
   * CHOIX DE LA DATE
   * Affiche un petit calendrier pour choisir le jour de l'événement.
   */
  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF307A59),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  /**
   * CHOIX DE L'HEURE
   * Affiche une horloge pour choisir l'heure précise.
   */
  Future<void> _selectTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && picked != _selectedTime) {
      setState(() => _selectedTime = picked);
    }
  }

  /**
   * CRÉATION FINALE
   * On vérifie que tout est bien rempli, on envoie les images sur internet,
   * puis on enregistre l'événement dans la base de données.
   */
  Future<void> _createEvent() async {
    if (_isSubmitting || _uploadingImages) return;
    if (!_formKey.currentState!.validate()) return;

    // Validation spécifique pour admin non global
    if (widget.user.role == UserRole.admin && !_isGlobal) {
      if (_selectedFaculty == null ||
          _selectedLevel == null ||
          _selectedField == null) {
        _showErrorDialog(
            'Veuillez sélectionner la faculté, le niveau et la filière');
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final uploadedUrls = await _uploadImages();
      if (!mounted) return;

      final eventDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      if (eventDateTime.isBefore(DateTime.now())) {
        _showErrorDialog('La date et l\'heure doivent être dans le futur');
        return;
      }

      final event = Event(
        id: 'event_${DateTime.now().millisecondsSinceEpoch}',
        title: _titleController.text,
        description: _descriptionController.text,
        date: eventDateTime,
        location: _locationController.text,
        faculty: _isGlobal
            ? ''
            : (widget.user.role == UserRole.admin
                ? _selectedFaculty ?? ''
                : widget.user.faculty ?? ''),
        level: _isGlobal
            ? ''
            : (widget.user.role == UserRole.admin
                ? _selectedLevel ?? ''
                : widget.user.level ?? ''),
        field: _isGlobal
            ? ''
            : (widget.user.role == UserRole.admin
                ? _selectedField ?? ''
                : widget.user.field ?? ''),
        createdBy: widget.user.id,
        createdAt: DateTime.now(),
        imageUrls: uploadedUrls,
        isGlobal: _isGlobal,
      );

      await _apiService.addEvent(event);

      final navigatorContext = MyApp.navigatorKey.currentContext;
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      widget.onEventCreated();
      if (navigatorContext != null) {
        AppHelpers.showSnackBar(
          navigatorContext,
          'Événement créé avec succès',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('Erreur lors de la création: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erreur'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade100),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.user.role == UserRole.delegate
                      ? 'Événement pour votre filière'
                      : 'Création d\'événement',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (widget.user.role == UserRole.delegate &&
                    widget.user.field != null)
                  Text(
                    widget.user.field!,
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminFields() {
    if (widget.user.role != UserRole.admin) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        const SizedBox(height: 20),
        CheckboxListTile(
          title: const Text(
            'Annonce globale (visible par tous)',
            style: TextStyle(color: Colors.white),
          ),
          value: _isGlobal,
          onChanged: (value) {
            setState(() {
              _isGlobal = value!;
              // Réinitialiser les sélections si on passe en global
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
        const SizedBox(height: 10),
        if (!_isGlobal) ...[
          // Faculté dropdown
          if (_loadingFaculties)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child:
                  Center(child: CircularProgressIndicator(color: Colors.white)),
            )
          else
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'Faculté *',
                labelStyle: const TextStyle(color: Colors.white),
                prefixIcon: const Icon(Icons.school, color: Colors.white),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
                  borderRadius: BorderRadius.circular(10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
              ),
              dropdownColor: const Color(0xFF2E9366),
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
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              validator: (value) {
                if (!_isGlobal && value == null) {
                  return 'Veuillez sélectionner une faculté';
                }
                return null;
              },
              isExpanded: true,
            ),

          const SizedBox(height: 20),

          // Niveau dropdown
          if (_selectedFaculty != null)
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'Niveau *',
                labelStyle: const TextStyle(color: Colors.white),
                prefixIcon: const Icon(Icons.grade, color: Colors.white),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
                  borderRadius: BorderRadius.circular(10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
              ),
              dropdownColor: const Color(0xFF2E9366),
              value: _selectedLevel,
              items: _levels
                  .map((level) => DropdownMenuItem<String>(
                        value: level,
                        child: Text(
                          'Niveau $level',
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
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              validator: (value) {
                if (!_isGlobal && value == null) {
                  return 'Veuillez sélectionner un niveau';
                }
                return null;
              },
              isExpanded: true,
            ),

          const SizedBox(height: 20),

          // Filière dropdown
          if (_selectedLevel != null && _fields.isNotEmpty)
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'Filière *',
                labelStyle: const TextStyle(color: Colors.white),
                prefixIcon: const Icon(Icons.category, color: Colors.white),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
                  borderRadius: BorderRadius.circular(10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.1),
              ),
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
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              validator: (value) {
                if (!_isGlobal && value == null) {
                  return 'Veuillez sélectionner une filière';
                }
                return null;
              },
              isExpanded: true,
            ),

          // Message si aucune filière
          if (_selectedLevel != null && _fields.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Aucune filière disponible pour ce niveau',
                style: TextStyle(
                    color: Colors.white70, fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildDateTimeSection() {
    final selectedDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    return Column(
      children: [
        const SizedBox(height: 20),
        Row(
          children: [
            const Icon(Icons.calendar_today, size: 24, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Date',
                      style: TextStyle(fontSize: 14, color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('EEEE dd MMMM yyyy', 'fr_FR')
                        .format(_selectedDate),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () => _selectDate(context),
              style: ElevatedButton.styleFrom(
                foregroundColor: const Color(0xFF307A59),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text('Changer',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.access_time, size: 24, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Heure',
                      style: TextStyle(fontSize: 14, color: Colors.white70)),
                  const SizedBox(height: 4),
                  Text(
                    _selectedTime.format(context),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () => _selectTime(context),
              style: ElevatedButton.styleFrom(
                foregroundColor: const Color(0xFF307A59),
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text('Changer',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 18, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'L\'événement aura lieu ${_getTimeDifference(selectedDateTime)}',
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getTimeDifference(DateTime eventDate) {
    final now = DateTime.now();
    final difference = eventDate.difference(now);
    if (difference.inDays > 0) {
      return 'dans ${difference.inDays} jour${difference.inDays > 1 ? 's' : ''}';
    } else if (difference.inHours > 0) {
      return 'dans ${difference.inHours} heure${difference.inHours > 1 ? 's' : ''}';
    } else if (difference.inMinutes > 0) {
      return 'dans ${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''}';
    } else {
      return 'maintenant';
    }
  }

  /**
   * CHAMP DE TEXTE STYLISÉ
   * Une petite "usine" pour créer des champs de texte (Titre, Description, Lieu)
   * avec le même look vert et blanc sans répéter tout le code.
   */
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      cursorColor: Colors.white,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white),
        prefixIcon: Icon(icon, color: Colors.white),
        border: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
          borderRadius: BorderRadius.circular(10),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withOpacity(0.7)),
          borderRadius: BorderRadius.circular(10),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Colors.white, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: const BorderSide(
              color: Color.fromARGB(255, 255, 194, 190), width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: const BorderSide(
              color: Color.fromARGB(255, 255, 200, 196), width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        errorStyle: const TextStyle(color: Color.fromARGB(255, 255, 162, 155)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1),
      ),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDateFormattingInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Dialog(
      backgroundColor: const Color(0xFF307A59),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: AppConfig.isDesktop ? 720 : 560,
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.event, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Créer un événement',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _isSubmitting || _uploadingImages
                            ? null
                            : () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildInfoSection(),
                  const SizedBox(height: 20),
                  _buildTextField(
                    controller: _titleController,
                    label: 'Titre de l\'événement *',
                    icon: Icons.title,
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return 'Le titre est requis';
                      if (value.length < 3)
                        return 'Le titre doit contenir au moins 3 caractères';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  _buildTextField(
                    controller: _descriptionController,
                    label: 'Description',
                    icon: Icons.description,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),
                  _buildTextField(
                    controller: _locationController,
                    label: 'Lieu *',
                    icon: Icons.location_on,
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return 'Le lieu est requis';
                      return null;
                    },
                  ),
                  _buildAdminFields(),
                  _buildDateTimeSection(),
                  // Section Images - Uniquement pour les admins
                  if (widget.user.role == UserRole.admin) ...[
                    const SizedBox(height: 20),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Images (optionnel)',
                            style: TextStyle(color: Colors.white)),
                        const SizedBox(height: 8),
                        if (_selectedImages.isNotEmpty)
                          SizedBox(
                            height: 100,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _selectedImages.length,
                              itemBuilder: (context, index) {
                                return Stack(
                                  children: [
                                    Container(
                                      width: 100,
                                      margin: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        image: DecorationImage(
                                          image:
                                              FileImage(_selectedImages[index]),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 0,
                                      right: 8,
                                      child: IconButton(
                                        icon: const Icon(Icons.cancel,
                                            color: Colors.white, size: 20),
                                        onPressed: () {
                                          setState(() {
                                            _selectedImages.removeAt(index);
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _uploadingImages ? null : _pickImages,
                          icon: const Icon(Icons.add_photo_alternate),
                          label: Text(_uploadingImages
                              ? 'Upload en cours...'
                              : 'Ajouter des images'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF307A59),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSubmitting || _uploadingImages
                              ? null
                              : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.white),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                          child: const Text('Annuler',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isSubmitting || _uploadingImages
                              ? null
                              : _createEvent,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF307A59),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                          child: _isSubmitting || _uploadingImages
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Color(0xFF307A59), strokeWidth: 2),
                                )
                              : const Text('Créer',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
