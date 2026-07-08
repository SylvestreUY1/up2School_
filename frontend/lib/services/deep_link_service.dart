import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../main.dart';
import '../models/file.dart';
import '../screens/files/file_viewer_screen.dart';
import '../screens/files/files_list_screen.dart';
import 'api_service.dart';

class DeepLinkService {
  factory DeepLinkService() => _instance;

  DeepLinkService._internal();

  static final DeepLinkService _instance = DeepLinkService._internal();

  final AppLinks _appLinks = AppLinks();
  final ApiService _apiService = ApiService();

  StreamSubscription<Uri>? _subscription;
  bool _initialized = false;
  final Set<String> _linksBeingHandled = {};

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final initialUri = await _appLinks.getInitialLink().timeout(
            const Duration(seconds: 2),
            onTimeout: () => null,
          );
      if (initialUri != null) {
        unawaited(_handleUri(initialUri));
      }
    } catch (error) {
      debugPrint('Lien initial indisponible: $error');
    }

    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => unawaited(_handleUri(uri)),
      onError: (error) => debugPrint('Erreur lien entrant: $error'),
    );
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _initialized = false;
    _linksBeingHandled.clear();
  }

  Future<void> _handleUri(Uri uri) async {
    final fileId = _extractSharedFileId(uri);
    if (fileId == null || fileId.isEmpty) return;

    final normalizedLink = '${uri.scheme}:$fileId';
    if (!_linksBeingHandled.add(normalizedLink)) return;

    try {
      await _waitForNavigator();

      final FileModel? file = await _apiService.getFileById(fileId);
      if (file == null) {
        _showFileNotFound();
        return;
      }

      final navigator = MyApp.navigatorKey.currentState;
      if (navigator == null) return;

      navigator.push(
        MaterialPageRoute(
          builder: (_) => FilesListScreen(
            faculty: file.faculty,
            level: file.level,
            field: file.field,
            unit: file.unit,
            type: file.type,
          ),
        ),
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        MyApp.navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => FileViewerScreen(file: file)),
        );
      });
    } finally {
      unawaited(
        Future<void>.delayed(const Duration(seconds: 2), () {
          _linksBeingHandled.remove(normalizedLink);
        }),
      );
    }
  }

  String? _extractSharedFileId(Uri uri) {
    if (uri.scheme == 'uy1' && uri.host == 'partage') {
      if (uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.first;
      }
      return uri.queryParameters['fileId'] ?? uri.queryParameters['id'];
    }

    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == 'uy1-lib.netlify.app' &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'partage') {
      if (uri.pathSegments.length > 1) {
        return uri.pathSegments[1];
      }
      return uri.queryParameters['fileId'] ?? uri.queryParameters['id'];
    }

    return null;
  }

  Future<void> _waitForNavigator() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      if (MyApp.navigatorKey.currentState != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  void _showFileNotFound() {
    final context = MyApp.navigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.fileNotFound),
        backgroundColor: Colors.red,
      ),
    );
  }
}
