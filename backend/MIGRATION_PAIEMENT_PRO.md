# Migration CinetPay → PaiementPro

## Résumé des changements

Ce document décrit la migration du système de paiement de **CinetPay** à **PaiementPro**.

###  Ce qui a été modifié

#### Backend (`functions/server.js`)

1. **Configuration**: Remplacé `getCinetPayConfig()` par `getPaiementProConfig()`
   - Ancien: `CINETPAY_API_KEY`, `CINETPAY_SITE_ID`, `CINETPAY_SECRET_KEY`
   - Nouveau: `PAIEMENT_PRO_MERCHANT_ID` (obligatoire)

2. **API d'initialisation de paiement** (`/api/subscriptions/checkout`)
   - Changement du payload envoyé à PaiementPro
   - Nouvelle URL: `https://paiementpro.net/webservice/onlinepayment/init/curl-init.php`
   - Ancien provider: `cinetpay` → Nouveau: `paiement_pro`

3. **Webhooks**
   - Les webhooks CinetPay ne sont plus vérifiés
   - Les routes `/api/payments/paiement-pro/webhook` ajoutées pour PaiementPro
   - Les anciennes routes `/api/payments/cinetpay/webhook` conservées pour rétrocompatibilité

4. **Retour de paiement** (`handlePaiementProReturn`)
   - Nouvelle fonction remplaçant `handleCinetPayReturn`
   - Valide le paiement automatiquement quand l'utilisateur revient
   - Routes: `/api/payments/paiement-pro/return` et `/api/payments/cinetpay/return`

5. **Vérification du paiement**
   - `applySubscriptionActivation()` adaptée pour PaiementPro
   - Supporte `verification: { success: true }` au lieu des réponses CinetPay complexes

#### Frontend (`lib/`)

1. **Nouveau service** (`services/paiement_pro_service.dart`)
   - Classe `PaiementProService` pour gérer les paiements
   - API similaire mais pour PaiementPro
   - Peut être intégré si une initialisation côté client est nécessaire

2. **Pas de changement** pour:
   - `backend_api_service.dart` (L'endpoint `/api/subscriptions/checkout` gère tout)
   - `profile_screen.dart` (Utilise l'API backend qui a été adaptée)

###  Configuration requise

#### Variables d'environnement (Backend)

Remplacer dans `functions/.env`:

```bash
# Ancien (à supprimer)
CINETPAY_API_KEY=xxx
CINETPAY_SITE_ID=xxx
CINETPAY_SECRET_KEY=xxx

# Nouveau (à ajouter)
PAIEMENT_PRO_MERCHANT_ID=your_merchant_id

# Garder (inchangé)
UP2SCHOOL_SUBSCRIPTION_AMOUNT=350
```

###  Flux de paiement

#### CinetPay (ancien)

```
Client → API /checkout → CinetPay API → URL paiement
Client → Paiement CinetPay
CinetPay → Webhook /api/payments/cinetpay/webhook
Backend → Vérifie via CinetPay API
Backend → Active l'abonnement
Client reviendra ← Page de retour
```

#### PaiementPro (nouveau)

```
Client → API /checkout → PaiementPro API → URL paiement
Client → Paiement PaiementPro → Retour vers returnURL
Backend → /api/payments/paiement-pro/return → Active l'abonnement
Client reste dans l'app ← Page de retour
```

###  Test

1. **Configurer** `PAIEMENT_PRO_MERCHANT_ID` dans les variables d'environnement
2. **Déployer** le backend (redéployer le repo functions sur Render)
3. **Tester** le flux de paiement:
   - Cliquer sur "Activer l'abonnement"
   - Être redirigé vers PaiementPro
   - Effectuer un paiement test
   - Revenir à l'application
   - L'abonnement doit être activé

###  Rétrocompatibilité

- Les anciennes routes CinetPay `/api/payments/cinetpay/*` sont conservées
- Elles pointent vers les nouvelles fonctions PaiementPro
- Les données de base de données restent les mêmes
- Le système lira et écrira le champ `provider` correctement (`paiement_pro`)

###  Notes importantes

1. **Champ `provider`** dans la table `payments`: Changé de `"cinetpay"` à `"paiement_pro"`
2. **Webhooks**: PaiementPro ne requiert pas de webhooks complexes comme CinetPay
3. **Vérification**: Simplifiée car la vérification se fait au retour de PaiementPro
4. **Statut de paiement**: Les anciens paiements CinetPay en attente garderont le status `cinetpay_status`, les nouveaux n'utiliseront pas ce champ

###  Intégration additionnelle (facultatif)

Si vous voulez utiliser `PaiementProService` côté client pour plus de contrôle:

```dart
import 'package:up2school/services/paiement_pro_service.dart';

final service = PaiementProService(merchantId: 'PP-F324');
service.configurePaiement(
  amount: 350,
  description: 'Abonnement Up2School',
  channel: 'WAVECI',
  referenceNumber: 'REF123',
  customerEmail: 'user@example.com',
  customerFirstName: 'Ato',
  customerLastname: 'Toto',
  customerPhoneNumber: '+237601020304',
  notificationURL: 'https://api.up2school.com/api/payments/paiement-pro/webhook',
  returnURL: 'https://api.up2school.com/api/payments/paiement-pro/return',
);

await service.initierPaiement();
if (service.success) {
  launchUrl(Uri.parse(service.paymentUrl!));
}
```

Cependant, le backend gère actuellement tout cela, donc cette utilisation directe est **optionnelle**.

###  Prochaines étapes

1. Mettre à jour les variables d'environnement sur Render
2. Redéployer le backend
3. Tester le flux end-to-end
4. Monitorer les logs de paiement
5. Documenter tout problème rencontré
