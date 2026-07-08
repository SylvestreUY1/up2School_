import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:open_filex/open_filex.dart';
import '../../screens/main/profile_screen.dart';

import '../../config/app_config.dart';
import '../../models/file.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../services/file_manager_service.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/constants.dart';
import '../../utils/helpers.dart';
import '../../utils/permissions.dart';

class FileViewerScreen extends StatefulWidget {
  final FileModel file;

  const FileViewerScreen({super.key, required this.file});

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  late final FileManagerService _fileService;
  final TextEditingController _searchController = TextEditingController();
  final Dio _dio = Dio();
  final ValueNotifier<int> _currentPageNotifier = ValueNotifier(1);
  final ValueNotifier<int> _totalPagesNotifier = ValueNotifier(1);
  final ValueNotifier<double> _progressNotifier = ValueNotifier(0.0);
  final ValueNotifier<bool> _pdfLoadingNotifier = ValueNotifier(true);

  double _zoomLevel = 1.0;
  PdfViewerController? _pdfController;
  bool _showSearchBar = false;
  String _searchText = '';
  double _currentProgress = 0.0;
  bool _isLoadingProgress = true;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _localFilePath;
  String? _remoteFileUrl;
  Future<String>? _textContentFuture;
  Future<void>? _viewerPreparationFuture;
  Timer? _progressSaveDebounce;
  Timer? _searchDebounce;
  int _currentPage = 1;
  int _totalPages = 1;
  double _lastSavedProgress = 0.0;
  bool _isLocalFileReady = false;
  bool get _isLocked => widget.file.isPremiumLocked;

  static const _textExtensions = {
    'txt',
    'rtf',
    'md',
    'csv',
    'json',
    'xml',
    'html',
    'css',
    'js',
    'dart',
    'java',
    'cpp',
    'c',
    'py',
    'php',
    'rb',
    'go',
    'rs',
    'kt',
    'swift',
    'ts',
    'sh',
    'yml',
    'yaml',
    'ini',
    'log',
  };

  @override
  void initState() {
    super.initState();
    _fileService = context.read<FileManagerService>();
    _loadProgress();
    _markFileAsOpened();
    _checkIfDownloaded();
    _refreshRemoteFileUrl();

    if (widget.file.fileType.toLowerCase() == 'pdf') {
      _pdfController = PdfViewerController();
    }

    if (_isTextFile && !AppConfig.useBackendForProtectedFiles) {
      _textContentFuture = _loadTextContent();
    }

    if (_shouldPrepareViewerLocally) {
      _viewerPreparationFuture = _prepareViewerSource();
    }
  }

  /// Recharge une URL fraîche quand le backend protège les fichiers
  /// avec des jetons temporaires.
  Future<void> _refreshRemoteFileUrl() async {
    try {
      final freshUrl = await _fileService.getFreshFileUrl(widget.file);
      if (!mounted) return;
      setState(() {
        _remoteFileUrl = freshUrl;
        if (_isTextFile && _localFilePath == null) {
          _textContentFuture = _loadTextContent();
        }
      });
    } catch (e) {
      print('Erreur rafraîchissement URL distante: $e');
      if (!mounted) return;
      setState(() {
        _remoteFileUrl = widget.file.url;
        if (_isTextFile && _localFilePath == null) {
          _textContentFuture = _loadTextContent();
        }
      });
    }
  }

  String get _effectiveRemoteUrl => _remoteFileUrl ?? widget.file.url;
  bool get _isTextFile => _textExtensions
      .contains(widget.file.fileName.split('.').last.toLowerCase());

  Future<void> _loadProgress() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;

    if (user != null) {
      setState(() {
        _currentProgress = widget.file.readingProgress[user.id] ?? 0.0;
        _lastSavedProgress = _currentProgress;
        _isLoadingProgress = false;
      });
      _progressNotifier.value = _currentProgress;
    } else {
      setState(() {
        _isLoadingProgress = false;
      });
    }
  }

  Future<void> _markFileAsOpened() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;

    if (user != null) {
      widget.file.markAsOpened(user.id);
    }
  }

  Future<void> _checkIfDownloaded() async {
    try {
      final isDownloaded = await _fileService.isFileDownloaded(widget.file);
      if (isDownloaded) {
        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/${widget.file.fileName}';
        final localFile = File(filePath);
        if (!await localFile.exists()) {
          return;
        }
        setState(() {
          _localFilePath = filePath;
          _isLocalFileReady = true;
          if (_isTextFile) {
            _textContentFuture = _loadTextContent();
          }
        });
      }
    } catch (e) {
      print('Erreur vérification fichier téléchargé: $e');
    }
  }

  Future<void> _updateProgress(double progress) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;

    if (user == null || progress <= _lastSavedProgress) return;

    try {
      await _fileService.updateReadingProgress(
        fileId: widget.file.id,
        userId: user.id,
        progress: progress,
      );
      _lastSavedProgress = progress;
    } catch (e) {
      print('Erreur mise à jour progression: $e');
    }
  }

  void _scheduleProgressSave(double progress) {
    _progressSaveDebounce?.cancel();
    _progressSaveDebounce = Timer(const Duration(milliseconds: 400), () {
      _updateProgress(progress);
    });
  }

  void _handlePdfPageChanged(PdfPageChangedDetails details) {
    final newPage = details.newPageNumber;
    final progress = _totalPages > 0 ? newPage / _totalPages : 0.0;
    final shouldRefreshProgress =
        progress > _currentProgress + 0.01 || progress >= 1.0;

    if (newPage != _currentPage) {
      _currentPage = newPage;
      _currentPageNotifier.value = newPage;
    }

    if (shouldRefreshProgress) {
      _currentProgress = progress;
      _progressNotifier.value = progress;
    }

    if (shouldRefreshProgress) {
      _scheduleProgressSave(progress);
    }
  }

  bool get _shouldPrepareViewerLocally {
    final extension = widget.file.fileName.split('.').last.toLowerCase();
    return !_isLocked && (extension == 'pdf' || _isTextFile);
  }

  Future<void> _prepareViewerSource() async {
    if (_isLocalFileReady) return;

    final preparedPath = await _fileService.prepareFileForViewing(widget.file);
    if (!mounted || preparedPath == null) return;

    setState(() {
      _localFilePath = preparedPath;
      _isLocalFileReady = true;
      if (_isTextFile) {
        _textContentFuture = _loadTextContent();
      }
    });
  }

  void _handleSearchChanged(String value, {required bool isPdf}) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      Duration(milliseconds: isPdf ? 250 : 120),
      () {
        if (!mounted) return;
        setState(() => _searchText = value);
        if (isPdf) {
          _performSearch();
        }
      },
    );
  }

  Future<void> _downloadFile() async {
    final l10n = context.l10n;
    if (_isLocked) {
      _showSubscriptionRequired();
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.currentUser;
    if (!Permissions.canDownloadFile(user, widget.file)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            user == null || user.role == UserRole.guest
                ? l10n.signInToDownloadFiles
                : l10n.downloadRestrictedToTrack,
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      final filePath = await _fileService.downloadFile(
        widget.file,
        user: user,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            setState(() {
              _downloadProgress = received / total;
            });
          }
        },
      );
      if (filePath == null) {
        throw l10n.downloadUnavailable;
      }

      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
        _localFilePath = filePath;
        _isLocalFileReady = true;
        if (_isTextFile) {
          _textContentFuture = _loadTextContent();
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.fileDownloadedSuccess),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Erreur téléchargement: $e');
      setState(() {
        _isDownloading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppHelpers.userFriendlyErrorMessage(
              e,
              fallback: l10n.fileDownloadFailed,
            )),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _openInExternalApp() async {
    final l10n = context.l10n;
    if (_isLocked) {
      _showSubscriptionRequired();
      return;
    }

    // Si le fichier est déjà téléchargé localement, on l'ouvre directement
    if (_localFilePath != null && await File(_localFilePath!).exists()) {
      try {
        await OpenFilex.open(_localFilePath!);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.fileOpenOnDeviceFailed),
            backgroundColor: Color(0xFFFF6C6C),
          ),
        );
      }
      return;
    }

    // Sinon, on essaie d'ouvrir l'URL distante
    final url = Uri.parse(_effectiveRemoteUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );
    } else {
      // Suggérer une application selon l'extension
      final extension = widget.file.fileName.split('.').last.toLowerCase();
      String suggestion = '';
      if (extension == 'pptx' || extension == 'ppt') {
        suggestion = l10n.installPowerPointSuggestion;
      } else if (extension == 'docx' || extension == 'doc') {
        suggestion = l10n.installWordSuggestion;
      } else if (extension == 'xlsx' || extension == 'xls') {
        suggestion = l10n.installExcelSuggestion;
      } else if (extension == 'pdf') {
        suggestion = l10n.installPdfSuggestion;
      } else {
        suggestion = l10n.installCompatibleAppSuggestion;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.unableToOpenFileWithSuggestion(suggestion)),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _copyFileLink() async {
    final l10n = context.l10n;
    if (_isLocked) {
      _showSubscriptionRequired();
      return;
    }

    await Clipboard.setData(
      ClipboardData(text: AppHelpers.generateFileShareLink(widget.file.id)),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.linkCopied),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<String> _loadTextContent() async {
    final l10n = context.l10n;
    if (_isLocked) {
      return l10n.archiveSubscriptionRequired;
    }

    if (_localFilePath != null && await File(_localFilePath!).exists()) {
      return await File(_localFilePath!).readAsString();
    } else {
      try {
        final response = await _dio.get(_effectiveRemoteUrl);
        return response.data.toString();
      } catch (e) {
        return '''
${l10n.fileLabel}: ${widget.file.name}
URL: $_effectiveRemoteUrl
${l10n.extensionLabel}: ${widget.file.fileType}

${l10n.contentUnavailableNeedDownload}

${l10n.downloadsLabel}: ${widget.file.downloadCount}
${l10n.viewsLabel}: ${widget.file.viewCount}
${l10n.favorites}: ${widget.file.favorites.length}
${l10n.progressLabel}: ${(_currentProgress * 100).toStringAsFixed(0)}%

${_searchText.isNotEmpty ? l10n.activeSearchFor(_searchText) : l10n.useSearchBarToFindText}
''';
      }
    }
  }

  Widget _buildViewer() {
    final extension = widget.file.fileName.split('.').last.toLowerCase();
    final bool isLocalAvailable = _isLocalFileReady;
    final bool waitingForRemoteUrl = !isLocalAvailable &&
        AppConfig.useBackendForProtectedFiles &&
        _remoteFileUrl == null;

    if (waitingForRemoteUrl) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF307A59)),
      );
    }

    if (!isLocalAvailable && _viewerPreparationFuture != null) {
      return FutureBuilder<void>(
        future: _viewerPreparationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF307A59)),
            );
          }

          return _buildViewerContent(extension, _isLocalFileReady);
        },
      );
    }

    return _buildViewerContent(extension, isLocalAvailable);
  }

  Widget _buildViewerContent(String extension, bool isLocalAvailable) {
    switch (extension) {
      case 'pdf':
        return Stack(
          children: [
            if (isLocalAvailable && _localFilePath != null)
              SfPdfViewer.file(
                File(_localFilePath!),
                controller: _pdfController,
                canShowScrollHead: true,
                canShowScrollStatus: true,
                pageLayoutMode: PdfPageLayoutMode.continuous,
                interactionMode: PdfInteractionMode.pan,
                onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                  _totalPages = details.document.pages.count;
                  _totalPagesNotifier.value = _totalPages;
                  _pdfLoadingNotifier.value = false;
                },
                onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
                  _pdfLoadingNotifier.value = false;
                },
                onPageChanged: _handlePdfPageChanged,
              )
            else
              SfPdfViewer.network(
                _effectiveRemoteUrl,
                controller: _pdfController,
                canShowScrollHead: true,
                canShowScrollStatus: true,
                pageLayoutMode: PdfPageLayoutMode.continuous,
                interactionMode: PdfInteractionMode.pan,
                onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                  _totalPages = details.document.pages.count;
                  _totalPagesNotifier.value = _totalPages;
                  _pdfLoadingNotifier.value = false;
                },
                onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
                  _pdfLoadingNotifier.value = false;
                },
                onPageChanged: _handlePdfPageChanged,
              ),
            ValueListenableBuilder<bool>(
              valueListenable: _pdfLoadingNotifier,
              builder: (context, isLoading, child) {
                if (!isLoading) {
                  return const SizedBox.shrink();
                }

                return const Center(
                  child: CircularProgressIndicator(color: Color(0xFF307A59)),
                );
              },
            ),
          ],
        );

      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
        if (isLocalAvailable && _localFilePath != null) {
          return PhotoView(
            imageProvider: FileImage(File(_localFilePath!)),
            backgroundDecoration: const BoxDecoration(color: Colors.white),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3.0,
            initialScale: PhotoViewComputedScale.contained,
          );
        } else {
          return PhotoView(
            imageProvider: CachedNetworkImageProvider(_effectiveRemoteUrl),
            backgroundDecoration: const BoxDecoration(color: Colors.white),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 3.0,
            initialScale: PhotoViewComputedScale.contained,
          );
        }

      case 'txt':
      case 'rtf':
      case 'md':
      case 'csv':
      case 'json':
      case 'xml':
      case 'html':
      case 'css':
      case 'js':
      case 'dart':
      case 'java':
      case 'cpp':
      case 'c':
      case 'py':
      case 'php':
      case 'rb':
      case 'go':
      case 'rs':
      case 'kt':
      case 'swift':
      case 'ts':
      case 'sh':
      case 'yml':
      case 'yaml':
      case 'ini':
      case 'log':
        return _buildTextViewer();

      case 'odt':
      case 'ods':
      case 'odp':
      case 'odg':
      case 'odf':
      case 'odb':
      case 'odc':
        return _buildOpenDocumentViewer();

      case 'doc':
      case 'docx':
      case 'xls':
      case 'xlsx':
      case 'ppt':
      case 'pptx':
      case 'mdb':
        return _buildOfficeDocumentViewer();

      case 'epub':
      case 'mobi':
      case 'azw':
      case 'fb2':
        return _buildEbookViewer();

      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
      case 'bz2':
        return _buildArchiveViewer();

      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'flac':
      case 'aac':
      case 'm4a':
      case 'wma':
        return _buildAudioViewer();

      case 'mp4':
      case 'avi':
      case 'mkv':
      case 'mov':
      case 'wmv':
      case 'flv':
      case 'webm':
        return _buildVideoViewer();

      default:
        return _buildUnsupportedViewer(extension);
    }
  }

  Widget _buildTextViewer() {
    final l10n = context.l10n;
    _textContentFuture ??= _loadTextContent();
    return FutureBuilder<String>(
      future: _textContentFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Color(0xFF307A59)));
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Color(0xFFFF6C6C)),
                const SizedBox(height: 16),
                Text(
                  l10n.eventLoadingError,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  snapshot.error.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }
        if (snapshot.hasData) {
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: _buildHighlightedText(snapshot.data!),
            ),
          );
        }
        return const Center(
            child: CircularProgressIndicator(color: Color(0xFF307A59)));
      },
    );
  }

  Widget _buildHighlightedText(String text) {
    if (_searchText.isEmpty) {
      return SelectableText(
        text,
        style: TextStyle(
          fontSize: 16 * _zoomLevel,
          fontFamily: 'Monospace',
          height: 1.5,
        ),
      );
    }
    final lowerText = text.toLowerCase();
    final lowerSearch = _searchText.toLowerCase();
    final matches = lowerText.allMatches(lowerSearch);
    if (matches.isEmpty) {
      return SelectableText(
        text,
        style: TextStyle(
          fontSize: 16 * _zoomLevel,
          fontFamily: 'Monospace',
          height: 1.5,
        ),
      );
    }
    final textSpans = <TextSpan>[];
    int previousEnd = 0;
    for (final match in matches) {
      if (match.start > previousEnd) {
        textSpans.add(TextSpan(
          text: text.substring(previousEnd, match.start),
          style: TextStyle(
            fontSize: 16 * _zoomLevel,
            fontFamily: 'Monospace',
            color: Colors.black,
          ),
        ));
      }
      textSpans.add(TextSpan(
        text: text.substring(match.start, match.end),
        style: TextStyle(
          fontSize: 16 * _zoomLevel,
          fontFamily: 'Monospace',
          color: Colors.white,
          backgroundColor: Colors.orange,
          fontWeight: FontWeight.bold,
        ),
      ));
      previousEnd = match.end;
    }
    if (previousEnd < text.length) {
      textSpans.add(TextSpan(
        text: text.substring(previousEnd),
        style: TextStyle(
          fontSize: 16 * _zoomLevel,
          fontFamily: 'Monospace',
          color: Colors.black,
        ),
      ));
    }
    return SelectableText.rich(
      TextSpan(children: textSpans),
      style: TextStyle(
        fontSize: 16 * _zoomLevel,
        fontFamily: 'Monospace',
        height: 1.5,
      ),
    );
  }

  Widget _buildOpenDocumentViewer() {
    final l10n = context.l10n;
    final extension = widget.file.fileName.split('.').last.toLowerCase();
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.description, size: 100, color: Color(0xFF307A59)),
          const SizedBox(height: 20),
          Text(
            l10n.openDocumentType(l10n.openDocumentKind(extension)),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            widget.file.fileName,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              l10n.openDocumentDescription,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 30),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _downloadFile,
                icon: const Icon(Icons.download),
                label: Text(l10n.download),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF307A59),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _openInExternalApp,
                icon: const Icon(Icons.open_in_browser),
                label: Text(l10n.openWithApp),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOfficeDocumentViewer() {
    final l10n = context.l10n;
    final extension = widget.file.fileName.split('.').last.toLowerCase();
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.description, size: 100, color: Colors.white),
          const SizedBox(height: 20),
          Text(
            l10n.officeDocumentKind(extension),
            style: const TextStyle(
              fontSize: 20,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.file.fileName,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              l10n.officeDocumentDescription,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 30),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _downloadFile,
                icon: const Icon(Icons.download,
                    color: Color.fromARGB(255, 255, 255, 255)),
                label: Text(
                  l10n.download,
                  style: TextStyle(color: Color(0xFFFFFFFF)),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2E9366),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _openInExternalApp,
                icon:
                    const Icon(Icons.open_in_browser, color: Color(0xFF307A59)),
                label: Text(l10n.openWithOffice,
                    style: const TextStyle(color: Color(0xFF307A59))),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEbookViewer() {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.menu_book, size: 100, color: Colors.orange),
          const SizedBox(height: 20),
          Text(
            l10n.ebook,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            widget.file.fileName,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _downloadFile,
                icon: const Icon(Icons.download),
                label: Text(l10n.download),
              ),
              ElevatedButton.icon(
                onPressed: _openInExternalApp,
                icon: const Icon(Icons.open_in_browser),
                label: Text(l10n.openWithApp),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildArchiveViewer() {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.archive, size: 100, color: Colors.purple),
          const SizedBox(height: 20),
          Text(
            l10n.compressedArchive,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            widget.file.fileName,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              l10n.archiveDescription,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: _downloadFile,
            icon: const Icon(Icons.download),
            label: Text(l10n.downloadArchive),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioViewer() {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.audio_file, size: 100, color: Colors.green),
          const SizedBox(height: 20),
          Text(
            l10n.audioFile,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            widget.file.fileName,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: _downloadFile,
            icon: const Icon(Icons.download),
            label: Text(l10n.download),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoViewer() {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.video_file, size: 100, color: Colors.red),
          const SizedBox(height: 20),
          Text(
            l10n.videoFile,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            widget.file.fileName,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: _downloadFile,
            icon: const Icon(Icons.download),
            label: Text(l10n.download),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnsupportedViewer(String extension) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.insert_drive_file, size: 100, color: Colors.grey),
          const SizedBox(height: 20),
          Text(
            l10n.unsupportedFormat(extension),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Text(
            widget.file.fileName,
            style: const TextStyle(fontSize: 16, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              l10n.unsupportedFileDescription,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: _downloadFile,
            icon: const Icon(Icons.download),
            label: Text(l10n.download),
          ),
        ],
      ),
    );
  }

  void _performSearch() {
    if (_pdfController != null && _searchText.isNotEmpty) {
      _pdfController!.searchText(_searchText);
    } else if (_pdfController != null && _searchText.isEmpty) {
      _pdfController!.clearSelection();
    }
  }

  void _zoomIn() {
    if (_pdfController != null) {
      setState(() {
        _pdfController!.zoomLevel += 0.1;
        _zoomLevel = _pdfController!.zoomLevel;
      });
    } else {
      setState(() => _zoomLevel += 0.1);
    }
  }

  void _zoomOut() {
    if (_pdfController != null) {
      if (_pdfController!.zoomLevel > 0.2) {
        setState(() {
          _pdfController!.zoomLevel -= 0.1;
          _zoomLevel = _pdfController!.zoomLevel;
        });
      }
    } else {
      if (_zoomLevel > 0.2) {
        setState(() => _zoomLevel -= 0.1);
      }
    }
  }

  void _resetZoom() {
    if (_pdfController != null) {
      setState(() {
        _pdfController!.zoomLevel = 1.0;
        _zoomLevel = 1.0;
      });
    } else {
      setState(() => _zoomLevel = 1.0);
    }
  }

  void _showSubscriptionRequired() {
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.archiveAccessSubscriptionRequired),
        backgroundColor: Colors.orange,
      ),
    );
  }

  @override
  void dispose() {
    _progressSaveDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _pdfController?.dispose();
    _currentPageNotifier.dispose();
    _totalPagesNotifier.dispose();
    _progressNotifier.dispose();
    _pdfLoadingNotifier.dispose();
    _dio.close();
    super.dispose();
  }

  Widget _buildLockedBody() {
    final l10n = context.l10n;
    final isApplePlatform = AppConfig.isApplePlatform;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.lock,
              size: 72,
              color: Color(0xFFE58F00),
            ),
            const SizedBox(height: 16),
            Text(
              isApplePlatform ? l10n.accessRequired : l10n.premiumArchive,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              isApplePlatform
                  ? l10n.previousYearArchiveAccessDescription
                  : l10n.premiumArchiveDescription,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ProfileScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.workspace_premium),
              label: Text(
                isApplePlatform ? l10n.checkAccess : l10n.subscribe,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E9366),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final extension = widget.file.fileName.split('.').last.toLowerCase();
    final isPdf = extension == 'pdf';
    final isText = _textExtensions.contains(extension);

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      appBar: AppBar(
        title: SizedBox(
          width: MediaQuery.of(context).size.width * 0.7,
          child: Text(
            widget.file.name,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: [
          if (!_isLocked && (isPdf || isText))
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _showSearchBar = !_showSearchBar),
            ),
          if (!_isLocked)
            PopupMenuButton<String>(
              itemBuilder: (context) => [
                if (isPdf || isText) ...[
                  PopupMenuItem(
                    value: 'zoom_in',
                    child: Row(
                      children: [
                        const Icon(Icons.zoom_in,
                            size: 20, color: Colors.black),
                        const SizedBox(width: 8),
                        Text(l10n.zoomIn),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'zoom_out',
                    child: Row(
                      children: [
                        const Icon(Icons.zoom_out,
                            size: 20, color: Colors.black),
                        const SizedBox(width: 8),
                        Text(l10n.zoomOut),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'zoom_reset',
                    child: Row(
                      children: [
                        const Icon(Icons.refresh,
                            size: 20, color: Colors.black),
                        const SizedBox(width: 8),
                        Text(l10n.resetZoom),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                ],
                PopupMenuItem(
                  value: 'copy_link',
                  child: Row(
                    children: [
                      const Icon(Icons.link, size: 20, color: Colors.black),
                      const SizedBox(width: 8),
                      Text(l10n.copyLink),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                switch (value) {
                  case 'zoom_in':
                    _zoomIn();
                    break;
                  case 'zoom_out':
                    _zoomOut();
                    break;
                  case 'zoom_reset':
                    _resetZoom();
                    break;
                  case 'copy_link':
                    _copyFileLink();
                    break;
                }
              },
            ),
        ],
      ),
      body: _isLocked
          ? _buildLockedBody()
          : Column(
              children: [
                if (_showSearchBar && (isPdf || isText))
                  Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(1.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                decoration: InputDecoration(
                                  hintText: l10n.searchInDocument,
                                  border: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(horizontal: 8),
                                ),
                                onChanged: (value) =>
                                    _handleSearchChanged(value, isPdf: isPdf),
                              ),
                            ),
                            if (_searchText.isNotEmpty)
                              IconButton(
                                icon: const Icon(Icons.clear, size: 20),
                                onPressed: () {
                                  _searchDebounce?.cancel();
                                  _searchController.clear();
                                  setState(() => _searchText = '');
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () => setState(() {
                                _searchDebounce?.cancel();
                                _showSearchBar = false;
                                _searchText = '';
                                _searchController.clear();
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_isDownloading)
                  LinearProgressIndicator(
                    value: _downloadProgress,
                    backgroundColor: Colors.grey[200],
                    color: const Color(0xFF307A59),
                  ),
                Expanded(child: _buildViewer()),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    border: Border(top: BorderSide(color: Colors.grey[300]!)),
                  ),
                  child: Column(
                    children: [
                      if (_isLoadingProgress)
                        const LinearProgressIndicator()
                      else
                        ValueListenableBuilder<double>(
                          valueListenable: _progressNotifier,
                          builder: (context, progress, child) =>
                              LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey[200],
                            color: const Color(0xFF307A59),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ValueListenableBuilder<double>(
                            valueListenable: _progressNotifier,
                            builder: (context, progress, child) => Text(
                              l10n.progressPercent(
                                  (progress * 100).toStringAsFixed(0)),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          if (isPdf)
                            ValueListenableBuilder<int>(
                              valueListenable: _currentPageNotifier,
                              builder: (context, currentPage, child) =>
                                  ValueListenableBuilder<int>(
                                valueListenable: _totalPagesNotifier,
                                builder: (context, totalPages, child) => Text(
                                  l10n.pageCount(currentPage, totalPages),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
