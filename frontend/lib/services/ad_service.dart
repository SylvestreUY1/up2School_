import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:dio/dio.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/ad_model.dart';
import '../config/app_config.dart';
import '../models/user.dart';
import '../utils/academic_targeting.dart';
import 'backend_api_service.dart';
import '../services/local_ad_storage.dart'; // à créer

class AdService {
  static const int _maxAdImageDimension = 1600;
  static const int _targetUploadSizeBytes = 1600 * 1024;
  static const int _maxSourceImageSizeBytes = 18 * 1024 * 1024;

  final FirebaseFirestore? _firestore =
      AppConfig.useFirebaseAds ? FirebaseFirestore.instance : null;
  final FirebaseStorage? _storage =
      AppConfig.useFirebaseAds ? FirebaseStorage.instance : null;
  final BackendApiService _backendApi = BackendApiService();

  bool get _useFirebaseAds => AppConfig.useFirebaseAds;

  bool _isAdCurrentlyActive(AdModel ad, [DateTime? reference]) {
    final now = reference ?? DateTime.now();
    final startsBeforeNow = ad.startDate == null || !ad.startDate!.isAfter(now);
    final endsAfterNow = ad.endDate == null || !ad.endDate!.isBefore(now);
    return ad.isActive && startsBeforeNow && endsAfterNow;
  }

  Future<List<AdModel>> _cacheAndFilterAds(
    List<AdModel> ads, {
    UserModel? user,
  }) async {
    final activeAds = ads
        .where(_isAdCurrentlyActive)
        .where(
          (ad) => AcademicTargeting.matchesUser(
            isGlobal: ad.isGlobal,
            faculty: ad.faculty,
            level: ad.level,
            field: ad.field,
            user: user,
          ),
        )
        .toList();

    for (final ad in activeAds) {
      await LocalAdStorage().insertAd(ad, user: user);
    }
    await LocalAdStorage().deleteExpiredAds(
      audienceKey: AcademicTargeting.audienceKey(user),
    );
    return activeAds;
  }

  Future<void> _deleteExpiredFirebaseAds() async {
    if (!_useFirebaseAds) return;

    try {
      final snapshot = await _firestore!
          .collection('ads')
          .where('endDate', isLessThan: DateTime.now())
          .get();

      for (final doc in snapshot.docs) {
        await doc.reference.delete();
        await LocalAdStorage().deleteAd(doc.id);
      }
    } catch (_) {
      // Best effort: expiry cleanup should not block ad loading.
    }
  }

  Future<List<AdModel>> _fetchActiveAdsWithCacheFallback(
      {UserModel? user}) async {
    if (_useFirebaseAds) {
      await _deleteExpiredFirebaseAds();
      final snapshot = await _firestore!
          .collection('ads')
          .where('isActive', isEqualTo: true)
          .get();
      final ads = snapshot.docs
          .map((doc) => AdModel.fromMap(doc.id, doc.data()))
          .toList();
      return _cacheAndFilterAds(ads, user: user);
    }

    try {
      final freshAds = await _backendApi.getActiveAds();
      return _cacheAndFilterAds(freshAds, user: user);
    } catch (_) {
      await LocalAdStorage().deleteExpiredAds(
        audienceKey: AcademicTargeting.audienceKey(user),
      );
      return LocalAdStorage().getActiveAds(user: user);
    }
  }

  Future<File> optimizeImageForAd(File imageFile) async {
    final sourceSize = await imageFile.length();
    if (sourceSize > _maxSourceImageSizeBytes) {
      throw Exception(
        'Image trop lourde. Choisissez une image de moins de 18 Mo.',
      );
    }

    final originalBytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) {
      throw Exception(
        'Format d\'image non pris en charge. Utilisez JPG, PNG ou WEBP.',
      );
    }

    img.Image processed = decoded;
    if (processed.width > _maxAdImageDimension ||
        processed.height > _maxAdImageDimension) {
      if (processed.width >= processed.height) {
        processed = img.copyResize(
          processed,
          width: _maxAdImageDimension,
          interpolation: img.Interpolation.linear,
        );
      } else {
        processed = img.copyResize(
          processed,
          height: _maxAdImageDimension,
          interpolation: img.Interpolation.linear,
        );
      }
    }

    Uint8List encoded = Uint8List.fromList(
      img.encodeJpg(processed, quality: 82),
    );

    if (encoded.length > _targetUploadSizeBytes) {
      for (final quality in [76, 70, 64, 58]) {
        encoded =
            Uint8List.fromList(img.encodeJpg(processed, quality: quality));
        if (encoded.length <= _targetUploadSizeBytes) {
          break;
        }
      }
    }

    if (encoded.length > _targetUploadSizeBytes) {
      final resizedWidth =
          (processed.width * 0.8).round().clamp(320, processed.width);
      final resizedHeight =
          (processed.height * 0.8).round().clamp(320, processed.height);
      processed = img.copyResize(
        processed,
        width: resizedWidth,
        height: resizedHeight,
        interpolation: img.Interpolation.linear,
      );
      encoded = Uint8List.fromList(img.encodeJpg(processed, quality: 60));
    }

    final tempDir = await getTemporaryDirectory();
    final adsDir = Directory(p.join(tempDir.path, 'ads'));
    if (!await adsDir.exists()) {
      await adsDir.create(recursive: true);
    }

    final optimizedPath = p.join(
      adsDir.path,
      'ad_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    final optimizedFile = File(optimizedPath);
    await optimizedFile.writeAsBytes(encoded, flush: true);
    return optimizedFile;
  }

  // Upload image vers Firebase Storage
  Future<String> uploadImage(File imageFile) async {
    if (_useFirebaseAds) {
      final fileName = DateTime.now().millisecondsSinceEpoch.toString();
      final ref = _storage!.ref().child('ads/$fileName.jpg');
      await ref.putFile(imageFile);
      return await ref.getDownloadURL();
    }

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.uri.pathSegments.last,
      ),
    });
    return _backendApi.uploadAdImage(formData);
  }

  // Création pub dans Firestore
  Future<void> createAd(AdModel ad, String adminUid) async {
    final effectiveStartDate = ad.startDate ?? DateTime.now();
    final effectiveEndDate =
        ad.endDate ?? DateTime.now().add(const Duration(days: 7));
    final normalizedAd = AdModel(
      id: ad.id,
      title: ad.title,
      description: ad.description,
      imageUrl: ad.imageUrl,
      targetUrl: ad.targetUrl,
      faculty: ad.faculty,
      level: ad.level,
      field: ad.field,
      isGlobal: ad.isGlobal,
      isActive: ad.isActive,
      clicks: ad.clicks,
      startDate: effectiveStartDate,
      endDate: effectiveEndDate,
      createdAt: ad.createdAt ?? DateTime.now(),
    );

    if (_useFirebaseAds) {
      final docRef = await _firestore!.collection('ads').add({
        ...normalizedAd.toMap(),
        'startDate': effectiveStartDate,
        'endDate': effectiveEndDate,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': adminUid,
      });
      await LocalAdStorage().insertAd(
        AdModel(
          id: docRef.id,
          title: ad.title,
          description: ad.description,
          imageUrl: ad.imageUrl,
          targetUrl: ad.targetUrl,
          faculty: ad.faculty,
          level: ad.level,
          field: ad.field,
          isGlobal: ad.isGlobal,
          isActive: ad.isActive,
          clicks: ad.clicks,
          startDate: effectiveStartDate,
          endDate: effectiveEndDate,
          createdAt: DateTime.now(),
        ),
      );
      await LocalAdStorage().deleteExpiredAds();
      return;
    }

    final createdAd = await _backendApi.createAd(normalizedAd, adminUid);
    if (_isAdCurrentlyActive(createdAd)) {
      await LocalAdStorage().insertAd(createdAd);
    }
    await LocalAdStorage().deleteExpiredAds();
  }

  // Récupération des pubs actives (stream) avec cache local
  Stream<List<AdModel>> getActiveAds({UserModel? user}) {
    if (_useFirebaseAds) {
      return _firestore!
          .collection('ads')
          .where('isActive', isEqualTo: true)
          .snapshots()
          .asyncMap((snapshot) async {
        await _deleteExpiredFirebaseAds();
        final ads = snapshot.docs
            .map((doc) => AdModel.fromMap(doc.id, doc.data()))
            .toList();
        return _cacheAndFilterAds(ads, user: user);
      });
    }

    return Stream.periodic(
      const Duration(seconds: 30),
      (_) => _fetchActiveAdsWithCacheFallback(user: user),
    )
        .asyncMap((future) => future)
        .startWith(_fetchActiveAdsWithCacheFallback(user: user));
  }

  // Récupère TOUTES les publicités (pour l'admin)
  Future<List<AdModel>> getAllAds() async {
    if (_useFirebaseAds) {
      await _deleteExpiredFirebaseAds();
      final snapshot = await _firestore!
          .collection('ads')
          .orderBy('createdAt', descending: true)
          .get();
      return snapshot.docs
          .map((doc) => AdModel.fromMap(doc.id, doc.data()))
          .toList();
    }

    return _backendApi.getAllAds();
  }

  // Supprime une publicité (admin seulement)
  Future<void> deleteAd(String adId) async {
    if (_useFirebaseAds) {
      await _firestore!.collection('ads').doc(adId).delete();
      await LocalAdStorage().deleteAd(adId);
      return;
    }

    await _backendApi.deleteAd(adId);
    await LocalAdStorage().deleteAd(adId);
  }

  // Track click
  Future<void> incrementClick(String adId) async {
    if (_useFirebaseAds) {
      await _firestore!.collection('ads').doc(adId).update({
        'clicks': FieldValue.increment(1),
      });
      return;
    }

    await _backendApi.incrementAdClick(adId);
  }

  // Récupération ponctuelle (pour le cache initial)
  Future<List<AdModel>> fetchAndCacheActiveAds({UserModel? user}) async {
    return _fetchActiveAdsWithCacheFallback(user: user);
  }
}

extension<T> on Stream<T> {
  Stream<T> startWith(Future<T> firstValue) async* {
    yield await firstValue;
    yield* this;
  }
}
