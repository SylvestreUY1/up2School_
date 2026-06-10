import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/file.dart';
import '../models/user.dart';
import '../screens/files/file_viewer_screen.dart';
import '../services/file_manager_service.dart';
import '../utils/helpers.dart';
import '../utils/permissions.dart';

class EnhancedFileCard extends StatefulWidget {
  final FileModel file;
  final String currentUserId;
  final UserModel? currentUser;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;
  final VoidCallback onDeleteLocal;
  final VoidCallback onCopyLink;
  final VoidCallback onExport;
  final VoidCallback onOpen;
  final VoidCallback? onSubscribe;
  final bool canDelete;
  final bool showProgress;

  const EnhancedFileCard({
    super.key,
    required this.file,
    required this.currentUserId,
    required this.currentUser,
    required this.onFavorite,
    required this.onDelete,
    required this.onDeleteLocal,
    required this.onCopyLink,
    required this.onExport,
    required this.onOpen,
    this.onSubscribe,
    this.canDelete = false,
    this.showProgress = true,
  });

  @override
  State<EnhancedFileCard> createState() => _EnhancedFileCardState();
}

class _EnhancedFileCardState extends State<EnhancedFileCard> {
  late bool _isFavorited;
  bool _isDownloading = false;
  bool _isDownloaded = false;

  FileManagerService get _fileService => context.read<FileManagerService>();

  @override
  void initState() {
    super.initState();
    _isFavorited = widget.file.favorites.contains(widget.currentUserId);
    _checkIfDownloaded();
  }

  @override
  void didUpdateWidget(EnhancedFileCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file != widget.file ||
        oldWidget.currentUserId != widget.currentUserId) {
      _isFavorited = widget.file.favorites.contains(widget.currentUserId);
      _checkIfDownloaded();
    }
  }

  Future<void> _checkIfDownloaded() async {
    final downloaded = await _fileService.isFileDownloaded(widget.file);
    if (mounted && downloaded != _isDownloaded) {
      setState(() {
        _isDownloaded = downloaded;
      });
    }
  }

  // Formattage la taille du fichier de manière lisible:
  String _formatFileSize(int? bytes) {
    if (bytes == null) return 'Taille inconnue';
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} Go';
  }

  Future<void> _handleDownloadOrOpen() async {
    if (widget.file.isPremiumLocked) {
      widget.onSubscribe?.call();
      return;
    }

    if (_isDownloaded) {
      try {
        await _fileService.openDownloadedFile(widget.file);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(AppHelpers.userFriendlyErrorMessage(
                  e,
                  fallback:
                      'Le fichier n’a pas pu être ouvert sur cet appareil.',
                )),
                backgroundColor: Colors.red),
          );
        }
      }
    } else {
      if (!Permissions.canDownloadFile(widget.currentUser, widget.file)) {
        final message = widget.currentUser == null ||
                widget.currentUser?.role == UserRole.guest
            ? 'Connectez-vous pour télécharger des fichiers.'
            : 'Téléchargement autorisé uniquement pour les fichiers de votre filière et de votre niveau.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      setState(() {
        _isDownloading = true;
      });
      try {
        final result = await _fileService.downloadFile(
          widget.file,
          user: widget.currentUser,
        );
        if (mounted) {
          if (result != null) {
            setState(() {
              _isDownloaded = true;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Fichier téléchargé'),
                  backgroundColor: Colors.green),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppHelpers.userFriendlyErrorMessage(
                e,
                fallback: 'Le fichier n’a pas pu être téléchargé. Réessayez.',
              )),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isDownloading = false;
          });
        }
      }
    }
  }

  void _handleFavorite() {
    if (widget.currentUserId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connectez-vous pour ajouter aux favoris'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() {
      _isFavorited = !_isFavorited;
    });
    widget.onFavorite();
  }

  void _openFile() async {
    if (widget.file.isPremiumLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Abonnement requis pour ouvrir cette archive'),
          backgroundColor: Colors.orange,
        ),
      );
      widget.onSubscribe?.call();
      return;
    }

    widget.onOpen();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FileViewerScreen(file: widget.file),
      ),
    );
  }

  double _getReadingProgress() {
    if (widget.currentUserId.isEmpty) return 0.0;
    return widget.file.readingProgress[widget.currentUserId] ?? 0.0;
  }

  Widget _buildFileIcon(String fileType) {
    switch (fileType.toLowerCase()) {
      case 'pdf':
        return const Icon(Icons.picture_as_pdf, color: Colors.red, size: 40);
      case 'doc':
      case 'docx':
        return const Icon(Icons.description, color: Colors.blue, size: 40);
      case 'ppt':
      case 'pptx':
        return const Icon(Icons.slideshow, color: Colors.orange, size: 40);
      case 'jpg':
      case 'jpeg':
      case 'png':
        return const Icon(Icons.image, color: Colors.green, size: 40);
      case 'txt':
        return const Icon(Icons.text_fields, color: Colors.grey, size: 40);
      default:
        return const Icon(Icons.insert_drive_file, size: 40);
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openFile,
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tête avec infos
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFileIcon(widget.file.fileType),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                widget.file.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (widget.file.isPremiumLocked) ...[
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.lock,
                                size: 18,
                                color: Color(0xFFE58F00),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${widget.file.unit} • ${widget.file.type}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Ajouté le ${_formatDate(widget.file.uploadedAt)}',
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 11,
                              ),
                            ),
                            if (widget.file.size != null) ...[
                              Text(
                                ' • ',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                _formatFileSize(widget.file.size),
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (widget.file.isPremiumLocked) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF4E5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Premium',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFE58F00),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: const Row(
                          children: [
                            Icon(Icons.share, size: 20),
                            SizedBox(width: 8),
                            Text('Partager'),
                          ],
                        ),
                        onTap: widget.onCopyLink,
                      ),

                      PopupMenuItem(
                        child: const Row(
                          children: [
                            Icon(Icons.save_alt, size: 20),
                            SizedBox(width: 8),
                            Text('Exporter'),
                          ],
                        ),
                        onTap: widget.onExport,
                      ),

                      // Supprimer localement (visible si le fichier est téléchargé)
                      if (_isDownloaded)
                        PopupMenuItem(
                          child: const Row(
                            children: [
                              Icon(Icons.delete_outline,
                                  size: 20,
                                  color: Color.fromARGB(255, 255, 150, 108)),
                              SizedBox(width: 8),
                              Text('Supprimer localement',
                                  style: TextStyle(color: Color(0xFFFF6C6C))),
                            ],
                          ),
                          onTap: widget.onDeleteLocal,
                        ),

                      if (widget.canDelete)
                        PopupMenuItem(
                          child: const Row(
                            children: [
                              Icon(Icons.delete,
                                  size: 20, color: Color(0xFFFF4A4A)),
                              SizedBox(width: 8),
                              Text('Supprimer',
                                  style: TextStyle(color: Color(0xFFFF4A4A))),
                            ],
                          ),
                          onTap: widget.onDelete,
                        ),
                    ],
                  ),
                ],
              ),

              // Barre de progression si disponible
              if (widget.showProgress && widget.file.lastOpened != null)
                Column(
                  children: [
                    const SizedBox(height: 2),
                    LinearProgressIndicator(
                      value: _getReadingProgress(),
                      backgroundColor: Colors.grey[200],
                      color: const Color(0xFF307A59),
                    ),
                    const SizedBox(height: 0.1),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${(_getReadingProgress() * 100).toStringAsFixed(0)}% lu',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 1),
              if (widget.file.isPremiumLocked)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Archive reservee aux abonnes actifs.',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: widget.onSubscribe,
                      icon: const Icon(Icons.workspace_premium, size: 18),
                      label: const Text('S\'abonner'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E9366),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      child: IconButton(
                        icon: Icon(
                          _isFavorited ? Icons.star : Icons.star_border,
                          color: _isFavorited ? Colors.amber : Colors.grey,
                          size: 20,
                        ),
                        onPressed: _handleFavorite,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        splashRadius: 20,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: _isDownloading
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: Icon(
                                _isDownloaded
                                    ? Icons.folder_open
                                    : Icons.download,
                                size: 20,
                                color: _isDownloaded ? Colors.green : null,
                              ),
                              onPressed: _handleDownloadOrOpen,
                            ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
