import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/constants.dart';

/**
 * FICHIER : loading_screen.dart
 * RÔLE : Affiche des indicateurs de chargement (roues qui tournent).
 * Utilisé pour faire patienter l'utilisateur pendant que l'app récupère des données.
 */

/**
 * UN ÉCRAN COMPLET DE CHARGEMENT
 * On l'utilise quand on change de page et que la nouvelle page n'est pas encore prête.
 */
class LoadingScreen extends StatelessWidget {
  final String? message; // Message facultatif à afficher (ex: "Connexion en cours...")

  const LoadingScreen({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // La petite roue qui tourne
            const CircularProgressIndicator(
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppConstants.primaryColor),
              strokeWidth: 2.0,
            ),
            const SizedBox(height: 20),
            // Le texte en dessous
            Text(
              message ?? l10n.loading,
              style: const TextStyle(
                fontSize: 16,
                color: AppConstants.greyColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/**
 * UNE COUCHE DE CHARGEMENT (OVERLAY)
 * Se place par-dessus une page existante pour bloquer les clics pendant un chargement.
 * Pratique pour éviter que l'utilisateur clique deux fois sur un bouton d'envoi.
 */
class LoadingOverlay extends StatelessWidget {
  final bool isLoading; // Est-ce qu'on doit afficher le chargement ?
  final Widget child;   // Le contenu de la page en dessous

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child, // On affiche d'abord la page
        if (isLoading)
          // Puis on rajoute un voile noir transparent par-dessus
          Container(
            color: Colors.black.withOpacity(0.5),
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

/**
 * EFFET DE SQUELETTE (SHIMMER)
 * Affiche des rectangles gris pour simuler la forme du contenu avant qu'il n'arrive.
 * C'est ce qu'on voit souvent sur Facebook ou YouTube avant que les images ne chargent.
 */
class ShimmerLoading extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const ShimmerLoading({
    super.key,
    this.width = double.infinity,
    this.height = 20,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: borderRadius,
      ),
    );
  }
}
