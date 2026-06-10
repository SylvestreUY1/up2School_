/**
 * FICHIER : file_card.dart
 * RÔLE : C'est le composant graphique (Widget) qui affiche un fichier dans la liste.
 * Il permet de voir le nom du cours, de le télécharger, de le mettre en favoris 
 * ou de l'ouvrir pour le lire.
 */
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/file.dart';
import '../providers/auth_provider.dart';
import '../services/file_manager_service.dart';
import '../utils/permissions.dart';

class FileCard extends StatefulWidget {
  final FileModel file; // Les données du fichier à afficher
  final VoidCallback onFavorite; // Action quand on clique sur le coeur
  final VoidCallback onDelete; // Action quand on supprime (si autorisé)
  final bool showDelete; // Est-ce qu'on affiche le bouton supprimer ?

  const FileCard({
    super.key,
    required this.file,
    required this.onFavorite,
    required this.onDelete,
    this.showDelete = false,
  });

  @override
  State<FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<FileCard> {
  bool _isDownloaded =
      false; // Est-ce que le fichier est déjà sur le téléphone ?
  bool _isDownloading = false; // Est-ce qu'on est en train de le télécharger ?
  double _downloadProgress = 0.0; // Barre de progression (0.0 à 1.0)

  FileManagerService get _fileService => context.read<FileManagerService>();

  @override
  void initState() {
    super.initState();
    _checkIfDownloaded(); // On vérifie dès le début si on a déjà le fichier
  }

  /**
   * ACTION : Que faire quand on clique sur le bouton principal (Télécharger ou Ouvrir)
   */
  Future<void> _handleFileAction() async {
    final currentUser =
        Provider.of<AuthProvider>(context, listen: false).currentUser;

    // 1. Si déjà téléchargé, on l'ouvre directement
    if (_isDownloaded) {
      try {
        await _fileService.openDownloadedFile(widget.file);
      } catch (e) {
        _showError('Impossible d’ouvrir le fichier.');
      }
    } else {
      // 2. Sinon, on vérifie si l'utilisateur a le droit de le prendre
      if (!Permissions.canDownloadFile(currentUser, widget.file)) {
        _showError('Vous n’avez pas les droits pour télécharger ce fichier.');
        return;
      }

      // 3. On lance le téléchargement
      setState(() {
        _isDownloading = true;
        _downloadProgress = 0.0;
      });
      try {
        await _fileService.downloadFile(
          widget.file,
          user: currentUser,
          onReceiveProgress: (received, total) {
            if (total > 0) setState(() => _downloadProgress = received / total);
          },
        );
        setState(() {
          _isDownloaded = true;
          _isDownloading = false;
        });
      } catch (e) {
        setState(() => _isDownloading = false);
        _showError('Erreur lors du téléchargement.');
      }
    }
  }

  /**
   * DESSIN : Comment la carte s'affiche à l'écran
   */
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                _getFileIcon(widget
                    .file.fileType), // Icône selon le type (.pdf, .doc...)
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.file.name,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('${widget.file.field} • ${widget.file.type}',
                          style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                // Bouton Favoris
                IconButton(
                  icon: Icon(
                      widget.file.favorites.isNotEmpty
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: Colors.red),
                  onPressed: widget.onFavorite,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Boutons d'actions en bas
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_isDownloading)
                  CircularProgressIndicator(
                      value: _downloadProgress) // Cercle de progression
                else
                  IconButton(
                    icon: Icon(
                        _isDownloaded ? Icons.folder_open : Icons.download,
                        color: Colors.green),
                    onPressed: _handleFileAction,
                  ),
                if (widget.showDelete)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: widget.onDelete,
                  ),
              ],
            )
          ],
        ),
      ),
    );
  }

  // Affiche une petite icône différente pour les PDF ou les documents Word
  Widget _getFileIcon(String fileType) {
    if (fileType.toLowerCase() == 'pdf')
      return const Icon(Icons.picture_as_pdf, color: Colors.red, size: 40);
    return const Icon(Icons.description, color: Colors.blue, size: 40);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  Future<void> _checkIfDownloaded() async {
    final downloaded = await _fileService.isFileDownloaded(widget.file);
    if (mounted) setState(() => _isDownloaded = downloaded);
  }
}
