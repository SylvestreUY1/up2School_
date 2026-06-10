/**
 * FICHIER : event_card.dart
 * RÔLE : C'est le composant graphique (Widget) qui affiche un événement dans le calendrier.
 * Il montre le titre de l'examen ou de la conférence, le lieu, l'heure 
 * et même des photos si elles sont disponibles.
 */
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/event.dart';

class EventCard extends StatelessWidget {
  final Event event; // L'événement à afficher
  final bool isPastEvent; // Est-ce que c'est déjà passé ?
  final VoidCallback onDelete; // Action pour supprimer (admin)
  final bool canDelete; // Est-ce que l'utilisateur a le droit de supprimer ?

  const EventCard({
    super.key,
    required this.event,
    this.isPastEvent = false,
    required this.onDelete,
    required this.canDelete,
  });

  /**
   * COULEUR : On change la couleur de la carte selon l'urgence
   */
  Color _getEventColor(DateTime date) {
    final now = DateTime.now();
    if (date.isBefore(now)) return const Color(0xFFE0E0E0); // Gris si passé
    final difference = date.difference(now).inDays;
    if (difference < 7)
      return const Color(
          0xFFFFF3E0); // Orange clair si c'est bientôt (moins de 7 jours)
    return const Color(0xFFE3F2FD); // Bleu si on a encore le temps
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: _getEventColor(event.date),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Titre et Badge "Global"
            Row(
              children: [
                const Icon(Icons.event),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    event.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                if (event.isGlobal) // Si c'est pour toute l'école
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'GLOBAL',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (canDelete)
                  IconButton(
                    tooltip: l10n.delete,
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: onDelete,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // 2. Photos (s'il y en a)
            if (event.imageUrls.isNotEmpty)
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: event.imageUrls.length,
                  itemBuilder: (context, index) =>
                      Image.network(event.imageUrls[index]),
                ),
              ),

            // 3. Infos (Date et Lieu)
            Row(
              children: [
                const Icon(Icons.access_time, size: 16),
                const SizedBox(width: 4),
                Text(DateFormat('dd/MM/yyyy HH:mm').format(event.date)),
                const Spacer(),
                const Icon(Icons.location_on, size: 16),
                const SizedBox(width: 4),
                Text(event.location),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
