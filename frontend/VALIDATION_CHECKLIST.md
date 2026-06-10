#  Checklist de Validation des Corrections

## Phase 1: Compilation & Démarrage

- [ ] **Compilation sans erreur**
  ```bash
  flutter clean && flutter pub get
  ```
- [ ] **Lancement réussi**

  ```bash
  flutter run -d linux  # ou ios/android device
  ```

- [ ] **Aucun crash au démarrage**
  - Vérifier la console pour les crashs

---

## Phase 2: Après Authentification

### À l'écran de connexion

- [ ] Connexion utilisateur réussie
- [ ] **Logs attendus dans la console**:
  ```
  [DEBUG] Abonnement aux topics pour user@email.com
  [DEBUG] Abonnement au topic: faculte_XXX_niveau_YYY_filiere_ZZZ
  [DEBUG]  Abonné au topic: faculte_XXX_niveau_YYY_filiere_ZZZ
  ```

### Si vous êtes sur Desktop

- [ ] Le log indique "Desktop platform: FCM non supporté" (c'est normal)
- [ ] Les notifications viendront via polling/websocket du backend

---

## Phase 3: Initialisation des Rappels

### Au premier démarrage après login

- [ ] **Logs attendus dans la console**:

  ```
  [SCHEDULER] Initialisation des rappels...
  [SCHEDULER]  Initialisation complétée: X rappels programmés, Y ignorés
  ```

- [ ] Remplacer `X` par le nombre d'événements × 2 (48h + 12h)
- [ ] Remplacer `Y` par les événements ignorés (passés ou sans date)

### Si la liste est vide

- [ ] Cherchez: `[SCHEDULER] Aucun événement trouvé.`
  - C'est normal si vous n'avez pas d'événements
  - Accédez à la section événements pour en créer

---

## Phase 4: Créer/Modifier un Événement

### Actions

1. Créez un nouvel événement (ou modifiez un existant)
2. Avec une date dans le futur (minimum 48h)
3. Avec votre faculté/niveau/filière sélectionnés

### Résultat attendu

- [ ] **Logs dans la console**:

  ```
  [REMINDER] Programmation rappel: Nom de l'événement, dans 48 heures
  [REMINDER] Date event: 2026-04-20, Date rappel: 2026-04-18, Maintenant: 2026-04-16
  [REMINDER]  Rappel programmé: Nom de l'événement pour 2026-04-18 08:00:00.000
  ```

- [ ] Les deux rappels apparaissent (48h et 12h)

---

## Phase 5: Tester les Notifications FCM

### Via Firebase Console (Mobile uniquement)

1. Allez dans Firebase > Cloud Messaging > Nouveau message
2. Titre: "Test Notification"
3. Body: "Ceci est un test"
4. **Cibler le topic**: `faculte_[Votre_Fac]_niveau_[Votre_Niveau]_filiere_[Votre_Filiere]`
5. Envoyez

### Résultat attendu

- [ ] La notification apparaît sur l'app
- [ ] **Logs attendus**:
  ```
  [BACKGROUND] Message FCM reçu: msg_123456
  [BACKGROUND] Data: {type: event, ...}
  [BACKGROUND]  Notification affichée en arrière-plan
  ```

---

## Phase 6: Tester les Notifications Locales (Rappels)

### Sur Device Réel

1. Créez un événement pour demain
2. Fermez l'app
3. Attendez le moment du rappel (ou avancez l'heure système)
4. La notification doit apparaître même avec l'app fermée

### Sur Émulateur

- Les notifications locales peuvent ne pas s'afficher correctement
- Testez sur device réel si possible

### Résultat attendu

- [ ] Notification apparaît au moment prévu
- [ ] Texte: "Rappel : [Event Title]"
- [ ] L'événement arrive sous peu

---

## Phase 7: Validation Complète

### Cherchez les logs clés

```bash
./check_notification_logs.sh
```

Attendu:

```
 SUBSCRIPTIONS AUX TOPICS FCM:
[DEBUG]  Abonné au topic: facaute_XXX...

 INITIALISATION DES RAPPELS:
[SCHEDULER]  Initialisation complétée: 5 rappels...

 RAPPELS PROGRAMMÉS:
[REMINDER]  Rappel programmé: Event Title...

 NOTIFICATIONS BACKGROUND FCM:
[BACKGROUND]  Notification affichée...
```

---

##  Problèmes Possibles & Solutions

###  Aucun log de subscription FCM

**Causes possibles**:

- L'utilisateur n'est pas connecté
- Les permissions de notification ne sont pas activées
- Vous êtes sur Desktop (silencieusement ignoré)

**Solutions**:

1. Vérifiez que vous êtes connecté
2. Allez dans Paramètres > Notifications et activez
3. Relancez l'app

---

###  `[SCHEDULER] Aucun événement trouvé`

**Causes possibles**:

- Base de données d'événements vide
- Premier lancement de l'app

**Solutions**:

1. Accédez à la section Événements
2. Créez au moins un événement avec date future

---

###  `[SCHEDULER] Topic invalide pour événement, abandon`

**Causes possibles**:

- Les topics générés ne correspondent pas
- Faculté/Niveau/Filière vides

**Solutions**:

1. Vérifiez que faculty/level/field sont remplis
2. Vérifiez la correspondance entre `functions/index.js` et `auth_service.dart`
3. Logs: cherchez `getTopicForEvent()`

---

###  Rappels ne s'affichent pas aux moments prévus

**Causes possibles**:

- App fermée sans persistence des rappels
- Permissions manquantes
- Émulateur iOS (ne supporte pas tous les cas)

**Solutions**:

1. Testez sur device réel
2. Vérifiez les permissions en Paramètres > Notifications
3. Relancez l'app pour reprogrammer les rappels

---

###  `[REMINDER]  Erreur programmation:`

**Causes possibles**:

- Plugin `flutter_local_notifications` mal initialisé
- DateTimeZone mal configurée

**Solutions**:

1. Vérifiez les logs complets de l'erreur
2. Relancez l'app
3. Essayez sur un device différent

---

##  Support Additionnel

### Logs à inclure dans les rapports de bug

Exécutez ceci et partagez:

```bash
./check_notification_logs.sh > notification_logs.txt
cat notification_logs.txt | head -100
```

Cherchez aussi:

- Les derniers logs avec `[SCHEDULER]`
- Les derniers logs avec `[REMINDER]`
- Les derniers logs avec `[DEBUG]`

### Information système utile

- Platform: (Android/iOS/Linux/Windows)
- Device: (réel ou émulateur)
- Votre faculté/niveau/filière
- Date des événements créés

---

##  Félicitations!

Si tous les checkpoints passent, vos notifications FCM et rappels locaux fonctionnent correctement! 
