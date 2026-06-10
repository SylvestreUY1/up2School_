# Up2School — Plateforme Académique

Application de distribution de fichiers universitaires construite avec **Flutter + Node.js/Express + Supabase + Firebase**.

---

## Architecture

```
up2school/
 backend/
    functions/         # API Node.js/Express
    supabase/          # Schémas SQL et base de données
    render.yaml        # Configuration de déploiement Render
 frontend/
     lib/               # Code source de l'application Flutter
     android/           # Configuration Android
     ios/               # Configuration iOS
     linux/             # Configuration Linux
     macos/             # Configuration macOS
     windows/           # Configuration Windows
```

---

## Démarrage rapide

### 1. Installer les dépendances

**Backend :**
```bash
cd backend/functions
npm install
```

**Frontend :**
```bash
cd frontend
flutter pub get
```

### 2. Compiler et lancer

**Backend (API locale) :**
```bash
cd backend/functions
npm start
```

**Frontend :**
```bash
cd frontend
flutter run
```

---

## Fonctionnalités

### Backend & Infrastructure
- **API Node.js/Express** — Serveur backend hébergé sur Render gérant les requêtes mobiles et desktop.
- **Base de données Supabase** — PostgreSQL gérant les profils, événements, documents et historique.
- **Stockage Cloudflare R2** — Stockage sécurisé des documents et images liés aux cours.
- **Paiements CinetPay** — Intégration pour la gestion des abonnements ou services.

### Frontend (Mobile & Desktop)
- **Authentification Firebase** — Gestion sécurisée de l'identité des utilisateurs.
- **Notifications Push** — Firebase Cloud Messaging pour des alertes en temps réel.
- **Visualisation PDF & Images** — Intégration de `syncfusion_flutter_pdfviewer` et `photo_view` pour la lecture des cours.
- **Base de données locale Hive/SQLite** — Mise en cache et fonctionnement optimal.
- **Multi-plateforme** — Support Android, iOS, Windows, macOS, et Linux depuis une seule base de code.

---

## Schéma de la base de données (Supabase)

```sql
user_profiles (
  profils enrichis, role, abonnement,
  appareils, tokens push
)

files (
  metadonnees des documents et
  controle d'acces
)

events (
  annonces et evenements
)

faculties (
  filtres academiques
)

payment_transactions (
  suivi du paiement CinetPay
)
```

---

## Choix de conception

| Aspect                                              |Choix                                                 |
| --------------------------------------------------- |----------------------------------------------------- |
| Frontend UI       | Flutter (Matérial Design)                                               |
| Backend API       | Node.js / Express                                               |
| Base de données   | Supabase (PostgreSQL)                                          |
| Auth & Push       | Firebase                                              |
| Stockage de Fichiers | Cloudflare R2                                                    |
| Stockage Local    | Hive & SQLite (sqflite)                                             |
