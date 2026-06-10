import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../../models/user.dart';
import '../../services/file_manager_service.dart';
import '../../main.dart'; // pour MyApp.navigatorKey
import '../../config/app_config.dart';
import '../../utils/helpers.dart';
import '../../utils/document_types.dart';

class AddFileDialog extends StatefulWidget {
  final UserModel user;
  final String faculty;
  final String level;
  final String field;
  final String unit;
  final String type;
  final VoidCallback onFileAdded;

  const AddFileDialog({
    super.key,
    required this.user,
    required this.faculty,
    required this.level,
    required this.field,
    required this.unit,
    required this.type,
    required this.onFileAdded,
  });

  @override
  State<AddFileDialog> createState() => _AddFileDialogState();
}

class _AddFileDialogState extends State<AddFileDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  PlatformFile? _selectedFile;

  String _buildUploadErrorMessage(Object error) {
    return AppHelpers.userFriendlyErrorMessage(
      error,
      fallback:
          'Le fichier n’a pas pu être envoyé. Vérifiez votre connexion puis réessayez.',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'txt',
          'jpg',
          'png',
          'zip',
          'ppt',
          'pptx',
          'xls',
          'xlsx'
        ],
      );

      if (result != null) {
        setState(() {
          _selectedFile = result.files.first;
          if (_nameController.text.isEmpty) {
            _nameController.text = _selectedFile!.name.split('.').first;
          }
        });
      }
    } catch (e) {
      _showError('Nous n’avons pas pu ouvrir ce fichier. Réessayez.');
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null) {
      _showError('Veuillez sélectionner un fichier');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    // Récupérer les données nécessaires avant de fermer le dialogue
    final fileManagerService = context.read<FileManagerService>();
    final file = _selectedFile!;
    final name = _nameController.text;
    final navigatorContext = MyApp.navigatorKey.currentContext;

    // Fermer immédiatement le dialogue
    Navigator.pop(context);

    // Indiquer le début de l'upload
    if (navigatorContext != null) {
      ScaffoldMessenger.of(navigatorContext).showSnackBar(
        const SnackBar(
          content: Text('Envoi du fichier en cours...'),
          duration: Duration(seconds: 1),
        ),
      );
    }

    try {
      await fileManagerService.addFile(
        file: File(file.path!),
        fileName: file.name,
        name: name,
        faculty: widget.faculty,
        level: widget.level,
        field: widget.field,
        unit: widget.unit,
        type: normalizeDocumentType(widget.type),
        user: widget.user,
      );

      if (navigatorContext != null) {
        ScaffoldMessenger.of(navigatorContext).showSnackBar(
          const SnackBar(
            content: Text('Fichier ajouté avec succès'),
            backgroundColor: Color(0xFF2E9366),
          ),
        );
      }
      widget.onFileAdded();
    } catch (e) {
      print('Erreur upload: $e');
      if (navigatorContext != null) {
        ScaffoldMessenger.of(navigatorContext).showSnackBar(
          SnackBar(
            content: Text(_buildUploadErrorMessage(e)),
            backgroundColor: const Color(0xFFFF6C6C),
          ),
        );
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFFF6C6C),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  // En-tête
                  Row(
                    children: [
                      const Icon(Icons.upload_file,
                          color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Ajouter un fichier',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Informations de destination
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Destination:',
                          style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Colors.white70),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.unit} - ${widget.type}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        Text(
                          '${widget.faculty} > ${widget.level} > ${widget.field}',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Nom du fichier
                  TextFormField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Nom du fichier *',
                      labelStyle: const TextStyle(color: Colors.white),
                      prefixIcon: const Icon(Icons.title, color: Colors.white),
                      border: OutlineInputBorder(
                        borderSide:
                            BorderSide(color: Colors.white.withOpacity(0.7)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide:
                            BorderSide(color: Colors.white.withOpacity(0.7)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide:
                            const BorderSide(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderSide: const BorderSide(
                            color: Color.fromARGB(255, 255, 194, 190),
                            width: 2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderSide: const BorderSide(
                            color: Color.fromARGB(255, 255, 200, 196),
                            width: 2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      errorStyle: const TextStyle(
                          color: Color.fromARGB(255, 255, 162, 155)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.1),
                    ),
                    cursorColor: Colors.white,
                    validator: (value) {
                      if (value == null || value.isEmpty)
                        return 'Le nom est requis';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Zone de sélection du fichier
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Fichier à uploader',
                          style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                              color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        if (_selectedFile != null)
                          Column(
                            children: [
                              const Icon(Icons.insert_drive_file,
                                  size: 50, color: Colors.white),
                              const SizedBox(height: 8),
                              Text(
                                _selectedFile!.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                              Text(
                                '${(_selectedFile!.size / 1024).toStringAsFixed(1)} KB',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ],
                          )
                        else
                          Column(
                            children: [
                              const Icon(Icons.cloud_upload,
                                  size: 50, color: Colors.white70),
                              const SizedBox(height: 8),
                              const Text(
                                'Aucun fichier sélectionné',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _pickFile,
                          icon: const Icon(Icons.attach_file,
                              color: Color(0xFF307A59)),
                          label: const Text(
                            'Sélectionner un fichier',
                            style: TextStyle(color: Color(0xFF307A59)),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF307A59),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Boutons Annuler / Uploader
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                          child: const Text(
                            'Annuler',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _uploadFile,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF307A59),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                          child: const Text(
                            'Uploader',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF307A59)),
                          ),
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
