# Configuration Google Sign-In pour Desktop (Linux/Windows)

## 📋 Pré-requis

L'authentification Google fonctionne maintenant sur desktop (Linux et Windows) via un navigateur OAuth.

## 🔧 Configuration requise dans Google Cloud Console

### 1. Vérifier le client ID web

1. Accédez à [Google Cloud Console](https://console.cloud.google.com/)
2. Sélectionnez le projet `up2school-app`
3. Allez à **APIs & Services** → **Credentials**
4. Cherchez la credential de type "OAuth 2.0 Client ID" avec le label "Web client"
5. Le Client ID devrait être: `846269435063-cbsj8fhcou2ojhsgspni5o5c1b3n047n.apps.googleusercontent.com`

### 2. Autoriser localhost comme RedirectURI

1. Cliquez sur le client ID web pour l'éditer
2. Sous **Authorized redirect URIs**, ajoutez ces adresses:
   - `http://localhost` (exact, pas de slash à la fin)
   - `http://localhost:8080` (alternative si port spécifique)
   - `http://127.0.0.1` (alternative)

3. Cliquez sur **Save**

### 3. Vérifier les origines JavaScript autorisées

1. Sous **Authorized JavaScript origins**, ajoutez:
   - `http://localhost`

## 🚀 Utilisation sur Desktop

### Linux/Ubuntu

```bash
cd frontend
flutter run -d linux
```

### Windows

```bash
cd frontend
flutter run -d windows
```

### Lors du login

1. Cliquez sur le bouton "Se connecter avec Google"
2. Un navigateur s'ouvrira automatiquement
3. Complétez l'authentification Google
4. Vous serez redirigé vers l'application

## 📱 Comportement différent par plateforme

- **Mobile (Android/iOS)**: Utilise le SDK natif Google Sign-In
- **Desktop (Linux/Windows)**: Utilise un navigateur OAuth avec callback localhost
- **Web**: Utilise le SDK JavaScript Google Sign-In

## ⚠️ Notes importantes

- La connexion est maintenant disponible sur tous les appareils desktop
- No need to disable anything in AppConfig - la détection est automatique
- L'accès token peut expirer après 1 heure (normal pour OAuth)
