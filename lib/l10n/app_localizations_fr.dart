// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Application Visionnaire';

  @override
  String get deviceLang => 'fr-FR';

  @override
  String get login => 'Se connecter';

  @override
  String get username => 'Nom d\'utilisateur';

  @override
  String get password => 'Mot de passe';

  @override
  String get chatList => 'Liste de chats';

  @override
  String get chatTitleCannotBeEmpty => 'Le titre du chat ne peut pas être vide ou contenir uniquement des espaces';

  @override
  String get cameraList => 'Flux de caméras';

  @override
  String get detection => 'Détection d\'objets';

  @override
  String get logout => 'Déconnexion';

  @override
  String get changeLanguage => 'Changer de langue';

  @override
  String get site => 'Chantier';

  @override
  String get stream => 'Flux';

  @override
  String get detectionTime => 'Heure de détection';

  @override
  String get violationMessage => 'Message d\'infraction';

  @override
  String get loadingImageError => 'Impossible de charger l\'image';

  @override
  String get violationRecordQuery => 'Requête de registre d\'infraction';

  @override
  String get keyword => 'Mot-clé (stream_name ou message)';

  @override
  String get startTime => 'Heure de début';

  @override
  String get endTime => 'Heure de fin';

  @override
  String get query => 'Rechercher';

  @override
  String get noRecords => 'Aucun enregistrement disponible';

  @override
  String get streamingWebSettings => 'Surveillance en direct';

  @override
  String get streamingWebUrl => 'Streaming Web URL (avec http:// ou https://)';

  @override
  String get save => 'Sauvegarder';

  @override
  String get goToLabels => 'Aller aux sites';

  @override
  String get currentUrl => 'URL actuelle';

  @override
  String get labelList => 'Sites';

  @override
  String get label => 'Étiquette';

  @override
  String get noImage => 'Aucune image de caméra disponible';

  @override
  String get warnings => 'Avertissements';

  @override
  String get lastUpdated => 'Dernière mise à jour';

  @override
  String get noWarnings => 'Aucun avertissement';

  @override
  String get detectionResult => 'Résultat de détection';

  @override
  String get chooseModel => 'Choisir un modèle';

  @override
  String get noImageSelected => 'Aucune image sélectionnée';

  @override
  String get noDetectionResult => 'Aucun résultat de détection';

  @override
  String get takePhoto => 'Prendre une photo';

  @override
  String get photoLibrary => 'Bibliothèque de photos';

  @override
  String get startDetection => 'Lancer la détection';

  @override
  String get cannotOpenCamera => 'Impossible d\'ouvrir la caméra';

  @override
  String get cannotOpenGallery => 'Impossible d\'ouvrir la galerie';

  @override
  String get getImageSizeFailed => 'Échec de récupération de la taille de l\'image';

  @override
  String get notLoggedIn => 'Non connecté (jeton de service de détection invalide)';

  @override
  String get tokenRefreshFailed => 'Échec du rafraîchissement du jeton';

  @override
  String get chatLoadFailed => 'Échec du chargement de la conversation';

  @override
  String get chatRoom => 'Salle de discussion';

  @override
  String get inputMessage => 'Entrez un message...';

  @override
  String get newChatRoom => 'Nouvelle Salle de Discussion';

  @override
  String get enterChatRoomTitle => 'Entrez le titre de la salle';

  @override
  String get create => 'Créer';

  @override
  String get createFailed => 'Échec de la création';

  @override
  String get confirmDeleteChatRoom => 'Êtes-vous sûr de vouloir supprimer cette salle de discussion ?';

  @override
  String get cancel => 'Annuler';

  @override
  String get delete => 'Supprimer';

  @override
  String get deleteFailed => 'Échec de la suppression';

  @override
  String get selectSite => 'Sélectionnez le chantier';

  @override
  String get notSelected => 'Non sélectionné';

  @override
  String errorPrefix(String error) {
    return 'Erreur : $error';
  }

  @override
  String get sitePrefix => 'Chantier : ';

  @override
  String get streamPrefix => 'Flux : ';

  @override
  String get detectionTimePrefix => 'Heure de détection : ';

  @override
  String get urlUpdated => 'URL de Streaming Web mis à jour :';

  @override
  String get streamingWebIndexTitle => 'Sites';

  @override
  String get unknownError => 'Erreur inconnue';

  @override
  String get noLabels => 'Aucune étiquette disponible';

  @override
  String get chatMessageCannotBeEmpty => 'Le message de la salle de discussion ne peut pas être vide';

  @override
  String get editQuestionHint => 'Veuillez saisir une nouvelle question';

  @override
  String get confirm => 'Confirmer';

  @override
  String get editQuestion => 'Modifier la question';

  @override
  String get regenerateAnswer => 'Régénérer la réponse';

  @override
  String get removeQuestionChain => 'Supprimer la question (et les dialogues suivants)';

  @override
  String get failedToLoadHistory => 'Échec du chargement de l\'historique';

  @override
  String get failedToLoadHistoryAfterRefresh => 'Échec du chargement de l\'historique après rafraîchissement';

  @override
  String get failedToAskAfterRefresh => 'Échec de la demande après rafraîchissement';

  @override
  String get editFailed => 'Échec de la modification';

  @override
  String get editFailedAfterRefresh => 'Échec de la modification après rafraîchissement';

  @override
  String get regenerateFailed => 'Échec de la régénération';

  @override
  String get regenerateFailedAfterRefresh => 'Échec de la régénération après rafraîchissement';

  @override
  String get removeFailed => 'Échec de la suppression';

  @override
  String get removeFailedAfterRefresh => 'Échec de la suppression après rafraîchissement';

  @override
  String get sendMessage => 'Envoyer le message';

  @override
  String get addImages => 'Ajouter des images';

  @override
  String get addFiles => 'Ajouter des fichiers';

  @override
  String attachmentCount(int count) {
    return '$count pièces jointes';
  }

  @override
  String get cancelGeneration => 'Annuler la génération';

  @override
  String get createChatRoom => 'Créer une salle de discussion';

  @override
  String attachmentUploadFailed(String error) {
    return 'Échec du téléversement de la pièce jointe : $error';
  }

  @override
  String attachmentDeleteFailed(String error) {
    return 'Échec de la suppression de la pièce jointe : $error';
  }

  @override
  String get selectLabel => 'Sélectionner une étiquette';

  @override
  String get showDetectionResults => 'Afficher les résultats de détection';

  @override
  String get hardhat => 'Casque de sécurité';

  @override
  String get vest => 'Gilet';

  @override
  String get machinery => 'Machinerie';

  @override
  String get vehicle => 'Véhicule';

  @override
  String get no_hardhat => 'Pas de casque';

  @override
  String get no_vest => 'Pas de gilet';

  @override
  String get person => 'Personne';

  @override
  String get cone => 'Cône de sécurité';

  @override
  String get mask => 'Masque';

  @override
  String get no_mask => 'Pas de masque';

  @override
  String get utility_pole => 'Poteau utilitaire';

  @override
  String warning_people_in_controlled_area(int count) {
    return 'Attention: $count personnes sont entrées dans la zone contrôlée!';
  }

  @override
  String warning_people_in_utility_pole_controlled_area(int count) {
    return 'Attention: $count personnes sont entrées dans la zone contrôlée du poteau utilitaire!';
  }

  @override
  String warning_no_hardhat(int count) {
    return 'Avertissement: $count personnes ne portent pas de casque!';
  }

  @override
  String warning_no_safety_vest(int count) {
    return 'Avertissement: $count personnes ne portent pas de gilet de sécurité!';
  }

  @override
  String warning_close_to_machinery(int count) {
    return 'Attention: $count personnes sont trop proches de la machinerie!';
  }

  @override
  String warning_close_to_vehicle(int count) {
    return 'Attention: $count personnes sont trop proches des véhicules!';
  }

  @override
  String detect_machinery_close_to_pole(int count) {
    return 'Avertissement: $count machines sont trop proches du poteau!';
  }

  @override
  String get showOverlay => 'Afficher l\'overlay';

  @override
  String get add => 'Ajouter';

  @override
  String get edit => 'Modifier';

  @override
  String get submit => 'Soumettre';

  @override
  String get build => 'Créer';

  @override
  String get saving => 'Enregistrement...';

  @override
  String get saveConfig => 'Enregistrer la configuration';

  @override
  String get configSavedSuccessfully => 'Configuration enregistrée avec succès';

  @override
  String get saveConfigFailed => 'Échec de l\'enregistrement de la configuration';

  @override
  String get confirmResetAllConfigs => 'Êtes-vous sûr de vouloir réinitialiser toutes les configurations API aux valeurs par défaut ? Cette action ne peut pas être annulée.';

  @override
  String confirmResetConfig(String name) {
    return 'Êtes-vous sûr de vouloir réinitialiser $name aux valeurs par défaut ?';
  }

  @override
  String get confirmDelete => 'Confirmer la suppression ?';

  @override
  String permanentDeleteWarning(String name) {
    return 'Supprimera définitivement \"$name\". Cette action ne peut pas être annulée !';
  }

  @override
  String deleteWarning(String name) {
    return 'Supprimera \"$name\". Cette action ne peut pas être annulée.';
  }

  @override
  String get siteCreated => '✅ Site créé';

  @override
  String get deleted => '✅ Supprimé';

  @override
  String get added => '✅ Ajouté';

  @override
  String get featureAdded => '✅ Fonctionnalité ajoutée';

  @override
  String editFeature(String name) {
    return 'Modifier \"$name\"';
  }

  @override
  String editUser(String username) {
    return 'Modifier \"$username\"';
  }

  @override
  String get addUser => 'Ajouter un utilisateur';

  @override
  String get addFeature => 'Ajouter une fonctionnalité';

  @override
  String get addGroup => 'Ajouter un groupe';

  @override
  String get editGroup => 'Modifier le groupe';

  @override
  String get confirmDeleteFile => 'Confirmer la suppression';

  @override
  String get confirmDeleteFileMessage => 'Êtes-vous sûr de vouloir supprimer ce fichier ?';

  @override
  String get fileDeleted => 'Fichier supprimé';

  @override
  String get deleteFileFailed => 'Échec de la suppression';

  @override
  String get createAuditDoc => 'Créer un document d\'amélioration d\'audit';

  @override
  String get createDocx => 'Créer DOCX';

  @override
  String get addPhotoPrompt => 'Veuillez ajouter des photos en prenant des photos ou depuis l\'album';

  @override
  String createFailedWith(String error) {
    return 'Échec de la création : $error';
  }

  @override
  String get addFile => 'Ajouter un fichier';

  @override
  String get noConfigChangesDetected => 'Aucun changement de configuration détecté';

  @override
  String get resetToDefaults => 'Réinitialiser aux valeurs par défaut';

  @override
  String get resetSuccess => 'Réinitialisation à la configuration par défaut';

  @override
  String get resetFailed => 'Échec de la réinitialisation';

  @override
  String resetEndpointSuccess(String name) {
    return 'Réinitialisation de $name réussie';
  }

  @override
  String resetEndpoint(String name) {
    return 'Réinitialiser $name';
  }

  @override
  String get notLoggedInOrInvalidToken => 'Non connecté ou jeton invalide';

  @override
  String uploadFailed(String error) {
    return 'Échec du téléchargement : $error';
  }

  @override
  String get pleaseWaitForSiteList => 'Liste des sites pas encore chargée, veuillez patienter';

  @override
  String get selectConstructionSite => 'Sélectionner le site de construction';

  @override
  String get allSites => 'Tous les sites';

  @override
  String get startDate => 'Date de début';

  @override
  String get endDate => 'Date de fin';

  @override
  String get versions => 'Versions';

  @override
  String get fileTypeNotConfigured => 'Ce type de fichier n\'a pas de file_prefix configuré, impossible d\'utiliser le modèle';

  @override
  String get noUsers => 'Aucun utilisateur pour le moment';

  @override
  String nameDisplay(String name, String email, String role, String group) {
    return 'Nom: $name | Courriel: $email | Rôle: $role | Groupe: $group';
  }

  @override
  String get deactivate => 'Désactiver';

  @override
  String get activate => 'Activer';

  @override
  String get permissionDenied => 'Permission refusée';

  @override
  String get userManagement => 'Gestion d\'Utilisateurs';

  @override
  String get account => 'Compte';

  @override
  String get familyName => 'Nom de famille';

  @override
  String get middleName => 'Deuxième prénom';

  @override
  String get givenName => 'Prénom';

  @override
  String get email => 'Courriel';

  @override
  String get mobile => 'Mobile';

  @override
  String get resetPassword => 'Réinitialiser le mot de passe';

  @override
  String get role => 'Rôle';

  @override
  String get group => 'Groupe';

  @override
  String get required => 'Requis';

  @override
  String get emailFormatError => 'Veuillez saisir une adresse courriel valide';

  @override
  String get selectGroup => 'Veuillez sélectionner un groupe';

  @override
  String get mobileOptional => 'Mobile (Optionnel)';

  @override
  String get middleNameOptional => 'Deuxième prénom (Optionnel)';

  @override
  String get updated => '✅ Mis à Jour';

  @override
  String get apiConfig => 'Configuration API';

  @override
  String get custom => 'Personnalisé';

  @override
  String deleteFeatureConfirmation(Object name) {
    return 'Supprimera la fonctionnalité \\\"$name\\\". Cette action ne peut pas être annulée.';
  }

  @override
  String assignGroups(Object name) {
    return 'Assigner des groupes - $name';
  }

  @override
  String get setGroups => 'Définir les groupes';

  @override
  String get reload => 'Recharger';

  @override
  String get copy => 'Copier';

  @override
  String get passwordChanged => '✅ Mot de passe changé, veuillez vous reconnecter avec le nouveau mot de passe';

  @override
  String get oldPassword => 'Ancien Mot de Passe';

  @override
  String get newPassword => 'Nouveau Mot de Passe';

  @override
  String get pleaseLoginFirst => 'Veuillez vous connecter d\'abord';

  @override
  String get changePassword => 'Changer le Mot de Passe';

  @override
  String get minimumPasswordLength => 'Au moins 8 caractères';

  @override
  String get featureManagement => 'Gestion de Fonctionnalités';

  @override
  String get featureName => 'Nom de Fonctionnalité';

  @override
  String get descriptionOptional => 'Description (facultative)';

  @override
  String assignGroup(String name) {
    return 'Assigner Groupe - $name';
  }

  @override
  String get noFeatures => 'Aucune fonctionnalité';

  @override
  String get groupPermissionsUpdated => '✅ Permissions du groupe mises à jour';

  @override
  String get setGroup => 'Définir Groupe';

  @override
  String get groupManagement => 'Gestion de Groupes';

  @override
  String get groupName => 'Nom de Groupe';

  @override
  String get uniformNumber => 'Numéro Uniforme (8 chiffres)';

  @override
  String get uniformNumberError => 'Le numéro uniforme nécessite 8 chiffres';

  @override
  String get noGroups => 'Aucun groupe';

  @override
  String uniformLabel(String uniformNumber) {
    return 'Uniforme: $uniformNumber';
  }

  @override
  String get uniformNumberValidation => 'Doit être 8 chiffres';

  @override
  String get name => 'Nom';

  @override
  String get siteManagement => 'Gestion de Site';

  @override
  String get siteName => 'Nom de Site';

  @override
  String get noSites => 'Aucun site';

  @override
  String get userUpdated => '✅ Utilisateur mis à jour';

  @override
  String get deleteSite => 'Supprimer Site';

  @override
  String get configureUsers => 'Configurer Utilisateurs';

  @override
  String get configureStream => 'Configurer Flux';

  @override
  String managementTitle(String siteName) {
    return 'Gestion de Site - $siteName';
  }

  @override
  String groupLabel(String groupName) {
    return 'groupe: $groupName';
  }

  @override
  String get loginTitle => 'Visionnaire App';

  @override
  String get loginFailed => '❌ Échec de la connexion';

  @override
  String get loginRequired => 'Veuillez saisir le nom d\'utilisateur ou le courriel et le mot de passe';

  @override
  String get admin => 'Administrateur';

  @override
  String get user => 'Utilisateur';

  @override
  String get error => 'Erreur';

  @override
  String get success => 'Succès';

  @override
  String get warning => 'Avertissement';

  @override
  String get info => 'Information';

  @override
  String get loading => 'Chargement...';

  @override
  String get noData => 'Aucune donnée';

  @override
  String get refreshData => 'Actualiser les données';

  @override
  String get search => 'Rechercher';

  @override
  String get filter => 'Filtrer';

  @override
  String get selectAll => 'Tout sélectionner';

  @override
  String get clearSelection => 'Effacer la sélection';

  @override
  String get back => 'Retour';

  @override
  String get next => 'Suivant';

  @override
  String get previous => 'Précédent';

  @override
  String get finish => 'Terminer';

  @override
  String get close => 'Fermer';

  @override
  String get apiConfigTitle => 'Configuration API';

  @override
  String get loadConfigFailed => 'Échec du chargement de la configuration';

  @override
  String get customConfig => 'Personnalisé';

  @override
  String get copyToClipboard => 'Copier dans le presse-papiers';

  @override
  String get copiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get resetToDefault => 'Réinitialiser par défaut';

  @override
  String get apiUrlHint => 'Veuillez saisir l\'URL de l\'API';

  @override
  String get validUrlError => 'Veuillez saisir une URL valide';

  @override
  String defaultValue(String value) {
    return 'Valeur par défaut : $value';
  }

  @override
  String get refresh => 'Actualiser';

  @override
  String get resetAll => 'Tout réinitialiser aux valeurs par défaut';

  @override
  String get apiUrlLabel => 'URL de l\'API';

  @override
  String get roleUser => 'Utilisateur';

  @override
  String get roleGuest => 'Invité';

  @override
  String get roleAdmin => 'Administrateur';

  @override
  String errorMessage(String error) {
    return '❌ $error';
  }

  @override
  String get streamConfig => 'Configuration de Flux';

  @override
  String streamConfigTitle(String siteName) {
    return 'Configuration de Flux - $siteName';
  }

  @override
  String streamUsage(int used, int max) {
    return 'Utilisé $used / Limite $max';
  }

  @override
  String streamLimitReached(int maxStreams) {
    return '⚠️ Limite de flux atteinte ($maxStreams)';
  }

  @override
  String get addStream => 'Ajouter un Flux';

  @override
  String get streamName => 'Nom du Flux';

  @override
  String get rtspHttpUrl => 'URL RTSP / HTTP';

  @override
  String get modelKey => 'Clé du modèle';

  @override
  String get startHour => 'Heure de Début (0-23)';

  @override
  String get endHour => 'Heure de Fin (0-23)';

  @override
  String get recognitionEnabled => 'Activer le flux de reconnaissance';

  @override
  String get recognitionEnabledHint => 'Lorsqu’il est désactivé, la configuration est enregistrée, mais la reconnaissance n’est pas exécutée et le flux est masqué du mur en direct.';

  @override
  String get expireDate => 'Date d\'Expiration (optionnel)';

  @override
  String get notSet => 'Non Défini';

  @override
  String editStream(String streamName) {
    return 'Modifier - $streamName';
  }

  @override
  String get deleteStream => 'Supprimer le Flux';

  @override
  String get deleteStreamConfirmation => 'Êtes-vous sûr ? Cette action ne peut pas être annulée';

  @override
  String get streamAdded => '✅ Flux ajouté';

  @override
  String get streamUpdated => '✅ Mis à jour';

  @override
  String get streamDeleted => '✅ Supprimé';

  @override
  String get noStreamConfigs => 'Aucune configuration de flux';

  @override
  String get editTooltip => 'Éditer';

  @override
  String get deleteTooltip => 'Supprimer';

  @override
  String get noSafetyVestOrHelmet => 'Pas de Gilet/Casque de Sécurité';

  @override
  String get nearMachineryOrVehicle => 'Près de Machines/Véhicules';

  @override
  String get inRestrictedArea => 'Dans Zone Restreinte';

  @override
  String get inUtilityPoleArea => 'Dans Zone de Poteau Électrique';

  @override
  String get machineryNearPole => 'Machines Près du Poteau';

  @override
  String get expiryDate => 'Date d\'Expiration (optionnel)';

  @override
  String get noStreamConfig => 'Aucune configuration de flux';

  @override
  String get fileManagement => 'Gestion de Fichiers';

  @override
  String get apiConfiguration => 'Configuration API';

  @override
  String get loadingApiConfig => 'Chargement de la configuration API...';

  @override
  String get apiConfigStatus => 'État de la Configuration API';

  @override
  String customConfigCount(Object count) {
    return '$count Personnalisée(s)';
  }

  @override
  String get usingDefaults => 'Utilise les Valeurs par Défaut';

  @override
  String customApiEndpointsMessage(Object count) {
    return 'Vous avez personnalisé $count URL de points de terminaison API.';
  }

  @override
  String get allEndpointsUseDefaults => 'Tous les points de terminaison API utilisent les URL par défaut.';

  @override
  String get apiEndpointDetails => 'Détails des Points de Terminaison API';

  @override
  String get chatApiDescription => 'Service API de conversation de chat';

  @override
  String get detectionApiDescription => 'Service API de détection d\'objets';

  @override
  String get managementApiDescription => 'Service API de gestion système';

  @override
  String get notificationApiDescription => 'Service API de notifications push';

  @override
  String get streamingApiDescription => 'Service API de streaming média';

  @override
  String get fileManagementApiDescription => 'Service API de gestion de fichiers';

  @override
  String get violationRecordsApiDescription => 'Service API d\'enregistrements de violations';

  @override
  String get apiService => 'Service API';

  @override
  String welcomeUser(String username) {
    return 'Bienvenue, $username !';
  }

  @override
  String roleLabel(String role) {
    return 'Rôle : $role';
  }

  @override
  String get guestUser => 'Utilisateur invité';

  @override
  String get pleaseLogin => 'Veuillez vous connecter pour accéder aux fonctionnalités';

  @override
  String get downloadImage => 'Télécharger l\'image';

  @override
  String get copyImage => 'Copier l\'image';

  @override
  String get shareImage => 'Partager le lien';

  @override
  String get imageDownloaded => 'Image téléchargée sur l\'appareil';

  @override
  String get imageSavedToGallery => 'Image sauvegardée dans la galerie photos';

  @override
  String get imageCopied => 'Image copiée dans le presse-papiers';

  @override
  String get downloadFailed => 'Téléchargement échoué';

  @override
  String get copyFailed => 'Copie échouée';

  @override
  String get shareFailed => 'Partage échoué';

  @override
  String get signupConsentMissingError => 'Please accept all required consent items.';

  @override
  String get signUp => 'Sign up';

  @override
  String get requiredField => 'Required';

  @override
  String get confirmPassword => 'Confirm password';

  @override
  String get passwordMismatch => 'Passwords do not match';

  @override
  String get signupLegalFallbackNotice => 'Using the bundled legal text for now; accepted versions will still be submitted.';

  @override
  String get signupTermsTitle => 'Terms of Service';

  @override
  String get signupTermsContent => 'Visionnaire provides construction safety records, detection review, notification, document, and collaboration features. Users must provide accurate account information, protect their credentials, and use the service only for authorized work purposes. AI detection and system alerts are assistive tools and do not replace on-site safety management, professional judgment, or legal responsibilities. Misuse, unauthorized access, reverse engineering, data scraping, or unlawful content is prohibited.';

  @override
  String get signupPrivacyTitle => 'Privacy Policy';

  @override
  String get signupPrivacyContent => 'Visionnaire may collect account profile data, worksite and group information, camera stream metadata, violation records, images, review notes, device tokens, IP address, user agent, and usage logs. Data is used to provide safety detection, review workflows, notifications, audit trails, security, maintenance, and service improvement. Data may be processed through cloud infrastructure, Firebase Cloud Messaging, and authorized AI services according to organizational settings.';

  @override
  String get signupAiTermsTitle => 'LLM and AI Agent Terms';

  @override
  String get signupAiTermsContent => 'LLM and AI Agent outputs are generated assistance and may be incomplete, inaccurate, or outdated. Users must independently verify outputs before using them for safety, compliance, legal, financial, or operational decisions. Do not submit confidential, sensitive, personal, or unlawful information unless your organization has authorized that use. Prompts, files, context, outputs, and actions may be logged for service delivery, security, audit, and improvement.';

  @override
  String get signupSocialTitle => 'Quick signup with a social account';

  @override
  String get signupSocialSubtitle => 'If a new account is created, verify your email first, then wait for administrator approval.';

  @override
  String get signupSubmittedTitle => 'Verify your email';

  @override
  String get signupSubmittedMessage => 'Your request has been submitted. We sent a one-time verification link that expires automatically. After verification, your account will wait for administrator approval.';

  @override
  String get signupConsentTitle => 'Required consent';

  @override
  String get signupAcceptTermsPrivacyPrefix => 'I have read and agree to';

  @override
  String get signupConsentAnd => 'and';

  @override
  String get signupAcceptNotifications => 'I agree to receive safety alerts and review notifications';

  @override
  String get signupAcceptAiTermsPrefix => 'I understand and agree to the';

  @override
  String get signupConsentRequirement => 'All three consent items are required before submitting.';

  @override
  String get emailVerificationTitle => 'Verify email';

  @override
  String get emailVerificationChecking => 'Checking your verification link. This link can only be used once and expires automatically.';

  @override
  String get emailVerificationMissingOrInvalid => 'This verification link is invalid or missing a token. You can send a new email.';

  @override
  String get emailVerificationExpired => 'This verification link has expired. Send a new verification email.';

  @override
  String get emailVerificationUsed => 'This verification link has already been used. If you still cannot login, send a new email or contact an administrator.';

  @override
  String get emailVerificationGenericError => 'Something went wrong while verifying your email.';

  @override
  String get emailVerificationVerified => 'Your email is verified. Please return to login.';

  @override
  String get emailVerificationPendingApproval => 'Your email is verified. Your account is waiting for administrator approval.';

  @override
  String get emailVerificationEnterEmail => 'Enter the email used for registration.';

  @override
  String get emailVerificationResend => 'Resend verification email';

  @override
  String get emailVerificationResendSent => 'If this email is registered and not yet verified, a verification email has been sent.';

  @override
  String get notificationDiagnosticsTitle => 'Notification check';

  @override
  String get notificationMissingUserId => 'Missing user ID. Please sign in again.';

  @override
  String get notificationTokenUploaded => 'FCM token uploaded.';

  @override
  String get notificationSignInBeforeTest => 'Please sign in before sending a test notification.';

  @override
  String get notificationTestSent => 'Test notification sent.';

  @override
  String get notificationFirebaseLabel => 'Firebase';

  @override
  String get notificationConfigured => 'Configured';

  @override
  String get notificationNotConfigured => 'Not configured';

  @override
  String get notificationPermission => 'Permission';

  @override
  String get notificationLastUpload => 'Last upload';

  @override
  String get notificationMissing => 'Missing';

  @override
  String get notificationServiceWorker => 'Service worker';

  @override
  String get notificationUploadToken => 'Upload token';

  @override
  String get notificationTestNotification => 'Test notification';

  @override
  String get notificationCenterTitle => 'Notification center';

  @override
  String notificationLoadMoreFailed(String error) {
    return 'Failed to load more notifications: $error';
  }

  @override
  String notificationMarkReadFailed(String error) {
    return 'Failed to mark notification as read: $error';
  }

  @override
  String notificationMarkAllReadFailed(String error) {
    return 'Failed to mark all notifications as read: $error';
  }

  @override
  String notificationOpenFailed(String error) {
    return 'Unable to open notification link: $error';
  }

  @override
  String get notificationFilterAll => 'All';

  @override
  String get notificationFilterUnread => 'Unread';

  @override
  String get notificationFilterSignature => 'Signature';

  @override
  String get notificationFilterViolation => 'Violation';

  @override
  String get notificationFilterDocument => 'Document';

  @override
  String get notificationFilterSystem => 'System';

  @override
  String get notificationJustNow => 'Just now';

  @override
  String notificationMinutesAgo(int minutes) {
    return '$minutes minutes ago';
  }

  @override
  String notificationHoursAgo(int hours) {
    return '$hours hours ago';
  }

  @override
  String notificationDaysAgo(int days) {
    return '$days days ago';
  }

  @override
  String get notificationMarkAllRead => 'Mark all as read';

  @override
  String notificationUnreadCount(int count) {
    return '$count unread';
  }

  @override
  String get notificationNoUnread => 'No unread';

  @override
  String get notificationEmpty => 'No notifications yet';

  @override
  String get notificationLoadFailed => 'Failed to load notifications';

  @override
  String get notificationFallbackTitle => 'Notification';

  @override
  String get violationNoMatchingRecords => 'No matching records';

  @override
  String get violationRecordsTab => 'Records';

  @override
  String get violationAnalyticsTab => 'Analytics';

  @override
  String get violationGroup => 'Group';

  @override
  String get violationAllGroups => 'All groups';

  @override
  String get violationRangeLastDay => 'Last day';

  @override
  String get violationRangeLast30Days => '30 days';

  @override
  String get violationRangeLastHalfYear => '6 months';

  @override
  String get violationRangeLastYear => '1 year';

  @override
  String get violationRangeYearToDate => 'YTD';

  @override
  String get violationUnnamedGroup => 'Unnamed group';

  @override
  String get reviewFilterAll => 'All';

  @override
  String get reviewFilterFlagged => 'Flagged';

  @override
  String get reviewFilterPending => 'Pending';

  @override
  String get reviewFilterResolved => 'Resolved';

  @override
  String get reviewFilterDismissed => 'Dismissed';

  @override
  String get reviewStatusReviewed => 'Reviewed';

  @override
  String get reviewStatusNotSubmitted => 'Not submitted';

  @override
  String get reviewFlagReasonLabel => 'Flag reason';

  @override
  String get reviewSectionTitle => 'Review';

  @override
  String get reviewFlaggedBadge => 'Flagged';

  @override
  String get reviewPendingNote => 'Pending note';

  @override
  String get reviewNote => 'Review note';

  @override
  String get reviewHandled => 'Handled';

  @override
  String get reviewNoteOptional => 'Review note, optional';

  @override
  String get reviewAuditTrail => 'Audit trail';

  @override
  String reviewAuditTrailLoadFailed(String error) {
    return 'Unable to load audit trail: $error';
  }

  @override
  String get reviewAuditTrailEmpty => 'No audit trail yet.';

  @override
  String get overlayLabel => 'Overlay';

  @override
  String get overlayHidden => 'Off';

  @override
  String get overlayAll => 'All';

  @override
  String get overlayFlaggedOnly => 'Flagged only';

  @override
  String get reviewChangeMarkerColor => 'Change marker color';

  @override
  String get reviewActionResolve => 'Resolve';

  @override
  String get reviewActionDismiss => 'Dismiss';

  @override
  String get reviewActionPending => 'Set pending';

  @override
  String get reviewMissingRecordUpdate => 'Unable to update review because the record ID is missing.';

  @override
  String get reviewSignInRequiredUpdate => 'You must be signed in to update review status.';

  @override
  String get reviewUpdated => 'Review status updated.';

  @override
  String get reviewUpdatedNext => 'Review updated. Moving to the next pending item.';

  @override
  String reviewUpdateFailed(String error) {
    return 'Failed to update review: $error';
  }

  @override
  String get reviewReasonFalsePositive => 'False positive: the detection was reported as incorrect';

  @override
  String get reviewReasonFalseNegative => 'Missed detection: an object was missing from the results';

  @override
  String get reviewReasonWrongClass => 'Wrong class: the detection label needs correction';

  @override
  String get reviewReasonBadBox => 'Bad box: the bounding box needs correction';

  @override
  String get detectionFeedbackTitle => 'Detection feedback';

  @override
  String get detectionFeedbackDescription => 'Mark false positives or missed detections for model improvement review.';

  @override
  String get detectionFeedbackFalsePositive => 'Mark wrong';

  @override
  String get detectionFeedbackMissed => 'Draw missed';

  @override
  String get detectionFeedbackNoBoxes => 'No detection boxes are available to select.';

  @override
  String get detectionFeedbackMissedLabel => 'Missed label';

  @override
  String get detectionFeedbackNoteOptional => 'Note, optional';

  @override
  String get detectionFeedbackNoMissedTarget => 'No missed target selected';

  @override
  String detectionFeedbackSelectedBox(String bbox) {
    return 'Selected $bbox';
  }

  @override
  String get detectionFeedbackSubmitMissed => 'Submit missed';

  @override
  String get detectionFeedbackFalsePositiveHint => 'Tap the wrong detection box in the image.';

  @override
  String get detectionFeedbackMissedHint => 'Drag on the image to draw the missed target.';

  @override
  String get detectionFeedbackBoxes => 'Boxes';

  @override
  String get feedbackNoDetectionSelected => 'No detection box was selected. Tap inside a box.';

  @override
  String get feedbackSelectionTooSmall => 'The selected area is too small. Please draw it again.';

  @override
  String get feedbackFalsePositiveDialogTitle => 'Report false positive';

  @override
  String get feedbackFalsePositiveDialogMessage => 'This detection will be marked as a false positive for review.';

  @override
  String get feedbackDrawMissedFirst => 'Draw the missed target in the image first.';

  @override
  String get feedbackMissingRecord => 'Unable to submit feedback because the record ID is missing.';

  @override
  String get feedbackSignInRequired => 'You must be signed in to submit feedback.';

  @override
  String get feedbackSubmitted => 'Feedback submitted. Thank you.';

  @override
  String feedbackSubmitFailed(String error) {
    return 'Failed to submit feedback: $error';
  }

  @override
  String get imageViewerTitle => 'Image viewer';

  @override
  String get imageViewerRotate => 'Rotate';

  @override
  String get imageViewerResetZoom => 'Reset zoom';

  @override
  String get falsePositivePickerTitle => 'Select wrong detection';

  @override
  String get falsePositivePickerHint => 'Double tap to zoom, pan, then tap a box or label.';

  @override
  String get falsePositivePickerBottomHint => 'Tap a highlighted box or label to report';

  @override
  String get falsePositivePickerMiss => 'Tap a box or label. Zoom in if needed.';

  @override
  String get saveSuccess => 'Saved successfully.';

  @override
  String get editAuditFixDocTitle => 'Edit audit improvement document';

  @override
  String get addAuditFixDocTitle => 'Add audit improvement document';

  @override
  String get multiSelectAlbum => 'Select from album';

  @override
  String get auditDateLabel => 'Audit date';

  @override
  String todayLabel(String date) {
    return 'Today: $date';
  }

  @override
  String get addPhotoViaCamera => 'Add photos with camera or album';

  @override
  String get showDateLabel => 'Show date stamp';

  @override
  String get dateLabel => 'Date';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get descBeforeLabel => 'Before improvement';

  @override
  String get descDuringLabel => 'During improvement';

  @override
  String get descAfterLabel => 'After improvement';

  @override
  String groupNumberLabel(String number) {
    return 'Group $number';
  }

  @override
  String get applyDescriptionToAllGroups => 'Apply description to following groups';

  @override
  String doneWithCount(String count) {
    return 'Done ($count)';
  }

  @override
  String loadFailedError(String error) {
    return 'Load failed: $error';
  }

  @override
  String get tryAgain => 'Try again';

  @override
  String pleaseSelectSignerFor(String field) {
    return 'Please select a signer for $field';
  }

  @override
  String get submitted => 'Submitted';

  @override
  String failedWith(String error) {
    return 'Failed: $error';
  }

  @override
  String get editDocumentTitle => 'Edit document';

  @override
  String get headerSection => 'Header';

  @override
  String get bodySection => 'Body';

  @override
  String get footerSection => 'Footer';

  @override
  String get saveAndSubmit => 'Save and submit';

  @override
  String tableLabel(String number) {
    return 'Table $number';
  }

  @override
  String get unnamedSite => 'Unnamed site';

  @override
  String get addImage => 'Add image';

  @override
  String get tapToSign => 'Tap to sign';

  @override
  String get signatureSection => 'Signature';

  @override
  String get signatureFlow => 'Signature flow';

  @override
  String get orderedSigningActive => 'Ordered signing is active.';

  @override
  String get freeSigningActive => 'Any-order signing is active.';

  @override
  String get signingOrderLocked => 'Signing order is locked after tasks are created.';

  @override
  String get anyOrder => 'Any order';

  @override
  String get signInOrder => 'Sign in order';

  @override
  String get orderedSigningDragHint => 'Drag signers to adjust the signing order before submitting.';

  @override
  String get freeSigningHint => 'All assigned signers can sign without a fixed order.';

  @override
  String get selectSignerHint => 'Select signer';

  @override
  String orderRank(String rank) {
    return 'Order $rank';
  }

  @override
  String get signatureFieldLabel => 'Signature field';

  @override
  String commentLabel(String comment) {
    return 'Comment: $comment';
  }

  @override
  String get sitesNotLoaded => 'Sites have not been loaded yet.';

  @override
  String get documentListTitle => 'Documents';

  @override
  String get creatorLabel => 'Creator';

  @override
  String get editorLabel => 'Editor';

  @override
  String get signerLabel => 'Signer';

  @override
  String get selectSiteFirstHint => 'Select a site first to load members.';

  @override
  String get loadingMemberList => 'Loading members...';

  @override
  String memberLoadFailed(String error) {
    return 'Failed to load members: $error';
  }

  @override
  String get noMemberListForSite => 'No members are available for this site.';

  @override
  String get uploadButton => 'Upload';

  @override
  String allFilter(String label) {
    return 'All $label';
  }

  @override
  String get unclassified => 'Unclassified';

  @override
  String get documentLocked => 'Document locked';

  @override
  String get mySignTasks => 'My signature tasks';

  @override
  String get browserDownloadStarted => 'Browser download started.';

  @override
  String get storagePermissionRequired => 'Storage permission is required to download files.';

  @override
  String get downloadComplete => 'Download complete.';

  @override
  String downloadFailedError(String error) {
    return 'Download failed: $error';
  }

  @override
  String deleteVersionConfirm(String version) {
    return 'Delete version $version?';
  }

  @override
  String get versionDeleted => 'Version deleted.';

  @override
  String deleteVersionFailedError(String error) {
    return 'Failed to delete version: $error';
  }

  @override
  String documentVersionListTitle(String document) {
    return 'Versions for $document';
  }

  @override
  String versionNumber(String version) {
    return 'Version $version';
  }

  @override
  String get downloadDocx => 'Download DOCX';

  @override
  String get downloadPdf => 'Download PDF';

  @override
  String get pdfConverting => 'PDF converting';

  @override
  String get deleteVersionTooltip => 'Delete version';

  @override
  String get pdfNotReady => 'PDF is not ready yet';

  @override
  String get addPhotoDocTitle => 'Add photo document';

  @override
  String get editPhotoDocTitle => 'Edit photo document';

  @override
  String get requiredSelect => 'Please select an option';

  @override
  String get projectNameLabel => 'Project name';

  @override
  String get addPhotosHint => 'Take photos or select images from album.';

  @override
  String get locationLabel => 'Location';

  @override
  String get applyImageDataToAll => 'Apply image data to following items';

  @override
  String get notificationSettings => 'Notification settings';

  @override
  String get siteNotificationTitle => 'Site notifications';

  @override
  String get siteNotificationDescription => 'Choose which site alerts you want to receive.';

  @override
  String get noSiteNotification => 'No site notification items.';

  @override
  String get notificationSearchHint => 'Search notifications';

  @override
  String get siteNotificationSaveSuccess => 'Site notification settings saved.';

  @override
  String get documentNotificationTitle => 'Document notifications';

  @override
  String get documentNotificationDescription => 'Choose which document workflow notifications you want to receive.';

  @override
  String get noDocumentNotification => 'No document notification items.';

  @override
  String get documentNotificationSaveSuccess => 'Document notification settings saved.';

  @override
  String get siteNotificationChannel => 'Site alerts';

  @override
  String get documentNotificationChannel => 'Document workflow';

  @override
  String notificationSaveFailed(String error) {
    return 'Failed to save notification settings: $error';
  }

  @override
  String get notificationSearchEmpty => 'No notification settings match your search.';

  @override
  String get allSiteGroups => 'All site groups';

  @override
  String get notificationEnabled => 'Enabled';

  @override
  String get notificationPendingSave => 'Pending save';

  @override
  String get notificationStatus => 'Status';

  @override
  String get notificationSaving => 'Saving';

  @override
  String get notificationSynced => 'Synced';

  @override
  String get enableAllNotifications => 'Enable all';

  @override
  String get disableAllNotifications => 'Disable all';

  @override
  String get saveNotificationChanges => 'Save changes';

  @override
  String get notificationAlreadySynced => 'Already synced';

  @override
  String notificationEnabledCount(String enabled, String total) {
    return '$enabled/$total enabled';
  }

  @override
  String get notificationUnsaved => 'Unsaved changes';

  @override
  String get pendingSignStatus => 'Pending';

  @override
  String get signedStatus => 'Signed';

  @override
  String get commentedStatus => 'Commented';

  @override
  String get skippedStatus => 'Skipped';

  @override
  String get rejectedStatus => 'Rejected';

  @override
  String get commentedStatusDescription => 'Return with a comment for revision.';

  @override
  String get skippedStatusDescription => 'Skip this signature step.';

  @override
  String get rejectedStatusDescription => 'Reject and return the document.';

  @override
  String get signedStatusDescription => 'Sign and approve this step.';

  @override
  String get chooseDocumentTypeTitle => 'Choose document type';

  @override
  String get documentTypeSearchHint => 'Search document types';

  @override
  String get noAvailableCategories => 'No available categories';

  @override
  String get noMatchingDocumentTypes => 'No matching document types';

  @override
  String get documentTypePrefixUnset => 'Prefix not set';

  @override
  String documentTypePrefixValue(String prefix) {
    return 'Prefix: $prefix';
  }

  @override
  String get approveUser => 'Approve user';

  @override
  String get selectGroupForUser => 'Select a group for this user.';

  @override
  String get statusPending => 'Pending';

  @override
  String get pendingApprovalTitle => 'Pending approval';

  @override
  String get pendingApprovalMessage => 'Your account is waiting for administrator approval.';

  @override
  String get signDocument => 'Sign document';

  @override
  String get goToMyTasks => 'Go to my tasks';

  @override
  String loadSignTaskFailed(String error) {
    return 'Failed to load signature task: $error';
  }

  @override
  String get signTaskNotFound => 'Signature task not found.';

  @override
  String signTaskLoadFailed(String error) {
    return 'Failed to load signature task: $error';
  }

  @override
  String get pleaseSignFirst => 'Please sign before submitting.';

  @override
  String submitFailed(String error) {
    return 'Submit failed: $error';
  }

  @override
  String get documentVersionUpdated => 'Document version has been updated. Please reload.';

  @override
  String get revisionCommentLabel => 'Revision comment';

  @override
  String get revisionCommentHint => 'Describe what should be revised.';

  @override
  String get rejectionReasonLabel => 'Rejection reason';

  @override
  String get rejectionReasonHint => 'Describe why this document is rejected.';

  @override
  String get signAction => 'Sign';

  @override
  String get commentAction => 'Comment';

  @override
  String get skipAction => 'Skip';

  @override
  String get rejectAction => 'Reject';

  @override
  String get signResult => 'Signature result';

  @override
  String get handwrittenSignature => 'Handwritten signature';

  @override
  String get resignature => 'Sign again';

  @override
  String get signatureConfirmed => 'Signature confirmed.';

  @override
  String get confirmSignature => 'Confirm signature';

  @override
  String get signaturePreview => 'Signature preview';

  @override
  String get confirmSubmit => 'Confirm submit';

  @override
  String get startSign => 'Start signing';

  @override
  String get signatureHint => 'Please provide your signature.';

  @override
  String get noSignTasks => 'No signature tasks.';

  @override
  String get createdTime => 'Created';

  @override
  String taskNumberStatus(String taskId, String status) {
    return 'Task $taskId · $status';
  }

  @override
  String versionPlaceholder(String version, String placeholder) {
    return 'Version $version · $placeholder';
  }

  @override
  String pdfLoadFailed(String error) {
    return 'Failed to load PDF: $error';
  }

  @override
  String get commentRequired => 'Comment is required for this action.';
}
