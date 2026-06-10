import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/file.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/file_manager_service.dart';
import '../../widgets/file_card.dart';
import '../../widgets/loading_screen.dart';
import '../../utils/permissions.dart';

class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  final ApiService _apiService = ApiService();
  List<FileModel> _files = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    // Récupérer les fichiers selon les critères de sélection
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const LoadingScreen();
    }

    return _files.isEmpty
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open, size: 100, color: Colors.grey),
                SizedBox(height: 20),
                Text(
                  'Aucun fichier disponible',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _files.length,
            itemBuilder: (context, index) {
              final currentUser =
                  Provider.of<AuthProvider>(context, listen: false).currentUser;
              return FileCard(
                file: _files[index],
                onFavorite: () => _toggleFavorite(_files[index].id),
                onDelete: () => _deleteFile(_files[index]),
                showDelete:
                    Permissions.canDeleteFile(currentUser, _files[index]),
              );
            },
          );
  }

  Future<void> _toggleFavorite(String fileId) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentUser != null) {
      await _apiService.toggleFileFavorite(
        fileId,
        authProvider.currentUser!.id,
      );
      _loadFiles(); // Recharger la liste
    }
  }

  Future<void> _deleteFile(FileModel file) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.currentUser != null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Supprimer le fichier'),
          content:
              const Text('Êtes-vous sûr de vouloir supprimer ce fichier ?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await context.read<FileManagerService>().deleteFile(
                      file: file,
                      user: authProvider.currentUser!,
                    );
                _loadFiles();
              },
              child:
                  const Text('Supprimer', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    }
  }
}
