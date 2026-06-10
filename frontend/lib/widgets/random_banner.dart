/**
 * FICHIER : random_banner.dart
 * RÔLE : Une petite bannière d'information qui change de message à chaque fois qu'on clique dessus.
 * Elle sert à donner des conseils ou des infos importantes aux étudiants de manière discrète.
 */
import 'dart:math';
import 'package:flutter/material.dart';
import '../utils/constants.dart';

class RandomBanner extends StatefulWidget {
  final bool showLogo; // Est-ce qu'on affiche le petit logo "U2S" à droite ?

  const RandomBanner({
    super.key,
    this.showLogo = true,
  });

  @override
  State<RandomBanner> createState() => _RandomBannerState();
}

class _RandomBannerState extends State<RandomBanner> {
  late String _currentMessage; // Le message actuellement affiché

  @override
  void initState() {
    super.initState();
    _currentMessage = _getRandomMessage(); // On choisit un message au hasard dès le début
  }

  /**
   * LA PIOCHE AU HASARD
   * Cette fonction choisit un message dans une liste d'infos utiles.
   */
  String _getRandomMessage() {
    final messages = [
      'Restez connecté pour ne rien manquer.',
      'Les publicités aident à financer la mission de votre librairie.',
      'Trouvez tous vos supports de cours au même endroit.',
      'Restez informé des événements de votre filière.',
      'Votre compte sera automatiquement supprimé après 45 jours d\'inactivité. Vous devrez alors le recréer.',
    ];

    final random = Random();
    return messages[random.nextInt(messages.length)]; // On prend un index au hasard
  }

  /**
   * CHANGER DE MESSAGE
   * Quand on clique sur la bannière, on relance la pioche pour changer de texte.
   */
  void _refreshMessage() {
    setState(() {
      _currentMessage = _getRandomMessage();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _refreshMessage, // Si on touche la bannière, on change le message
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 2), // Donne un petit effet d'ombre porté
            ),
          ],
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // PARTIE GAUCHE : L'icône d'info et le texte
            Expanded(
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppConstants.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Color(0xFF307A59),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _currentMessage, // C'est ici qu'on affiche le texte pioché
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // PARTIE DROITE : Le petit logo Up2School (si activé)
            if (widget.showLogo)
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  color: AppConstants.primaryColor.withOpacity(0.1),
                ),
                child: Center(
                  child: Text(
                    'U2S',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppConstants.primaryColor,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
