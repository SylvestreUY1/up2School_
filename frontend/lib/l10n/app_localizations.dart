import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Couche de localisation légère du projet.
///
/// On reste volontairement simple ici pour la phase d'épuration :
/// - seulement deux langues supportées (`fr` et `en`)
/// - résolution automatique selon la langue du système
/// - API directe via `context.l10n`
class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static AppLocalizations forLocale(Locale locale) => AppLocalizations(locale);

  static const supportedLocales = [
    Locale('fr'),
    Locale('en'),
  ];

  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = [
    _AppLocalizationsDelegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static AppLocalizations of(BuildContext context) {
    final localizations = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );

    assert(localizations != null, 'AppLocalizations non initialisé');
    return localizations!;
  }

  static Locale resolveLocale(Locale? deviceLocale) {
    if (deviceLocale == null) {
      return supportedLocales.first;
    }

    for (final supportedLocale in supportedLocales) {
      if (supportedLocale.languageCode == deviceLocale.languageCode) {
        return supportedLocale;
      }
    }

    return supportedLocales.first;
  }

  /// Prend en compte la liste de langues préférées du système.
  ///
  /// Exemple :
  /// - appareil configuré en `en-GB`, puis `fr-FR`
  /// - l'application choisit `en`
  /// Si aucune langue n'est supportée, on retombe sur le français.
  static Locale resolvePreferredLocale(Iterable<Locale>? deviceLocales) {
    if (deviceLocales == null) {
      return supportedLocales.first;
    }

    for (final locale in deviceLocales) {
      final resolved = supportedLocales.where(
        (supportedLocale) =>
            supportedLocale.languageCode == locale.languageCode,
      );
      if (resolved.isNotEmpty) {
        return resolved.first;
      }
    }

    return supportedLocales.first;
  }

  bool get isFrench => locale.languageCode == 'fr';

  String _pick(String french, String english) => isFrench ? french : english;

  String get appName => 'Up2School';
  String get loading => _pick('Chargement...', 'Loading...');
  String get loadingSession =>
      _pick('Chargement de la session...', 'Loading session...');
  String get loadingProfile =>
      _pick('Chargement du profil...', 'Loading profile...');
  String get startupError => _pick('Erreur de démarrage', 'Startup error');
  String get close => _pick('Fermer', 'Close');
  String get ok => 'OK';
  String get cancel => _pick('Annuler', 'Cancel');
  String get continueLabel => _pick('Continuer', 'Continue');
  String get refresh => _pick('Actualiser', 'Refresh');
  String get validate => _pick('Valider', 'Confirm');
  String get confirm => _pick('Confirmer', 'Confirm');
  String get modify => _pick('Modifier', 'Edit');
  String get change => _pick('Changer', 'Change');
  String get fileNotFound => _pick('Fichier introuvable', 'File not found');
  String get notSpecified => _pick('Non spécifié', 'Not specified');
  String get undefinedValue => _pick('non définie', 'undefined');
  String get newNotification =>
      _pick('Nouvelle notification', 'New notification');
  String get openNotification =>
      _pick('Ouvrir la notification', 'Open notification');

  String get importantNotificationsChannelName =>
      _pick('Notifications importantes', 'Important notifications');
  String get importantNotificationsChannelDescription => _pick(
        'Notifications pour les fichiers et événements',
        'Notifications for files and events',
      );
  String get reminderChannelName =>
      _pick('Rappels d’événements', 'Event reminders');
  String get reminderChannelDescription =>
      _pick('Rappels locaux pour les événements', 'Local reminders for events');

  String get login => _pick('Connexion', 'Sign in');
  String get register => _pick('Inscription', 'Sign up');
  String get signIn => _pick('Se connecter', 'Sign in');
  String get signUp => _pick('S’inscrire', 'Sign up');
  String get signOut => _pick('Déconnexion', 'Sign out');
  String get forgotPassword =>
      _pick('Mot de passe oublié ?', 'Forgot password?');
  String get resetPasswordTitle =>
      _pick('Réinitialisation du mot de passe', 'Reset password');
  String get enterYourEmail =>
      _pick('Entrez votre adresse email', 'Enter your email address');
  String get send => _pick('Envoyer', 'Send');
  String get email => 'Email';
  String get password => _pick('Mot de passe', 'Password');
  String get currentPassword =>
      _pick('Mot de passe actuel', 'Current password');
  String get newPassword => _pick('Nouveau mot de passe', 'New password');
  String get confirmPassword =>
      _pick('Confirmer le mot de passe', 'Confirm password');
  String get confirmNewPassword =>
      _pick('Confirmer le nouveau mot de passe', 'Confirm new password');
  String get fullName => _pick('Nom complet', 'Full name');
  String get noAccountYet => _pick('Pas encore de compte ?', 'No account yet?');
  String get alreadyHaveAccount =>
      _pick('Déjà un compte ?', 'Already have an account?');
  String get academicInformation =>
      _pick('Informations académiques', 'Academic information');
  String get faculty => _pick('Faculté', 'Faculty');
  String get level => _pick('Niveau', 'Level');
  String get field => _pick('Filière', 'Field');
  String get teachingUnit => _pick('Unité d\'enseignement', 'Teaching unit');
  String get documentType => _pick('Type de document', 'Document type');
  String get selectAcademicPath => _pick(
      'Veuillez sélectionner votre parcours académique',
      'Please select your academic track');
  String get selectYourTrack =>
      _pick('Sélectionnez votre parcours', 'Select your track');

  String get enterEmail =>
      _pick('Veuillez entrer votre email', 'Please enter your email');
  String get invalidEmail => _pick('Email invalide', 'Invalid email address');
  String get enterPassword =>
      _pick('Veuillez entrer votre mot de passe', 'Please enter your password');
  String get enterNewPassword =>
      _pick('Veuillez entrer un mot de passe', 'Please enter a password');
  String get passwordTooShort => _pick(
        'Le mot de passe doit contenir au moins 6 caractères',
        'Password must be at least 6 characters long',
      );
  String get enterFullName =>
      _pick('Veuillez entrer votre nom', 'Please enter your name');
  String get confirmYourPassword => _pick(
        'Veuillez confirmer le mot de passe',
        'Please confirm your password',
      );
  String get passwordsDoNotMatch =>
      _pick('Les mots de passe ne correspondent pas', 'Passwords do not match');
  String get selectFaculty =>
      _pick('Veuillez sélectionner une faculté', 'Please select a faculty');
  String get selectLevel =>
      _pick('Veuillez sélectionner un niveau', 'Please select a level');
  String get selectField =>
      _pick('Veuillez sélectionner une filière', 'Please select a field');
  String get noFieldAvailableForLevel => _pick(
        'Aucune filière disponible pour ce niveau',
        'No field is available for this level',
      );

  String get loginErrorDefault => _pick(
        'Erreur de connexion. Vérifiez votre connexion internet ou vos informations.',
        'Sign-in failed. Check your internet connection or credentials.',
      );
  String get registerErrorDefault => _pick(
        'Erreur d’inscription. Vérifiez votre connexion internet.',
        'Registration failed. Check your internet connection.',
      );
  String get resetEmailSent => _pick(
        'Email de réinitialisation envoyé. Vérifiez votre boîte de réception.',
        'Reset email sent. Check your inbox.',
      );

  String get connectionError =>
      _pick('Erreur de connexion', 'Connection error');
  String get info => 'Information';
  String get past => _pick('P', 'P');
  String get now => _pick('Maintenant', 'Now');
  String get all => _pick('Tous', 'All');
  String get favorites => _pick('Favoris', 'Favorites');
  String get recent => _pick('Récents', 'Recent');
  String get today => _pick('Aujourd’hui', 'Today');
  String get thisWeek => _pick('Cette semaine', 'This week');
  String get thisMonth => _pick('Ce mois', 'This month');
  String get delete => _pick('Supprimer', 'Delete');
  String get download => _pick('Télécharger', 'Download');
  String get openWithApp => _pick('Ouvrir avec une app', 'Open with an app');
  String get searchInDocument =>
      _pick('Rechercher dans le document...', 'Search in the document...');
  String get copyLink => _pick('Copier le lien', 'Copy link');
  String get zoomIn => _pick('Zoom +', 'Zoom +');
  String get zoomOut => _pick('Zoom -', 'Zoom -');
  String get resetZoom => _pick('Réinitialiser le zoom', 'Reset zoom');
  String get addEvent => _pick('Ajouter un événement', 'Add an event');
  String get noEventsToDisplay =>
      _pick('Aucun événement à afficher', 'No events to display');
  String get signInToViewEvents => _pick(
      'Connectez-vous pour voir les événements', 'Sign in to view events');
  String get noEventsInYourField => _pick(
        'Aucun événement dans votre filière',
        'No events in your field',
      );
  String get noScheduledEvents =>
      _pick('Aucun événement programmé', 'No scheduled events');
  String get createEventFieldRequired => _pick(
        'Vous devez avoir une filière pour créer un événement',
        'You must have a field to create an event',
      );
  String get deleteEventTitle => _pick('Supprimer l’événement', 'Delete event');
  String deleteEventMessage(String title) => _pick(
        'Êtes-vous sûr de vouloir supprimer l’événement "$title" ?',
        'Are you sure you want to delete the event "$title"?',
      );
  String get eventDeletedSuccess =>
      _pick('Événement supprimé avec succès', 'Event deleted successfully');
  String get eventDeleteFailed => _pick(
        'Erreur lors de la suppression. Vérifiez votre connexion internet',
        'Error while deleting. Check your internet connection',
      );
  String get eventLoadingError =>
      _pick('Erreur de chargement', 'Loading error');
  String todayAt(String time) => _pick('Aujourd\'hui, $time', 'Today, $time');
  String tomorrowAt(String time) => _pick('Demain, $time', 'Tomorrow, $time');
  String get allFields => _pick('Toutes filières', 'All fields');
  String get allLevels => _pick('Tous niveaux', 'All levels');
  String get eventPassedLabel => _pick('Événement passé', 'Past event');
  String get globalLabel => 'G';
  String get fileUnavailableLoading =>
      _pick('Erreur de chargement', 'Loading error');
  String get signInToDownloadFiles => _pick(
        'Connectez-vous pour télécharger des fichiers.',
        'Sign in to download files.',
      );
  String get downloadRestrictedToTrack => _pick(
        'Téléchargement autorisé uniquement pour les fichiers de votre filière et de votre niveau.',
        'Downloading is only allowed for files matching your field and level.',
      );
  String get downloadUnavailable =>
      _pick('Téléchargement indisponible', 'Download unavailable');
  String get fileDownloadedSuccess =>
      _pick('Fichier téléchargé avec succès', 'File downloaded successfully');
  String get fileDownloadFailed => _pick(
        'Le fichier n’a pas pu être téléchargé. Réessayez.',
        'The file could not be downloaded. Please try again.',
      );
  String get fileOpenOnDeviceFailed => _pick(
        'Le fichier n’a pas pu être ouvert sur cet appareil.',
        'The file could not be opened on this device.',
      );
  String get installPowerPointSuggestion => _pick(
        'Installez Microsoft PowerPoint, Google Slides ou une application compatible.',
        'Install Microsoft PowerPoint, Google Slides, or a compatible app.',
      );
  String get installWordSuggestion => _pick(
        'Installez Microsoft Word, Google Docs ou une application compatible.',
        'Install Microsoft Word, Google Docs, or a compatible app.',
      );
  String get installExcelSuggestion => _pick(
        'Installez Microsoft Excel, Google Sheets ou une application compatible.',
        'Install Microsoft Excel, Google Sheets, or a compatible app.',
      );
  String get installPdfSuggestion => _pick(
        'Installez un lecteur PDF (Adobe Acrobat, etc.).',
        'Install a PDF reader (Adobe Acrobat, etc.).',
      );
  String get installCompatibleAppSuggestion => _pick(
        'Installez une application capable d’ouvrir ce type de fichier.',
        'Install an app capable of opening this file type.',
      );
  String unableToOpenFileWithSuggestion(String suggestion) => _pick(
        'Impossible d’ouvrir le fichier. $suggestion',
        'Unable to open the file. $suggestion',
      );
  String get linkCopied =>
      _pick('Lien copié dans le presse-papier', 'Link copied to clipboard');
  String get archiveSubscriptionRequired => _pick(
        'Abonnement requis pour consulter cette archive.',
        'A subscription is required to view this archive.',
      );
  String get fileLabel => _pick('Fichier', 'File');
  String get extensionLabel => _pick('Extension', 'Extension');
  String get downloadsLabel => _pick('Téléchargements', 'Downloads');
  String get viewsLabel => _pick('Vues', 'Views');
  String get progressLabel => _pick('Progression', 'Progress');
  String get contentUnavailableNeedDownload => _pick(
        'Contenu non disponible - le fichier doit être téléchargé pour être visualisé.',
        'Content unavailable - the file must be downloaded to be viewed.',
      );
  String activeSearchFor(String query) =>
      _pick('Recherche active pour: "$query"', 'Active search for: "$query"');
  String get useSearchBarToFindText => _pick(
        'Utilisez la barre de recherche pour trouver du texte',
        'Use the search bar to find text',
      );
  String openDocumentType(String type) =>
      _pick('Document $type', '$type document');
  String get openDocument => 'OpenDocument';
  String openDocumentKind(String extension) {
    switch (extension) {
      case 'odt':
        return _pick('Document texte', 'Text document');
      case 'ods':
        return _pick('Tableur', 'Spreadsheet');
      case 'odp':
        return _pick('Présentation', 'Presentation');
      case 'odg':
        return _pick('Dessin', 'Drawing');
      case 'odf':
        return _pick('Formule mathématique', 'Math formula');
      case 'odb':
        return _pick('Base de données', 'Database');
      case 'odc':
        return _pick('Graphique', 'Chart');
      default:
        return openDocument;
    }
  }

  String get openDocumentDescription => _pick(
        'Les fichiers OpenDocument peuvent être ouverts avec LibreOffice, OpenOffice ou d’autres suites bureautiques compatibles.',
        'OpenDocument files can be opened with LibreOffice, OpenOffice, or other compatible office suites.',
      );
  String get officeDocument => _pick('Document Office', 'Office document');
  String officeDocumentKind(String extension) {
    switch (extension) {
      case 'doc':
      case 'docx':
        return _pick('Document Word', 'Word document');
      case 'xls':
      case 'xlsx':
        return _pick('Feuille de calcul Excel', 'Excel spreadsheet');
      case 'ppt':
      case 'pptx':
        return _pick('Présentation PowerPoint', 'PowerPoint presentation');
      case 'mdb':
        return _pick('Base de données Access', 'Access database');
      default:
        return officeDocument;
    }
  }

  String get officeDocumentDescription => _pick(
        'Ce document nécessite Microsoft Office, LibreOffice ou une application compatible pour être visualisé.',
        'This document requires Microsoft Office, LibreOffice, or a compatible app to be viewed.',
      );
  String get openWithOffice => _pick('Ouvrir avec Office', 'Open with Office');
  String get ebook => _pick('Livre électronique', 'E-book');
  String get compressedArchive =>
      _pick('Archive compressée', 'Compressed archive');
  String get archiveDescription => _pick(
        'Ce fichier contient plusieurs fichiers compressés. Décompressez-le pour accéder à son contenu.',
        'This file contains multiple compressed files. Extract it to access its contents.',
      );
  String get downloadArchive =>
      _pick('Télécharger l’archive', 'Download archive');
  String get audioFile => _pick('Fichier audio', 'Audio file');
  String get videoFile => _pick('Fichier vidéo', 'Video file');
  String unsupportedFormat(String extension) => _pick(
      'Format .$extension non supporté', 'Unsupported .$extension format');
  String get unsupportedFileDescription => _pick(
        'Ce type de fichier ne peut pas être visualisé directement dans l’application.',
        'This file type cannot be viewed directly in the application.',
      );
  String get archiveAccessSubscriptionRequired => _pick(
        'Abonnement requis pour acceder a cette archive',
        'Subscription required to access this archive',
      );
  String get premiumArchive => _pick('Archive Premium', 'Premium archive');
  String get premiumArchiveDescription => _pick(
        'Ce document a ete publie avant juillet et necessite un abonnement actif pour etre ouvert ou telecharge.',
        'This document was published before July and requires an active subscription to open or download.',
      );
  String get page => _pick('Page', 'Page');
  String progressPercent(String value) =>
      _pick('Progression: $value%', 'Progress: $value%');
  String pageCount(int currentPage, int totalPages) =>
      _pick('Page $currentPage/$totalPages', 'Page $currentPage/$totalPages');
  String get fileNotAvailableLocally => _pick(
        'Fichier non présent localement',
        'File not available locally',
      );
  String get localCopyDeleted =>
      _pick('Copie locale supprimée', 'Local copy deleted');
  String get localCopyDeleteFailed => _pick(
        'La copie locale n’a pas pu être supprimée.',
        'The local copy could not be deleted.',
      );
  String get deleteFileTitle => _pick('Supprimer le fichier', 'Delete file');
  String get deleteFileMessage => _pick(
        'Êtes-vous sûr de vouloir supprimer ce fichier ? Cette action est irréversible.',
        'Are you sure you want to delete this file? This action cannot be undone.',
      );
  String get fileDeletedSuccess =>
      _pick('Fichier supprimé avec succès', 'File deleted successfully');
  String get fileDeleteFailed => _pick(
        'Le fichier n’a pas pu être supprimé pour le moment. Réessayez.',
        'The file could not be deleted right now. Please try again.',
      );
  String get shareFileSubject =>
      _pick('Partage de fichier depuis UY1-lib', 'File shared from UY1-lib');
  String get signInToDownloadOrExport => _pick(
        'Connectez-vous pour télécharger ou exporter des fichiers.',
        'Sign in to download or export files.',
      );
  String get exportRestrictedToTrack => _pick(
        'Vous ne pouvez exporter que les fichiers de votre filière et de votre niveau.',
        'You can only export files matching your field and level.',
      );
  String get storagePermissionDenied =>
      _pick('Permission de stockage refusée', 'Storage permission denied');
  String get preparingFile =>
      _pick('Préparation du fichier...', 'Preparing file...');
  String fileExportedTo(String path) =>
      _pick('Fichier exporté vers $path', 'File exported to $path');
  String get fileExportFailed => _pick(
        'Le fichier n’a pas pu être exporté. Réessayez.',
        'The file could not be exported. Please try again.',
      );
  String get favoriteAddFailed => _pick(
        'Impossible d’ajouter ce fichier aux favoris.',
        'Unable to add this file to favorites.',
      );
  String get signInToAddFavorites => _pick(
        'Connectez-vous pour ajouter aux favoris',
        'Sign in to add favorites',
      );
  String get fileOpenFailed => _pick(
        'Le fichier n’a pas pu être ouvert pour le moment.',
        'The file could not be opened right now.',
      );
  String get subscriptionRequired =>
      _pick('Abonnement requis', 'Subscription required');
  String get accessRequired => _pick('Accès requis', 'Access required');
  String get previousYearArchiveDescription => _pick(
        'Ce fichier appartient aux archives de l\'annee scolaire precedente. Un abonnement actif est necessaire pour l\'ouvrir ou le telecharger.',
        'This file belongs to the previous academic year archives. An active subscription is required to open or download it.',
      );
  String get previousYearArchiveAccessDescription => _pick(
        'Ce fichier appartient aux archives de l\'annee scolaire precedente. Certains contenus necessitent un acces actif pour etre ouverts ou telecharges.',
        'This file belongs to the previous academic year archives. Some content requires active access to open or download.',
      );
  String get noFilesAvailable =>
      _pick('Aucun fichier disponible', 'No files available');

  String get resources => _pick('Ressources', 'Resources');
  String get events => _pick('Événements', 'Events');
  String get profile => _pick('Profil', 'Profile');
  String get announcements => _pick('Annonces', 'Announcements');
  String get administration => _pick('Administration', 'Administration');
  String get adminConsole => _pick('Console admin', 'Admin console');
  String get manageCampaigns =>
      _pick('Gérer les campagnes', 'Manage campaigns');
  String get usersAndStructures =>
      _pick('Utilisateurs et structures', 'Users and structures');
  String get browseLibrary =>
      _pick('Explorer la bibliothèque', 'Browse the library');
  String get eventsTracking =>
      _pick('Suivi de la programmation', 'Track the schedule');
  String get accessYourAccount =>
      _pick('Accéder à votre compte', 'Access your account');
  String get settingsAndSubscription =>
      _pick('Paramètres et abonnement', 'Settings and subscription');
  String get guestSession => _pick('Session invitée', 'Guest session');
  String get desktopMode => _pick('Mode bureau', 'Desktop mode');
  String get eventsSpace => _pick('Espace événements', 'Events space');
  String get profileSpace => _pick('Espace profil', 'Profile space');
  String get universityLibrary =>
      _pick('Bibliothèque universitaire', 'University library');
  String get appOverview => _pick(
        'UY1-Lib centralise et facilite le partage de ressources pédagogiques et d’informations.',
        'UY1-Lib centralizes and simplifies the sharing of learning resources and information.',
      );
  String get eventsSpaceDescription => _pick(
        'Consultez, filtrez et publiez les événements académiques depuis un espace mieux adapté au bureau.',
        'Browse, filter, and publish academic events from a workspace that feels better on desktop.',
      );
  String get guestProfileDescription => _pick(
        'Connectez-vous pour retrouver votre profil, vos privilèges et vos informations académiques.',
        'Sign in to access your profile, privileges, and academic information.',
      );
  String get profileDescription => _pick(
        'Retrouvez vos informations personnelles, vos droits et vos paramètres de compte.',
        'Find your personal information, permissions, and account settings.',
      );
  String get libraryExplorerDescription => _pick(
        'Parcourez les facultés, niveaux, filières et ressources depuis une navigation latérale plus confortable.',
        'Browse faculties, levels, tracks, and resources from a more comfortable side navigation.',
      );
  String currentProgress(String path) =>
      _pick('Progression actuelle : $path', 'Current progress: $path');
  String pathProgress(int current, int total) =>
      _pick('Parcours $current/$total', 'Path $current/$total');
  String get adminOnlyAccess => _pick('Accès réservé aux administrateurs',
      'Access reserved for administrators');

  String get yearlySubscription =>
      _pick('Abonnement annuel', 'Yearly subscription');
  String get archiveAccess => _pick('Accès aux archives', 'Archive access');
  String subscriptionActiveUntil(String date) =>
      _pick('Actif jusqu’au $date', 'Active until $date');
  String get subscriptionLockedDescription => _pick(
        'Les fichiers publiés les années antérieures sont verrouillés sans abonnement (350 FCFA/an).',
        'Files published in previous academic years are locked without a subscription (350 FCFA/year).',
      );
  String get accessLockedDescription => _pick(
        'Certains contenus des annees precedentes necessitent un acces actif.',
        'Some content from previous academic years requires active access.',
      );
  String get activeStatus => _pick('Actif', 'Active');
  String get subscribe => _pick('S’abonner', 'Subscribe');
  String get checkAccess => _pick('Vérifier mon accès', 'Check my access');
  String get enabledLabel => _pick('On', 'On');
  String get disabledLabel => _pick('Off', 'Off');
  String schoolYearLabel(String year) =>
      _pick('Année scolaire : $year', 'Academic year: $year');
  String paymentNumberLabel(String phone) =>
      _pick('Numéro de paiement : $phone', 'Payment number: $phone');
  String phoneLabel(String phone) =>
      _pick('Téléphone associé : $phone', 'Phone on file: $phone');
  String get subscriptionStatusUpdated =>
      _pick('Statut d’abonnement actualisé', 'Subscription status updated');
  String get subscriptionStatusUpdateFailed => _pick(
        'Impossible d’actualiser l’abonnement',
        'Unable to refresh subscription status',
      );
  String get subscriptionActivated => _pick(
      'Abonnement activé avec succès', 'Subscription activated successfully');
  String get paymentNumberPrompt => _pick(
        'Numéro Mobile Money ou Orange Money',
        'Mobile Money or Orange Money number',
      );
  String get phone => _pick('Téléphone', 'Phone');
  String get paymentPhoneExample => _pick('Ex : 670000000', 'Ex: 670000000');
  String get paymentLinkUnavailable =>
      _pick('Lien de paiement indisponible', 'Payment link unavailable');
  String get unableToOpenPaymentLink => _pick(
        'Impossible d’ouvrir le lien de paiement',
        'Unable to open the payment link',
      );
  String get confirmPaymentReturn => _pick(
        'Validez le paiement puis revenez dans l’application.',
        'Complete the payment, then return to the app.',
      );
  String get paymentLaunchFailed => _pick(
        'Le paiement n’a pas pu être lancé. Réessayez dans un instant.',
        'The payment could not be started. Please try again shortly.',
      );

  String get adminPanel => _pick('Panneau d’administration', 'Admin panel');
  String get manageUsersStructures => _pick(
      'Gérer les utilisateurs et structures', 'Manage users and structures');
  String get changePassword =>
      _pick('Changer le mot de passe', 'Change password');
  String get deleteAccount => _pick('Supprimer le compte', 'Delete account');
  String get deleteMyAccount =>
      _pick('Supprimer mon compte', 'Delete my account');
  String get deleteAccountWarning => _pick(
        'Cette action est irréversible. Toutes vos données seront supprimées.',
        'This action is irreversible. All your data will be deleted.',
      );
  String get signOutSuccess =>
      _pick('Déconnexion réussie', 'Signed out successfully');
  String get signOutConfirmMessage => _pick(
      'Êtes-vous sûr de vouloir vous déconnecter ?',
      'Are you sure you want to sign out?');
  String get signOutFailed => _pick(
        'La déconnexion n’a pas pu être terminée. Réessayez.',
        'Sign out could not be completed. Please try again.',
      );
  String get accountDeletionFailed => _pick(
        'Le compte n’a pas pu être supprimé pour le moment.',
        'The account could not be deleted right now.',
      );
  String get enterYourPassword =>
      _pick('Veuillez entrer votre mot de passe', 'Please enter your password');
  String get passwordChanged =>
      _pick('Mot de passe changé avec succès', 'Password changed successfully');
  String get passwordChangeFailed => _pick(
        'Le mot de passe n’a pas pu être modifié. Réessayez.',
        'The password could not be changed. Please try again.',
      );
  String get accountDeleteForever =>
      _pick('Supprimer définitivement', 'Delete permanently');

  String get language => _pick('Langue', 'Language');
  String get systemDefault => _pick('Système', 'System');
  String get french => 'Français';
  String get english => 'English';
  String get appLanguage => _pick('Langue de l’application', 'App language');
  String get appLanguageDescription => _pick(
        'Choisissez la langue de l’interface et des notifications locales.',
        'Choose the language for the interface and local notifications.',
      );

  String get academicInfoHint => _pick(
        'Ces informations déterminent les documents et événements qui vous sont proposés.',
        'This information determines which documents and events are shown to you.',
      );

  String get licenseMaster => _pick('Licence / Master', 'Bachelor / Master');
  String documentsOf(String type) =>
      _pick('Documents de $type', '$type documents');
  String levelLabel(String level) => _pick('Niveau $level', 'Level $level');

  String documentTypeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'cours':
        return _pick('Cours', 'Courses');
      case 'td':
        return 'TD';
      case 'sujets':
      case 'sujets d\'examen':
        return _pick('Sujets d’examen', 'Exam papers');
      case 'projets':
        return _pick('Projets', 'Projects');
      case 'autres':
      case 'autres ressources':
        return _pick('Autres ressources', 'Other resources');
      default:
        return type;
    }
  }

  String roleLabel(String role) {
    switch (role) {
      case 'admin':
        return _pick('Administrateur', 'Administrator');
      case 'delegate':
        return _pick('Délégué', 'Delegate');
      case 'student':
        return _pick('Étudiant', 'Student');
      default:
        return _pick('Invité', 'Guest');
    }
  }

  String roleOnDesktop(String roleLabel) =>
      _pick('$roleLabel sur bureau', '$roleLabel on desktop');

  String reminderTitle(String eventTitle, {bool immediate = false}) => immediate
      ? _pick(
          'Rappel immédiat : $eventTitle', 'Immediate reminder: $eventTitle')
      : _pick('Rappel : $eventTitle', 'Reminder: $eventTitle');

  String reminderBody(String eventTitle, int hoursBefore,
      {bool immediate = false}) {
    if (immediate) {
      if (hoursBefore == 1) {
        return _pick(
          'L’événement "$eventTitle" commence dans moins d’une heure.',
          'The event "$eventTitle" starts in less than one hour.',
        );
      }
      return _pick(
        'L’événement "$eventTitle" commence dans moins de $hoursBefore heures.',
        'The event "$eventTitle" starts in less than $hoursBefore hours.',
      );
    }

    if (hoursBefore == 1) {
      return _pick(
        'L’événement "$eventTitle" commence dans 1 heure.',
        'The event "$eventTitle" starts in 1 hour.',
      );
    }

    return _pick(
      'L’événement "$eventTitle" approche dans $hoursBefore heures.',
      'The event "$eventTitle" is coming up in $hoursBefore hours.',
    );
  }

  String inMonths(int months) =>
      _pick('Dans $months mois', 'In $months months');

  String inDays(int days) => _pick('Dans $days jours', 'In $days days');

  String inHours(int hours) => _pick('Dans $hours heures', 'In $hours hours');

  String inMinutes(int minutes) =>
      _pick('Dans $minutes minutes', 'In $minutes minutes');

  String openUrlError(String url) =>
      _pick('Impossible d’ouvrir l’URL : $url', 'Unable to open URL: $url');

  String genericError(String details) =>
      _pick('Erreur : $details', 'Error: $details');

  String secondsLabel(int seconds) =>
      _pick('$seconds secondes', '$seconds seconds');

  String minutesLabel(int minutes) =>
      _pick('$minutes minutes', '$minutes minutes');

  String hoursLabel(String hours) => _pick('$hours heures', '$hours hours');

  String daysLabel(String days) => _pick('$days jours', '$days days');
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
        (supportedLocale) =>
            supportedLocale.languageCode == locale.languageCode,
      );

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
