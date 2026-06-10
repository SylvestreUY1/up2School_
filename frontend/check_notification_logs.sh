#!/bin/bash
# Script de vérification des logs de notifications

echo "🔍 Recherche des logs de notifications..."
echo ""

# Logs récents Flutter depuis le dernier lancement
flutter_log="$(find ~/.config/Code/User/workspaceStorage -name "*debug.log" -type f -mmin -15 | head -1)"

if [ -z "$flutter_log" ]; then
  flutter_log="$(find ~/.config/Code/User/workspaceStorage -name "*debug.log" -type f | head -1)"
fi

if [ -f "$flutter_log" ]; then
  echo "📂 Fichier log trouvé: $flutter_log"
  echo ""
  
  echo "🔹 SUBSCRIPTIONS AUX TOPICS FCM:"
  grep -i "\[DEBUG\] Abonnement" "$flutter_log" | tail -5
  
  echo ""
  echo "🔹 INITIALISATION DES RAPPELS:"
  grep -i "\[SCHEDULER\]" "$flutter_log" | head -5
  
  echo ""
  echo "🔹 RAPPELS PROGRAMMÉS:"
  grep -i "\[REMINDER\]" "$flutter_log" | head -10
  
  echo ""
  echo "🔹 NOTIFICATIONS BACKGROUND FCM:"
  grep -i "\[BACKGROUND\]" "$flutter_log" | tail -5
  
  echo ""
  echo "✅ Fin du rapport"
else
  echo "❌ Aucun fichier log trouvé"
  echo "Assurez-vous que l'app a été lancée avec: flutter run -d linux"
fi
