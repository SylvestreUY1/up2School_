import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/file.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/file_manager_service.dart';
import '../../widgets/enhanced_file_card.dart';
import '../../widgets/file_filter_chip.dart';
import '../../utils/file_filters.dart';
import '../../utils/permissions.dart';
import 'add_file_dialog.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../main/profile_screen.dart';
import '../../config/app_config.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../l10n/app_localizations.dart';

class FilesListScreen extends StatefulWidget {
  final String faculty;
  final String level;
  final String field;
  final String unit;
  final String type;
  final Color? iconColor;

  const FilesListScreen({
    super.key,
    required this.faculty,
    required this.level,
    required this.field,
    required this.unit,
    required this.type,
    this.iconColor,
  });

  @override
  State<FilesListScreen> createState() => _FilesListScreenState();
}

class _FilesListScreenState extends State<FilesListScreen> {
  List<FileModel> _files = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 0;
  int _loadSequence = 0;
  final int _pageSize = 10;
  final ScrollController _scrollController = ScrollController();
  FileFilter _currentFilter = FileFilter.all;

  bool _useDesktopLayout(BuildContext context) {
    return AppConfig.isDesktop && MediaQuery.of(context).size.width >= 1100;
  }

  FileManagerService get _fileService => context.read<FileManagerService>();

  @override
  void initState() {
    super.initState();
    _loadFiles(refresh: true);
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadFiles({bool refresh = false}) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (!authProvider.isInitialized) {
      await authProvider.initializationDone;
    }

    final user = authProvider.currentUser;
    final requestedPage = refresh ? 0 : _currentPage;
    final loadId = ++_loadSequence;

    if (refresh) {
      setState(() {
        _currentPage = 0;
        _hasMore = true;
        _isLoading = true;
      });
    } else {
      setState(() => _isLoading = true);
    }

    try {
      if (requestedPage == 0) {
        final cachedFiles = await _fileService.getCachedFilesPage(
          faculty: widget.faculty,
          level: widget.level,
          field: widget.field,
          unit: widget.unit,
          type: widget.type,
          page: 0,
          pageSize: _pageSize,
          filter: _currentFilter,
          userId: user?.id,
        );

        if (!mounted || loadId != _loadSequence) {
          return;
        }

        if (cachedFiles.isNotEmpty) {
          setState(() {
            _files = cachedFiles;
            _hasMore = true;
            _currentPage = 1;
            _isLoading = false;
          });
        } else if (refresh) {
          setState(() => _files = []);
        }
      }

      final newFiles = await _fileService.getFilesWithPagination(
        faculty: widget.faculty,
        level: widget.level,
        field: widget.field,
        unit: widget.unit,
        type: widget.type,
        page: requestedPage,
        pageSize: _pageSize,
        filter: _currentFilter,
        userId: user?.id,
        forceRefresh: requestedPage == 0 || refresh,
      );

      if (!mounted || loadId != _loadSequence) {
        return;
      }

      setState(() {
        if (requestedPage == 0) {
          _files = _mergeFreshFiles(_files, newFiles);
        } else {
          _files = _mergePagedFiles(_files, newFiles);
        }
        _hasMore = newFiles.length == _pageSize;
        _currentPage = requestedPage + 1;
      });
    } catch (e) {
      print('⚠️  Erreur chargement fichiers: $e');
    } finally {
      if (mounted && loadId == _loadSequence) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<FileModel> _mergeFreshFiles(
    List<FileModel> currentFiles,
    List<FileModel> freshFiles,
  ) {
    final merged = <FileModel>[];
    final seenIds = <String>{};

    for (final file in freshFiles) {
      if (seenIds.add(file.id)) {
        merged.add(file);
      }
    }

    for (final file in currentFiles) {
      if (seenIds.add(file.id)) {
        merged.add(file);
      }
    }

    return merged;
  }

  List<FileModel> _mergePagedFiles(
    List<FileModel> currentFiles,
    List<FileModel> newFiles,
  ) {
    final merged = List<FileModel>.from(currentFiles);
    final existingIndexes = <String, int>{};

    for (var i = 0; i < merged.length; i++) {
      existingIndexes[merged[i].id] = i;
    }

    for (final file in newFiles) {
      final existingIndex = existingIndexes[file.id];
      if (existingIndex != null) {
        merged[existingIndex] = file;
      } else {
        existingIndexes[file.id] = merged.length;
        merged.add(file);
      }
    }

    return merged;
  }

  Future<void> _loadMore() => _loadFiles();

  Future<void> _applyFilter(FileFilter filter) async {
    setState(() {
      _currentFilter = filter;
      _currentPage = 0;
      _files.clear();
      _hasMore = true;
    });
    await _loadFiles(refresh: true);
  }

  Future<void> _refresh() async {
    await _loadFiles(refresh: true);
  }

  // MÉTHODE : supprime le fichier localement (si téléchargé)
  Future<void> _deleteLocalFile(FileModel file) async {
    try {
      bool isDownloaded = await _fileService.isFileDownloaded(file);
      if (!isDownloaded) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.fileNotAvailableLocally)),
        );
        return;
      }

      await _fileService.deleteLocalFile(file);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.localCopyDeleted),
          backgroundColor: Colors.green,
        ),
      );
      await _refresh();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppHelpers.userFriendlyErrorMessage(
            e,
            fallback: context.l10n.localCopyDeleteFailed,
          )),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // MÉTHODE : supprime le fichier distant (pour admin/délégué)
  Future<void> _deleteFile(FileModel file, AuthProvider authProvider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteFileTitle),
        content: Text(context.l10n.deleteFileMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              context.l10n.cancel,
              style: TextStyle(color: Color(0xFF307A59)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              context.l10n.delete,
              style: TextStyle(color: Color(0xFFFF6C6C)),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _fileService.deleteFile(
          file: file,
          user: authProvider.currentUser!,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.fileDeletedSuccess),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
        await _refresh();
      } catch (e) {
        print('Erreur suppression: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.fileDeleteFailed,
              ),
              backgroundColor: const Color(0xFFFF6C6C),
            ),
          );
        }
      }
    }
  }

  // MÉTHODE : génère le lien avec le schéma personnalisé
  String _generateFileLink(FileModel file) {
    return 'https://uy1-lib.netlify.app/partage/${file.id}';
  }

  // MÉTHODE : partage le lien via share_plus
  void _shareFileLink(FileModel file) {
    final link = _generateFileLink(file);
    Share.share(link, subject: context.l10n.shareFileSubject);
  }

  /// Choisit le meilleur dossier d'export selon la plateforme.
  ///
  /// Sur desktop, on privilégie le vrai dossier "Téléchargements" pour que
  /// l'utilisateur retrouve rapidement le document. Sur iOS, on reste dans
  /// le conteneur Documents de l'application.
  Future<Directory> _resolveExportDirectory() async {
    if (Platform.isAndroid) {
      return Directory('/storage/emulated/0/Download');
    }

    if (Platform.isIOS) {
      return getApplicationDocumentsDirectory();
    }

    final downloadsDirectory = await getDownloadsDirectory();
    if (downloadsDirectory != null) {
      return downloadsDirectory;
    }

    return getApplicationDocumentsDirectory();
  }

  // Méthode pour exporter le fichier vers le dossier Downloads/UY1-Lib
  Future<void> _exportFile(FileModel file) async {
    if (file.isPremiumLocked) {
      _showSubscriptionPrompt();
      return;
    }

    final currentUser =
        Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (!Permissions.canDownloadFile(currentUser, file)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentUser == null || currentUser.role == UserRole.guest
                ? context.l10n.signInToDownloadOrExport
                : context.l10n.exportRestrictedToTrack,
          ),
          backgroundColor: const Color(0xFFFF9800),
        ),
      );
      return;
    }

    try {
      if (Platform.isAndroid) {
        PermissionStatus status = await Permission.storage.request();
        if (!status.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.storagePermissionDenied),
              backgroundColor: Color(0xFFFF6C6C),
            ),
          );
          return;
        }
      }

      bool isDownloaded = await _fileService.isFileDownloaded(file);
      String? localPath;

      if (!isDownloaded) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.preparingFile)),
        );
        localPath = await _fileService.downloadFile(file, user: currentUser);
        if (localPath == null) throw 'Échec du téléchargement';
      } else {
        final directory = await getApplicationDocumentsDirectory();
        localPath = '${directory.path}/${file.fileName}';
      }

      final sourceFile = File(localPath);
      if (!await sourceFile.exists()) throw 'Fichier source introuvable';

      final downloadsDir = await _resolveExportDirectory();

      if (!await downloadsDir.exists()) {
        throw 'Dossier Downloads inaccessible';
      }

      final uy1LibDir = Directory('${downloadsDir.path}/UY1-Lib');
      if (!await uy1LibDir.exists()) {
        await uy1LibDir.create(recursive: true);
      }

      final destinationPath = '${uy1LibDir.path}/${file.fileName}';
      final destinationFile = File(destinationPath);
      final bytes = await sourceFile.readAsBytes();
      await destinationFile.writeAsBytes(bytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.fileExportedTo(destinationPath)),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.fileExportFailed),
          backgroundColor: const Color(0xFFFF6C6C),
        ),
      );
    }
  }

  void _toggleFavorite(FileModel file) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;

    if (user != null) {
      try {
        await _fileService.toggleFavorite(fileId: file.id, userId: user.id);
        await _refresh();
      } catch (e) {
        print('Erreur favori: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.favoriteAddFailed),
              backgroundColor: const Color(0xFFFF6C6C),
            ),
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.signInToAddFavorites),
          backgroundColor: Color(0xFFFF9800),
        ),
      );
    }
  }

  void _markAsOpened(FileModel file, AuthProvider authProvider) async {
    if (file.isPremiumLocked) {
      _showSubscriptionPrompt();
      return;
    }

    final user = authProvider.currentUser;
    if (user != null) {
      try {
        await _fileService.incrementViewCount(file.id, user.id);
        await _refresh();
      } catch (e) {
        print('Erreur marquer comme ouvert: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.fileOpenFailed),
              backgroundColor: const Color(0xFFFF6C6C),
            ),
          );
        }
      }
    }
  }

  void _showSubscriptionPrompt() {
    final isApplePlatform = AppConfig.isApplePlatform;
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isApplePlatform
                  ? context.l10n.accessRequired
                  : context.l10n.subscriptionRequired,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              isApplePlatform
                  ? context.l10n.previousYearArchiveAccessDescription
                  : context.l10n.previousYearArchiveDescription,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    this.context,
                    MaterialPageRoute(builder: (_) => const ProfileScreen()),
                  );
                },
                icon: const Icon(Icons.workspace_premium),
                label: Text(
                  isApplePlatform
                      ? context.l10n.checkAccess
                      : context.l10n.subscribe,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddFileDialog(AuthProvider authProvider) {
    final user = authProvider.currentUser;
    if (user == null) return;

    showDialog(
      context: context,
      builder: (context) => AddFileDialog(
        user: user,
        faculty: widget.faculty,
        level: widget.level,
        field: widget.field,
        unit: widget.unit,
        type: widget.type,
        onFileAdded: _refresh,
      ),
    );
  }

  Widget _buildDocumentCard(
    FileModel file,
    AuthProvider authProvider,
    UserModel? currentUser,
  ) {
    final canDelete = Permissions.canDeleteFile(currentUser, file);

    return EnhancedFileCard(
      file: file,
      currentUserId: currentUser?.id ?? '',
      currentUser: currentUser,
      onFavorite: () => _toggleFavorite(file),
      onDelete: () => _deleteFile(file, authProvider),
      onDeleteLocal: () => _deleteLocalFile(file),
      onCopyLink: () => _shareFileLink(file),
      onExport: () => _exportFile(file),
      canDelete: canDelete,
      onOpen: () => _markAsOpened(file, authProvider),
      onSubscribe: _showSubscriptionPrompt,
    );
  }

  Widget _buildLoadingMoreIndicator({required bool isGrid}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isGrid ? 0 : 16),
      child: const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 3,
        ),
      ),
    );
  }

  Widget _buildDocumentsView(
    AuthProvider authProvider,
    UserModel? currentUser,
  ) {
    final isDesktop = _useDesktopLayout(context);
    final itemCount = _files.length + (_hasMore ? 1 : 0);

    if (!isDesktop) {
      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index == _files.length) {
            return _buildLoadingMoreIndicator(isGrid: false);
          }

          return _buildDocumentCard(
            _files[index],
            authProvider,
            currentUser,
          );
        },
      );
    }

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: 150,
        crossAxisSpacing: 16,
        mainAxisSpacing: 12,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == _files.length) {
          return _buildLoadingMoreIndicator(isGrid: true);
        }

        return _buildDocumentCard(
          _files[index],
          authProvider,
          currentUser,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final currentUser = authProvider.currentUser;

    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(
        title: Text(
          '${widget.unit} - ${l10n.documentTypeLabel(widget.type)}',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _useDesktopLayout(context) ? 1180 : double.infinity,
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.all(_useDesktopLayout(context) ? 12 : 1),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FileFilterChip(
                        label: l10n.all,
                        filter: FileFilter.all,
                        currentFilter: _currentFilter,
                        onSelected: (filter) => _applyFilter(filter),
                      ),
                      const SizedBox(width: 8),
                      FileFilterChip(
                        label: l10n.favorites,
                        filter: FileFilter.favorites,
                        currentFilter: _currentFilter,
                        onSelected: (filter) => _applyFilter(filter),
                      ),
                      const SizedBox(width: 8),
                      FileFilterChip(
                        label: l10n.recent,
                        filter: FileFilter.recent,
                        currentFilter: _currentFilter,
                        onSelected: (filter) => _applyFilter(filter),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  color: const Color(0xFF307A59),
                  child: _files.isEmpty && !_isLoading
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.folder_open,
                                size: 100,
                                color: Color(0xFF9E9E9E),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                l10n.noFilesAvailable,
                                style: TextStyle(color: Color(0xFF9E9E9E)),
                              ),
                            ],
                          ),
                        )
                      : _buildDocumentsView(authProvider, currentUser),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: (currentUser?.role == UserRole.admin ||
              currentUser?.role == UserRole.delegate)
          ? FloatingActionButton(
              onPressed: () => _showAddFileDialog(authProvider),
              backgroundColor: const Color(0xFF307A59),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
}
