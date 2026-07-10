/**
 * FICHIER : rotating_ad_banner.dart
 * RÔLE : C'est le carrousel de publicités de l'application.
 * Il affiche des bannières qui changent toutes les 10 secondes.
 * Très important : il n'affiche que les pubs qui concernent l'étudiant 
 * (par exemple, un étudiant en Droit ne verra pas les mêmes pubs qu'un étudiant en Sciences).
 */
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../screens/main/ad_banner.dart';
import '../models/ad_model.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../services/ad_service.dart';
import '../services/local_ad_storage.dart';
import '../utils/academic_targeting.dart';

class RotatingAdBanner extends StatefulWidget {
  const RotatingAdBanner({super.key});

  @override
  State<RotatingAdBanner> createState() => _RotatingAdBannerState();
}

class _RotatingAdBannerState extends State<RotatingAdBanner> {
  final AdService _adService = AdService();
  final LocalAdStorage _localStorage = LocalAdStorage();

  List<AdModel> _ads = []; // La liste des publicités à afficher
  int _currentIndex = 0; // L'index de la pub actuellement visible
  Timer? _timer; // Le chronomètre pour changer de pub
  StreamSubscription? _subscription;
  String?
      _currentAudienceKey; // Pour savoir si l'utilisateur a changé de profil académique

  @override
  void initState() {
    super.initState();
  }

  /**
   * MISE À JOUR DE L'AUDIENCE
   * Si l'utilisateur change sa faculté ou son niveau, on doit changer les pubs.
   */
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final user = context.watch<AuthProvider>().currentUser;
    final nextAudienceKey = AcademicTargeting.audienceKey(user);
    if (_currentAudienceKey == nextAudienceKey) {
      return; // Rien n'a changé, on garde les mêmes pubs
    }

    _currentAudienceKey = nextAudienceKey;
    unawaited(_loadAds(user)); // On recharge les pubs adaptées
  }

  /**
   * CHARGEMENT DES PUBS
   * On essaie d'abord de les prendre dans la mémoire du téléphone (pour que ça aille vite),
   * puis on demande au serveur s'il y en a des nouvelles.
   */
  Future<void> _loadAds(UserModel? user) async {
    await _subscription?.cancel();
    _subscription = null;

    // 1. On regarde dans le placard (cache local)
    try {
      final cachedAds = await _localStorage.getActiveAds(user: user);
      if (cachedAds.isNotEmpty && mounted) {
        setState(() {
          _ads = cachedAds;
          _currentIndex = 0;
        });
        _startRotation();
      } else {
        await _fetchAndCacheFromBackend(user);
      }
    } catch (e) {
      await _fetchAndCacheFromBackend(user);
    }

    // 2. On écoute le serveur en direct pour mettre à jour si besoin
    _subscription =
        _adService.getActiveAds(user: user).listen((freshAds) async {
      if (!mounted) return;
      // On met à jour notre placard local
      for (final ad in freshAds) {
        await _localStorage.insertAd(ad, user: user);
      }
      final updatedAds = await _localStorage.getActiveAds(user: user);
      if (mounted) {
        setState(() {
          _ads = updatedAds;
          _currentIndex = 0;
        });
        _startRotation();
      }
    });
  }

  Future<void> _fetchAndCacheFromBackend(UserModel? user) async {
    try {
      final ads = await _adService.fetchAndCacheActiveAds(user: user);
      if (ads.isNotEmpty && mounted) {
        setState(() {
          _ads = ads;
          _currentIndex = 0;
        });
        _startRotation();
      }
    } catch (e) {
      print('Erreur publicités: $e');
    }
  }

  /**
   * LA ROTATION AUTOMATIQUE
   * On lance un compte à rebours de 10 secondes. À chaque fin de décompte,
   * on passe à la publicité suivante.
   */
  void _startRotation() {
    _timer?.cancel();
    if (_ads.length <= 1)
      return; // Pas besoin de tourner s'il n'y a qu'une seule pub
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % _ads.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  /**
   * CALCUL DE LA HAUTEUR - VERSION HYBRIDE
   * - Mobile (< 600 dp) : conserve l'ancienne logique (24% de la largeur)
   * - Tablette (600-1024 dp) : utilise le ratio 6.4:1 pour un rendu parfait
   * - Desktop (>= 1024 dp) : utilise le ratio 6.4:1 pour un rendu parfait
   */
  double _bannerHeightForWidth(double width) {
    const double tabletBreakpoint = 600.0;
    const double desktopBreakpoint = 1024.0;
    const double aspectRatio = 6.4; // Ratio standard 320x50
    const double horizontalMargins = 24.0; // 12px de chaque côté (AdBanner)

    // MOBILE : on conserve l'ancienne logique qui fonctionnait bien
    if (width < tabletBreakpoint) {
      return (width * 0.24).clamp(88.0, 128.0);
    }

    // TABLETTE ET DESKTOP : on utilise le ratio pour respecter les proportions
    final double availableWidth = width - horizontalMargins;
    double height = availableWidth / aspectRatio;

    // Clampage adapté aux grands écrans
    return height.clamp(104.0, 200.0);
  }

  @override
  Widget build(BuildContext context) {
    if (_ads.isEmpty)
      return const SizedBox
          .shrink(); // Si pas de pub, on n'affiche rien du tout

    return LayoutBuilder(
      builder: (context, constraints) {
        final fallbackWidth = MediaQuery.of(context).size.width;
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackWidth;

        return SizedBox(
          width: double.infinity,
          height: _bannerHeightForWidth(width),
          child: AnimatedSwitcher(
            duration: const Duration(
                milliseconds: 500), // Petit effet de fondu lors du changement
            child: AdBanner(
              key: ValueKey(_ads[_currentIndex].imageUrl),
              ad: _ads[_currentIndex],
            ),
          ),
        );
      },
    );
  }
}