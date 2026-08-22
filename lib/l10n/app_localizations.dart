import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_id.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_th.dart';
import 'app_localizations_vi.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
    Locale('id'),
    Locale('ja'),
    Locale('th'),
    Locale('vi'),
    Locale('zh'),
    Locale('zh', 'CN')
  ];

  /// The title of the application
  ///
  /// In en, this message translates to:
  /// **'Visionnaire Application'**
  String get appTitle;

  /// Region code for the device language
  ///
  /// In en, this message translates to:
  /// **'en-UK'**
  String get deviceLang;

  /// Login button text
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// Username field label
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// Password field label
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// Title of the chat list page
  ///
  /// In en, this message translates to:
  /// **'Chat List'**
  String get chatList;

  /// Error message when chat title is empty or whitespace only
  ///
  /// In en, this message translates to:
  /// **'Chat title cannot be empty or whitespace only'**
  String get chatTitleCannotBeEmpty;

  /// Title of the camera streams page
  ///
  /// In en, this message translates to:
  /// **'Camera Streams'**
  String get cameraList;

  /// Title of the object detection page
  ///
  /// In en, this message translates to:
  /// **'Object Detection'**
  String get detection;

  /// Text for the logout button
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// Text for the change language button
  ///
  /// In en, this message translates to:
  /// **'Change Language'**
  String get changeLanguage;

  /// Label for site
  ///
  /// In en, this message translates to:
  /// **'Site'**
  String get site;

  /// Label for stream
  ///
  /// In en, this message translates to:
  /// **'Stream'**
  String get stream;

  /// Label for detection time
  ///
  /// In en, this message translates to:
  /// **'Detection Time'**
  String get detectionTime;

  /// Label for violation message
  ///
  /// In en, this message translates to:
  /// **'Violation Message'**
  String get violationMessage;

  /// Error message when image fails to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load image'**
  String get loadingImageError;

  /// Title of the violation record query page
  ///
  /// In en, this message translates to:
  /// **'Violation Record Query'**
  String get violationRecordQuery;

  /// Hint text for keyword input
  ///
  /// In en, this message translates to:
  /// **'Keyword (stream_name or message)'**
  String get keyword;

  /// Label for start time
  ///
  /// In en, this message translates to:
  /// **'Start Time'**
  String get startTime;

  /// Label for end time
  ///
  /// In en, this message translates to:
  /// **'End Time'**
  String get endTime;

  /// Text for the query button
  ///
  /// In en, this message translates to:
  /// **'Query'**
  String get query;

  /// Text shown when no records are available
  ///
  /// In en, this message translates to:
  /// **'No records available'**
  String get noRecords;

  /// Title of the live monitoring page
  ///
  /// In en, this message translates to:
  /// **'Live Monitoring'**
  String get streamingWebSettings;

  /// Hint text for Streaming Web URL input
  ///
  /// In en, this message translates to:
  /// **'Streaming Web URL (with http:// or https://)'**
  String get streamingWebUrl;

  /// Save button
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Text for the button to go to the live monitoring locations page
  ///
  /// In en, this message translates to:
  /// **'Go to Locations'**
  String get goToLabels;

  /// Label for the current URL
  ///
  /// In en, this message translates to:
  /// **'Current URL'**
  String get currentUrl;

  /// Title of the live monitoring locations page
  ///
  /// In en, this message translates to:
  /// **'Locations'**
  String get labelList;

  /// Single label name
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get label;

  /// Text shown when no camera images are available
  ///
  /// In en, this message translates to:
  /// **'No camera images available'**
  String get noImage;

  /// Label for warnings section
  ///
  /// In en, this message translates to:
  /// **'Warnings'**
  String get warnings;

  /// Label for the last updated time
  ///
  /// In en, this message translates to:
  /// **'Last updated'**
  String get lastUpdated;

  /// Text shown when there are no warnings
  ///
  /// In en, this message translates to:
  /// **'No warnings'**
  String get noWarnings;

  /// Label for detection result section
  ///
  /// In en, this message translates to:
  /// **'Detection Result'**
  String get detectionResult;

  /// Label for model selection
  ///
  /// In en, this message translates to:
  /// **'Choose Model'**
  String get chooseModel;

  /// Text shown when no image has been selected
  ///
  /// In en, this message translates to:
  /// **'No image selected'**
  String get noImageSelected;

  /// Text shown when there is no detection result
  ///
  /// In en, this message translates to:
  /// **'No detection result'**
  String get noDetectionResult;

  /// Text for the take photo button
  ///
  /// In en, this message translates to:
  /// **'Take Photo'**
  String get takePhoto;

  /// Text for the photo library button
  ///
  /// In en, this message translates to:
  /// **'Photo Library'**
  String get photoLibrary;

  /// Text for the start detection button
  ///
  /// In en, this message translates to:
  /// **'Start Detection'**
  String get startDetection;

  /// Error message when camera cannot be opened
  ///
  /// In en, this message translates to:
  /// **'Cannot open camera'**
  String get cannotOpenCamera;

  /// Error message when gallery cannot be opened
  ///
  /// In en, this message translates to:
  /// **'Cannot open gallery'**
  String get cannotOpenGallery;

  /// Error message when failed to get image size
  ///
  /// In en, this message translates to:
  /// **'Failed to get image size'**
  String get getImageSizeFailed;

  /// Error message when not logged in or token is invalid
  ///
  /// In en, this message translates to:
  /// **'Not logged in (Detection service token invalid)'**
  String get notLoggedIn;

  /// Error message when token refresh fails
  ///
  /// In en, this message translates to:
  /// **'Token refresh failed'**
  String get tokenRefreshFailed;

  /// Error message when chat fails to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load chat'**
  String get chatLoadFailed;

  /// Title for the chat room page
  ///
  /// In en, this message translates to:
  /// **'Chat Room'**
  String get chatRoom;

  /// Placeholder text for message input
  ///
  /// In en, this message translates to:
  /// **'Enter message...'**
  String get inputMessage;

  /// Title for new chat room dialog
  ///
  /// In en, this message translates to:
  /// **'New Chat Room'**
  String get newChatRoom;

  /// Hint text for chat room title input
  ///
  /// In en, this message translates to:
  /// **'Enter chat room title'**
  String get enterChatRoomTitle;

  /// Text for the create button
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// Error message when chat room creation fails
  ///
  /// In en, this message translates to:
  /// **'Creation failed'**
  String get createFailed;

  /// Confirmation message for chat room deletion
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this chat room?'**
  String get confirmDeleteChatRoom;

  /// Cancel button
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Delete button
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Error message when chat room deletion fails
  ///
  /// In en, this message translates to:
  /// **'Deletion failed'**
  String get deleteFailed;

  /// Hint text for site selection dropdown
  ///
  /// In en, this message translates to:
  /// **'Select Site'**
  String get selectSite;

  /// Text shown when nothing is selected
  ///
  /// In en, this message translates to:
  /// **'Not selected'**
  String get notSelected;

  /// Error message prefix
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorPrefix(String error);

  /// Prefix label for site name
  ///
  /// In en, this message translates to:
  /// **'Site: '**
  String get sitePrefix;

  /// Prefix label for stream name
  ///
  /// In en, this message translates to:
  /// **'Stream: '**
  String get streamPrefix;

  /// Prefix label for detection time
  ///
  /// In en, this message translates to:
  /// **'Detection Time: '**
  String get detectionTimePrefix;

  /// Message displayed when the Streaming Web Base URL has been updated
  ///
  /// In en, this message translates to:
  /// **'Updated Streaming Web Base URL to:'**
  String get urlUpdated;

  /// Title for the live monitoring locations index page
  ///
  /// In en, this message translates to:
  /// **'Locations'**
  String get streamingWebIndexTitle;

  /// Default error message when error information is not available
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get unknownError;

  /// Text shown when there are no label data
  ///
  /// In en, this message translates to:
  /// **'No labels available'**
  String get noLabels;

  /// Error message when chat message is empty
  ///
  /// In en, this message translates to:
  /// **'Chat message cannot be empty'**
  String get chatMessageCannotBeEmpty;

  /// Hint text for editing question
  ///
  /// In en, this message translates to:
  /// **'Please enter the new question'**
  String get editQuestionHint;

  /// Text for the confirm button in dialog
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// Text for the edit question button
  ///
  /// In en, this message translates to:
  /// **'Edit Question'**
  String get editQuestion;

  /// Text for the regenerate answer button
  ///
  /// In en, this message translates to:
  /// **'Regenerate Answer'**
  String get regenerateAnswer;

  /// Text for the remove question button
  ///
  /// In en, this message translates to:
  /// **'Remove Question (with subsequent dialog)'**
  String get removeQuestionChain;

  /// Error message when history fails to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load history'**
  String get failedToLoadHistory;

  /// Error message when history fails to load after refresh
  ///
  /// In en, this message translates to:
  /// **'Failed to load history after refresh'**
  String get failedToLoadHistoryAfterRefresh;

  /// Error message when asking fails after refresh
  ///
  /// In en, this message translates to:
  /// **'Failed to ask after refresh'**
  String get failedToAskAfterRefresh;

  /// Error message when editing fails
  ///
  /// In en, this message translates to:
  /// **'Edit failed'**
  String get editFailed;

  /// Error message when editing fails after refresh
  ///
  /// In en, this message translates to:
  /// **'Edit failed after refresh'**
  String get editFailedAfterRefresh;

  /// Error message when regeneration fails
  ///
  /// In en, this message translates to:
  /// **'Regenerate failed'**
  String get regenerateFailed;

  /// Error message when regeneration fails after refresh
  ///
  /// In en, this message translates to:
  /// **'Regenerate failed after refresh'**
  String get regenerateFailedAfterRefresh;

  /// Error message when removal fails
  ///
  /// In en, this message translates to:
  /// **'Remove failed'**
  String get removeFailed;

  /// Error message when removal fails after refresh
  ///
  /// In en, this message translates to:
  /// **'Remove failed after refresh'**
  String get removeFailedAfterRefresh;

  /// Tooltip and button text for sending a chat message
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get sendMessage;

  /// Tooltip for adding images to a chat message
  ///
  /// In en, this message translates to:
  /// **'Add images'**
  String get addImages;

  /// Tooltip for adding files to a chat message
  ///
  /// In en, this message translates to:
  /// **'Add files'**
  String get addFiles;

  /// Label showing how many attachments are pending in chat input
  ///
  /// In en, this message translates to:
  /// **'{count} attachments'**
  String attachmentCount(int count);

  /// Tooltip for canceling active answer generation
  ///
  /// In en, this message translates to:
  /// **'Cancel generation'**
  String get cancelGeneration;

  /// Tooltip for creating a new chat room from the input area
  ///
  /// In en, this message translates to:
  /// **'Create chat room'**
  String get createChatRoom;

  /// Error message when a chat attachment upload fails
  ///
  /// In en, this message translates to:
  /// **'Attachment upload failed: {error}'**
  String attachmentUploadFailed(String error);

  /// Error message when deleting a chat attachment fails
  ///
  /// In en, this message translates to:
  /// **'Attachment deletion failed: {error}'**
  String attachmentDeleteFailed(String error);

  /// Empty state text for desktop streaming label pane
  ///
  /// In en, this message translates to:
  /// **'Select a label'**
  String get selectLabel;

  /// Label for toggling object detection overlay on streams
  ///
  /// In en, this message translates to:
  /// **'Show detection results'**
  String get showDetectionResults;

  /// Label for hardhat
  ///
  /// In en, this message translates to:
  /// **'Hardhat'**
  String get hardhat;

  /// Label for vest
  ///
  /// In en, this message translates to:
  /// **'Vest'**
  String get vest;

  /// Label for machinery
  ///
  /// In en, this message translates to:
  /// **'Machinery'**
  String get machinery;

  /// Label for vehicle
  ///
  /// In en, this message translates to:
  /// **'Vehicle'**
  String get vehicle;

  /// Label for no hardhat
  ///
  /// In en, this message translates to:
  /// **'No Hardhat'**
  String get no_hardhat;

  /// Label for no vest
  ///
  /// In en, this message translates to:
  /// **'No Vest'**
  String get no_vest;

  /// Label for person
  ///
  /// In en, this message translates to:
  /// **'Person'**
  String get person;

  /// Label for safety cone
  ///
  /// In en, this message translates to:
  /// **'Safety Cone'**
  String get cone;

  /// Label for mask
  ///
  /// In en, this message translates to:
  /// **'Mask'**
  String get mask;

  /// Label for no mask
  ///
  /// In en, this message translates to:
  /// **'No Mask'**
  String get no_mask;

  /// Label for utility pole
  ///
  /// In en, this message translates to:
  /// **'Utility Pole'**
  String get utility_pole;

  /// Warning message for people entering the controlled zone
  ///
  /// In en, this message translates to:
  /// **'Warning: {count} people have entered the controlled area!'**
  String warning_people_in_controlled_area(int count);

  /// Warning message for people entering the utility pole controlled area
  ///
  /// In en, this message translates to:
  /// **'Warning: {count} people have entered the utility pole restricted area!'**
  String warning_people_in_utility_pole_controlled_area(int count);

  /// Warning message for missing hardhat
  ///
  /// In en, this message translates to:
  /// **'Warning: {count} people are not wearing a hardhat!'**
  String warning_no_hardhat(int count);

  /// Warning message for missing safety vest
  ///
  /// In en, this message translates to:
  /// **'Warning: {count} people are not wearing a safety vest!'**
  String warning_no_safety_vest(int count);

  /// Warning message for people close to machinery
  ///
  /// In en, this message translates to:
  /// **'Warning: {count} people are too close to machinery!'**
  String warning_close_to_machinery(int count);

  /// Warning message for people close to vehicles
  ///
  /// In en, this message translates to:
  /// **'Warning: {count} people are too close to vehicles!'**
  String warning_close_to_vehicle(int count);

  /// Warning message for machinery close to the utility pole
  ///
  /// In en, this message translates to:
  /// **'Warning: {count} machinery are too close to the utility pole!'**
  String detect_machinery_close_to_pole(int count);

  /// Text for the show overlay button
  ///
  /// In en, this message translates to:
  /// **'Show Overlay'**
  String get showOverlay;

  /// Add button
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// Edit title prefix
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Text for the submit button
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// Text for the create button
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get build;

  /// Text shown while saving
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// Text for the save configuration button
  ///
  /// In en, this message translates to:
  /// **'Save Configuration'**
  String get saveConfig;

  /// Message shown when configuration is saved successfully
  ///
  /// In en, this message translates to:
  /// **'Configuration saved successfully'**
  String get configSavedSuccessfully;

  /// Message shown when configuration save fails
  ///
  /// In en, this message translates to:
  /// **'Failed to save configuration'**
  String get saveConfigFailed;

  /// Confirmation message for resetting all configurations
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to reset all API configurations to default values? This action cannot be undone.'**
  String get confirmResetAllConfigs;

  /// Confirmation message for resetting a single configuration
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to reset {name} to default values?'**
  String confirmResetConfig(String name);

  /// Title for delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete?'**
  String get confirmDelete;

  /// Warning message for permanent deletion
  ///
  /// In en, this message translates to:
  /// **'Will permanently delete \"{name}\". This action cannot be undone!'**
  String permanentDeleteWarning(String name);

  /// Warning message for deletion
  ///
  /// In en, this message translates to:
  /// **'Will delete \"{name}\". This action cannot be undone.'**
  String deleteWarning(String name);

  /// Message shown when site is created successfully
  ///
  /// In en, this message translates to:
  /// **'✅ Site created'**
  String get siteCreated;

  /// Delete success message
  ///
  /// In en, this message translates to:
  /// **'✅ Deleted'**
  String get deleted;

  /// Message shown when item is added successfully
  ///
  /// In en, this message translates to:
  /// **'✅ Added'**
  String get added;

  /// Message shown when feature is added successfully
  ///
  /// In en, this message translates to:
  /// **'✅ Feature added'**
  String get featureAdded;

  /// Title for edit feature dialog
  ///
  /// In en, this message translates to:
  /// **'Edit \"{name}\"'**
  String editFeature(String name);

  /// Title for edit user dialog
  ///
  /// In en, this message translates to:
  /// **'Edit \"{username}\"'**
  String editUser(String username);

  /// Title for add user form
  ///
  /// In en, this message translates to:
  /// **'Add User'**
  String get addUser;

  /// Text for the add feature button
  ///
  /// In en, this message translates to:
  /// **'Add Feature'**
  String get addFeature;

  /// Title for add group form
  ///
  /// In en, this message translates to:
  /// **'Add Group'**
  String get addGroup;

  /// Title for edit group dialog
  ///
  /// In en, this message translates to:
  /// **'Edit Group'**
  String get editGroup;

  /// Title for file delete confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete'**
  String get confirmDeleteFile;

  /// Message for file delete confirmation
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this file?'**
  String get confirmDeleteFileMessage;

  /// Message shown when file is deleted successfully
  ///
  /// In en, this message translates to:
  /// **'File deleted'**
  String get fileDeleted;

  /// Message shown when file deletion fails
  ///
  /// In en, this message translates to:
  /// **'Delete failed'**
  String get deleteFileFailed;

  /// Title for create audit document page
  ///
  /// In en, this message translates to:
  /// **'Create Audit Improvement Document'**
  String get createAuditDoc;

  /// Text for the create DOCX button
  ///
  /// In en, this message translates to:
  /// **'Create DOCX'**
  String get createDocx;

  /// Prompt text for adding photos
  ///
  /// In en, this message translates to:
  /// **'Please add photos by taking photos or from album'**
  String get addPhotoPrompt;

  /// Message shown when creation fails
  ///
  /// In en, this message translates to:
  /// **'Creation failed: {error}'**
  String createFailedWith(String error);

  /// Text for add file tooltip
  ///
  /// In en, this message translates to:
  /// **'Add File'**
  String get addFile;

  /// Message when no changes are detected in configuration
  ///
  /// In en, this message translates to:
  /// **'No configuration changes detected'**
  String get noConfigChangesDetected;

  /// Button text to reset all configurations to default values
  ///
  /// In en, this message translates to:
  /// **'Reset to Defaults'**
  String get resetToDefaults;

  /// Success message after resetting configuration
  ///
  /// In en, this message translates to:
  /// **'Reset to default configuration'**
  String get resetSuccess;

  /// Error message when reset operation fails
  ///
  /// In en, this message translates to:
  /// **'Reset failed'**
  String get resetFailed;

  /// Success message after resetting a specific endpoint
  ///
  /// In en, this message translates to:
  /// **'Reset {name} successfully'**
  String resetEndpointSuccess(String name);

  /// Dialog title for resetting a specific endpoint
  ///
  /// In en, this message translates to:
  /// **'Reset {name}'**
  String resetEndpoint(String name);

  /// Error message for not logged in or invalid token
  ///
  /// In en, this message translates to:
  /// **'Not logged in or invalid token'**
  String get notLoggedInOrInvalidToken;

  /// Error message for upload failure
  ///
  /// In en, this message translates to:
  /// **'Upload failed: {error}'**
  String uploadFailed(String error);

  /// Message to wait for site list loading
  ///
  /// In en, this message translates to:
  /// **'Site list not yet loaded, please wait'**
  String get pleaseWaitForSiteList;

  /// Title for select construction site dialog
  ///
  /// In en, this message translates to:
  /// **'Select Construction Site'**
  String get selectConstructionSite;

  /// All sites option
  ///
  /// In en, this message translates to:
  /// **'All Sites'**
  String get allSites;

  /// Start date label
  ///
  /// In en, this message translates to:
  /// **'Start Date'**
  String get startDate;

  /// End date label
  ///
  /// In en, this message translates to:
  /// **'End Date'**
  String get endDate;

  /// Versions option
  ///
  /// In en, this message translates to:
  /// **'Versions'**
  String get versions;

  /// Error message for unconfigured file type
  ///
  /// In en, this message translates to:
  /// **'This file type has no file_prefix configured, cannot use template'**
  String get fileTypeNotConfigured;

  /// Message shown when there are no users
  ///
  /// In en, this message translates to:
  /// **'No users yet'**
  String get noUsers;

  /// Format for displaying user information
  ///
  /// In en, this message translates to:
  /// **'Name: {name} | Email: {email} | Role: {role} | Group: {group}'**
  String nameDisplay(String name, String email, String role, String group);

  /// Text for deactivate button
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get deactivate;

  /// Text for activate button
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get activate;

  /// Message for permission denied
  ///
  /// In en, this message translates to:
  /// **'Permission denied'**
  String get permissionDenied;

  /// User management menu item
  ///
  /// In en, this message translates to:
  /// **'User Management'**
  String get userManagement;

  /// Label for account/username field
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// Label for family name field
  ///
  /// In en, this message translates to:
  /// **'Family Name'**
  String get familyName;

  /// Label for middle name field
  ///
  /// In en, this message translates to:
  /// **'Middle Name'**
  String get middleName;

  /// Label for given name field
  ///
  /// In en, this message translates to:
  /// **'Given Name'**
  String get givenName;

  /// Label for email field
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// Label for mobile field
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get mobile;

  /// Label for reset password field
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get resetPassword;

  /// Label for role field
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// Label for group field
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get group;

  /// Form validation error: required
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// Validation message for invalid email format
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get emailFormatError;

  /// Validation message for group selection
  ///
  /// In en, this message translates to:
  /// **'Please select a group'**
  String get selectGroup;

  /// Label for optional mobile field
  ///
  /// In en, this message translates to:
  /// **'Mobile (Optional)'**
  String get mobileOptional;

  /// Label for optional middle name field
  ///
  /// In en, this message translates to:
  /// **'Middle Name (Optional)'**
  String get middleNameOptional;

  /// Update success message
  ///
  /// In en, this message translates to:
  /// **'✅ Updated'**
  String get updated;

  /// API configuration title
  ///
  /// In en, this message translates to:
  /// **'API Configuration'**
  String get apiConfig;

  /// Custom option
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @deleteFeatureConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Will delete feature \\\"{name}\\\". This action cannot be undone.'**
  String deleteFeatureConfirmation(Object name);

  /// No description provided for @assignGroups.
  ///
  /// In en, this message translates to:
  /// **'Assign Groups - {name}'**
  String assignGroups(Object name);

  /// Tooltip text for setting groups
  ///
  /// In en, this message translates to:
  /// **'Set Groups'**
  String get setGroups;

  /// Reload button text
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// Copy button text
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// Password change success message
  ///
  /// In en, this message translates to:
  /// **'✅ Password changed, please login again with new password'**
  String get passwordChanged;

  /// Old password field label
  ///
  /// In en, this message translates to:
  /// **'Old Password'**
  String get oldPassword;

  /// New password field label
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// Please login first prompt
  ///
  /// In en, this message translates to:
  /// **'Please login first'**
  String get pleaseLoginFirst;

  /// Change password menu item
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// Minimum password length validation message
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get minimumPasswordLength;

  /// Feature management menu item
  ///
  /// In en, this message translates to:
  /// **'Feature Management'**
  String get featureManagement;

  /// Feature name field label
  ///
  /// In en, this message translates to:
  /// **'Feature Name'**
  String get featureName;

  /// Description optional field label
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptional;

  /// Assign group title
  ///
  /// In en, this message translates to:
  /// **'Assign Group - {name}'**
  String assignGroup(String name);

  /// No features message
  ///
  /// In en, this message translates to:
  /// **'No features'**
  String get noFeatures;

  /// Group permissions update success message
  ///
  /// In en, this message translates to:
  /// **'✅ Group permissions updated'**
  String get groupPermissionsUpdated;

  /// Set group button text
  ///
  /// In en, this message translates to:
  /// **'Set Group'**
  String get setGroup;

  /// Group management menu item
  ///
  /// In en, this message translates to:
  /// **'Group Management'**
  String get groupManagement;

  /// Group name field label
  ///
  /// In en, this message translates to:
  /// **'Group Name'**
  String get groupName;

  /// Uniform number field label
  ///
  /// In en, this message translates to:
  /// **'Uniform Number (8 digits)'**
  String get uniformNumber;

  /// Uniform number format error message
  ///
  /// In en, this message translates to:
  /// **'Uniform number requires 8 digits'**
  String get uniformNumberError;

  /// No groups message
  ///
  /// In en, this message translates to:
  /// **'No groups'**
  String get noGroups;

  /// Uniform number display label
  ///
  /// In en, this message translates to:
  /// **'Uniform: {uniformNumber}'**
  String uniformLabel(String uniformNumber);

  /// Uniform number validation error message
  ///
  /// In en, this message translates to:
  /// **'Must be 8 digits'**
  String get uniformNumberValidation;

  /// Name field label
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// Site management menu item
  ///
  /// In en, this message translates to:
  /// **'Site Management'**
  String get siteManagement;

  /// Site name field label
  ///
  /// In en, this message translates to:
  /// **'Site Name'**
  String get siteName;

  /// No sites message
  ///
  /// In en, this message translates to:
  /// **'No sites'**
  String get noSites;

  /// User update success message
  ///
  /// In en, this message translates to:
  /// **'✅ User updated'**
  String get userUpdated;

  /// Delete site prompt
  ///
  /// In en, this message translates to:
  /// **'Delete Site'**
  String get deleteSite;

  /// Configure users tooltip
  ///
  /// In en, this message translates to:
  /// **'Configure Users'**
  String get configureUsers;

  /// Configure stream tooltip
  ///
  /// In en, this message translates to:
  /// **'Configure Stream'**
  String get configureStream;

  /// Site management dialog title
  ///
  /// In en, this message translates to:
  /// **'Site Management - {siteName}'**
  String managementTitle(String siteName);

  /// Group label for site display
  ///
  /// In en, this message translates to:
  /// **'group: {groupName}'**
  String groupLabel(String groupName);

  /// Login page title
  ///
  /// In en, this message translates to:
  /// **'Visionnaire App'**
  String get loginTitle;

  /// Login failed message
  ///
  /// In en, this message translates to:
  /// **'❌ Login failed'**
  String get loginFailed;

  /// Login required fields prompt
  ///
  /// In en, this message translates to:
  /// **'Please enter username and password'**
  String get loginRequired;

  /// Admin role
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get admin;

  /// Regular user role
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// Error title
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// Success title
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// Warning title
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get warning;

  /// Information title
  ///
  /// In en, this message translates to:
  /// **'Information'**
  String get info;

  /// Loading message
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No data message
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get noData;

  /// Refresh data button
  ///
  /// In en, this message translates to:
  /// **'Refresh data'**
  String get refreshData;

  /// Search button text
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// Filter button text
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter;

  /// Select all option
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// Clear selection button
  ///
  /// In en, this message translates to:
  /// **'Clear Selection'**
  String get clearSelection;

  /// Back button text
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// Next button text
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// Previous button text
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previous;

  /// Finish button text
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get finish;

  /// Close button
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Title for API configuration page
  ///
  /// In en, this message translates to:
  /// **'API Configuration'**
  String get apiConfigTitle;

  /// Error message when configuration fails to load
  ///
  /// In en, this message translates to:
  /// **'Failed to load configuration'**
  String get loadConfigFailed;

  /// Label for custom configuration
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get customConfig;

  /// Tooltip for copy button
  ///
  /// In en, this message translates to:
  /// **'Copy to clipboard'**
  String get copyToClipboard;

  /// Message shown when text is copied to clipboard
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// Tooltip for reset button
  ///
  /// In en, this message translates to:
  /// **'Reset to default'**
  String get resetToDefault;

  /// Hint text for API URL input field
  ///
  /// In en, this message translates to:
  /// **'Please enter API URL'**
  String get apiUrlHint;

  /// Error message for invalid URL
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid URL'**
  String get validUrlError;

  /// Label showing the default value
  ///
  /// In en, this message translates to:
  /// **'Default value: {value}'**
  String defaultValue(String value);

  /// Tooltip for refresh button
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// Menu item text to reset all configurations
  ///
  /// In en, this message translates to:
  /// **'Reset All to Defaults'**
  String get resetAll;

  /// Label for API URL input field
  ///
  /// In en, this message translates to:
  /// **'API URL'**
  String get apiUrlLabel;

  /// User role label
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get roleUser;

  /// Guest role label
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get roleGuest;

  /// Admin role label
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// Error message format
  ///
  /// In en, this message translates to:
  /// **'❌ {error}'**
  String errorMessage(String error);

  /// Stream configuration dialog title
  ///
  /// In en, this message translates to:
  /// **'Stream Configuration'**
  String get streamConfig;

  /// Stream configuration dialog title
  ///
  /// In en, this message translates to:
  /// **'Stream Configuration - {siteName}'**
  String streamConfigTitle(String siteName);

  /// Stream usage display
  ///
  /// In en, this message translates to:
  /// **'Used {used} / Limit {max}'**
  String streamUsage(int used, int max);

  /// Warning message: stream limit reached
  ///
  /// In en, this message translates to:
  /// **'⚠️ Stream limit reached ({maxStreams})'**
  String streamLimitReached(int maxStreams);

  /// Add stream title
  ///
  /// In en, this message translates to:
  /// **'Add Stream'**
  String get addStream;

  /// Stream name field label
  ///
  /// In en, this message translates to:
  /// **'Stream Name'**
  String get streamName;

  /// URL field label
  ///
  /// In en, this message translates to:
  /// **'RTSP / HTTP URL'**
  String get rtspHttpUrl;

  /// Model key field label
  ///
  /// In en, this message translates to:
  /// **'Model key'**
  String get modelKey;

  /// Time input label: start hour
  ///
  /// In en, this message translates to:
  /// **'Start Hour (0-23)'**
  String get startHour;

  /// Time input label: end hour
  ///
  /// In en, this message translates to:
  /// **'End Hour (0-23)'**
  String get endHour;

  /// Master switch for the recognition stream
  ///
  /// In en, this message translates to:
  /// **'Enable recognition stream'**
  String get recognitionEnabled;

  /// Explanation of the recognition stream master switch
  ///
  /// In en, this message translates to:
  /// **'When off, the configuration is saved, but recognition does not run and the stream is hidden from the live wall.'**
  String get recognitionEnabledHint;

  /// Expire date field label
  ///
  /// In en, this message translates to:
  /// **'Expire Date (optional)'**
  String get expireDate;

  /// Not set status
  ///
  /// In en, this message translates to:
  /// **'Not Set'**
  String get notSet;

  /// Edit stream dialog title
  ///
  /// In en, this message translates to:
  /// **'Edit - {streamName}'**
  String editStream(String streamName);

  /// Delete stream dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete Stream'**
  String get deleteStream;

  /// Delete stream confirmation message
  ///
  /// In en, this message translates to:
  /// **'Are you sure? This action cannot be undone'**
  String get deleteStreamConfirmation;

  /// Stream add success message
  ///
  /// In en, this message translates to:
  /// **'✅ Stream added'**
  String get streamAdded;

  /// Stream update success message
  ///
  /// In en, this message translates to:
  /// **'✅ Updated'**
  String get streamUpdated;

  /// Stream delete success message
  ///
  /// In en, this message translates to:
  /// **'✅ Deleted'**
  String get streamDeleted;

  /// Text shown when there are no stream configurations
  ///
  /// In en, this message translates to:
  /// **'No stream configurations'**
  String get noStreamConfigs;

  /// Edit tooltip
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editTooltip;

  /// Delete tooltip
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteTooltip;

  /// Detection option: no safety vest or helmet
  ///
  /// In en, this message translates to:
  /// **'No Safety Vest/Helmet'**
  String get noSafetyVestOrHelmet;

  /// Detection option: near machinery or vehicle
  ///
  /// In en, this message translates to:
  /// **'Near Machinery/Vehicle'**
  String get nearMachineryOrVehicle;

  /// Detection option: in restricted area
  ///
  /// In en, this message translates to:
  /// **'In Restricted Area'**
  String get inRestrictedArea;

  /// Detection option: in utility pole area
  ///
  /// In en, this message translates to:
  /// **'In Utility Pole Area'**
  String get inUtilityPoleArea;

  /// Detection option: machinery near pole
  ///
  /// In en, this message translates to:
  /// **'Machinery Near Pole'**
  String get machineryNearPole;

  /// Expiry date option label
  ///
  /// In en, this message translates to:
  /// **'Expiry Date (optional)'**
  String get expiryDate;

  /// Message when no stream configurations exist
  ///
  /// In en, this message translates to:
  /// **'No stream configuration'**
  String get noStreamConfig;

  /// File management menu item
  ///
  /// In en, this message translates to:
  /// **'File Management'**
  String get fileManagement;

  /// API configuration menu item
  ///
  /// In en, this message translates to:
  /// **'API Configuration'**
  String get apiConfiguration;

  /// Loading API configuration message
  ///
  /// In en, this message translates to:
  /// **'Loading API configuration...'**
  String get loadingApiConfig;

  /// API configuration status title
  ///
  /// In en, this message translates to:
  /// **'API Configuration Status'**
  String get apiConfigStatus;

  /// Custom configuration count
  ///
  /// In en, this message translates to:
  /// **'{count} Custom'**
  String customConfigCount(Object count);

  /// Using defaults label
  ///
  /// In en, this message translates to:
  /// **'Using Defaults'**
  String get usingDefaults;

  /// Custom API endpoints count message
  ///
  /// In en, this message translates to:
  /// **'You have customized {count} API endpoint URLs.'**
  String customApiEndpointsMessage(Object count);

  /// All endpoints use defaults message
  ///
  /// In en, this message translates to:
  /// **'All API endpoints use default URLs.'**
  String get allEndpointsUseDefaults;

  /// API endpoint details title
  ///
  /// In en, this message translates to:
  /// **'API Endpoint Details'**
  String get apiEndpointDetails;

  /// Chat API service description
  ///
  /// In en, this message translates to:
  /// **'Chat conversation API service'**
  String get chatApiDescription;

  /// Detection API service description
  ///
  /// In en, this message translates to:
  /// **'Object detection API service'**
  String get detectionApiDescription;

  /// Management API service description
  ///
  /// In en, this message translates to:
  /// **'System management API service'**
  String get managementApiDescription;

  /// Notification API service description
  ///
  /// In en, this message translates to:
  /// **'Notification push API service'**
  String get notificationApiDescription;

  /// Streaming API service description
  ///
  /// In en, this message translates to:
  /// **'Streaming media API service'**
  String get streamingApiDescription;

  /// File management API service description
  ///
  /// In en, this message translates to:
  /// **'File management API service'**
  String get fileManagementApiDescription;

  /// Violation records API service description
  ///
  /// In en, this message translates to:
  /// **'Violation records API service'**
  String get violationRecordsApiDescription;

  /// Generic API service description
  ///
  /// In en, this message translates to:
  /// **'API Service'**
  String get apiService;

  /// Welcome message for logged in user
  ///
  /// In en, this message translates to:
  /// **'Welcome, {username}!'**
  String welcomeUser(String username);

  /// User role label
  ///
  /// In en, this message translates to:
  /// **'Role: {role}'**
  String roleLabel(String role);

  /// Label for non-logged in user
  ///
  /// In en, this message translates to:
  /// **'Guest User'**
  String get guestUser;

  /// Message encouraging user to login
  ///
  /// In en, this message translates to:
  /// **'Please login to access features'**
  String get pleaseLogin;

  /// Button text for downloading image
  ///
  /// In en, this message translates to:
  /// **'Download Image'**
  String get downloadImage;

  /// Button text for copying image to clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy Image'**
  String get copyImage;

  /// Button text for sharing link
  ///
  /// In en, this message translates to:
  /// **'Share Link'**
  String get shareImage;

  /// Message when image is downloaded to device
  ///
  /// In en, this message translates to:
  /// **'Image downloaded to device'**
  String get imageDownloaded;

  /// Message when image is saved to photo gallery
  ///
  /// In en, this message translates to:
  /// **'Image saved to photo gallery'**
  String get imageSavedToGallery;

  /// Message when image is copied
  ///
  /// In en, this message translates to:
  /// **'Image copied to clipboard'**
  String get imageCopied;

  /// Message when download fails
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get downloadFailed;

  /// Message when copy fails
  ///
  /// In en, this message translates to:
  /// **'Copy failed'**
  String get copyFailed;

  /// Message when share fails
  ///
  /// In en, this message translates to:
  /// **'Share failed'**
  String get shareFailed;

  /// No description provided for @signupConsentMissingError.
  ///
  /// In en, this message translates to:
  /// **'Please accept all required consent items.'**
  String get signupConsentMissingError;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign up'**
  String get signUp;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredField;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPassword;

  /// No description provided for @passwordMismatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordMismatch;

  /// No description provided for @signupLegalFallbackNotice.
  ///
  /// In en, this message translates to:
  /// **'Using the bundled legal text for now; accepted versions will still be submitted.'**
  String get signupLegalFallbackNotice;

  /// No description provided for @signupTermsTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get signupTermsTitle;

  /// No description provided for @signupTermsContent.
  ///
  /// In en, this message translates to:
  /// **'Visionnaire provides construction safety records, detection review, notification, document, and collaboration features. Users must provide accurate account information, protect their credentials, and use the service only for authorized work purposes. AI detection and system alerts are assistive tools and do not replace on-site safety management, professional judgment, or legal responsibilities. Misuse, unauthorized access, reverse engineering, data scraping, or unlawful content is prohibited.'**
  String get signupTermsContent;

  /// No description provided for @signupPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get signupPrivacyTitle;

  /// No description provided for @signupPrivacyContent.
  ///
  /// In en, this message translates to:
  /// **'Visionnaire may collect account profile data, worksite and group information, camera stream metadata, violation records, images, review notes, device tokens, IP address, user agent, and usage logs. Data is used to provide safety detection, review workflows, notifications, audit trails, security, maintenance, and service improvement. Data may be processed through cloud infrastructure, Firebase Cloud Messaging, and authorized AI services according to organizational settings.'**
  String get signupPrivacyContent;

  /// No description provided for @signupAiTermsTitle.
  ///
  /// In en, this message translates to:
  /// **'LLM and AI Agent Terms'**
  String get signupAiTermsTitle;

  /// No description provided for @signupAiTermsContent.
  ///
  /// In en, this message translates to:
  /// **'LLM and AI Agent outputs are generated assistance and may be incomplete, inaccurate, or outdated. Users must independently verify outputs before using them for safety, compliance, legal, financial, or operational decisions. Do not submit confidential, sensitive, personal, or unlawful information unless your organization has authorized that use. Prompts, files, context, outputs, and actions may be logged for service delivery, security, audit, and improvement.'**
  String get signupAiTermsContent;

  /// No description provided for @signupSocialTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick signup with a social account'**
  String get signupSocialTitle;

  /// No description provided for @signupSocialSubtitle.
  ///
  /// In en, this message translates to:
  /// **'If a new account is created, verify your email first, then wait for administrator approval.'**
  String get signupSocialSubtitle;

  /// No description provided for @signupSubmittedTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify your email'**
  String get signupSubmittedTitle;

  /// No description provided for @signupSubmittedMessage.
  ///
  /// In en, this message translates to:
  /// **'Your request has been submitted. We sent a one-time verification link that expires automatically. After verification, your account will wait for administrator approval.'**
  String get signupSubmittedMessage;

  /// No description provided for @signupConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Required consent'**
  String get signupConsentTitle;

  /// No description provided for @signupAcceptTermsPrivacyPrefix.
  ///
  /// In en, this message translates to:
  /// **'I have read and agree to'**
  String get signupAcceptTermsPrivacyPrefix;

  /// No description provided for @signupConsentAnd.
  ///
  /// In en, this message translates to:
  /// **'and'**
  String get signupConsentAnd;

  /// No description provided for @signupAcceptNotifications.
  ///
  /// In en, this message translates to:
  /// **'I agree to receive safety alerts and review notifications'**
  String get signupAcceptNotifications;

  /// No description provided for @signupAcceptAiTermsPrefix.
  ///
  /// In en, this message translates to:
  /// **'I understand and agree to the'**
  String get signupAcceptAiTermsPrefix;

  /// No description provided for @signupConsentRequirement.
  ///
  /// In en, this message translates to:
  /// **'All three consent items are required before submitting.'**
  String get signupConsentRequirement;

  /// No description provided for @emailVerificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify email'**
  String get emailVerificationTitle;

  /// No description provided for @emailVerificationChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking your verification link. This link can only be used once and expires automatically.'**
  String get emailVerificationChecking;

  /// No description provided for @emailVerificationMissingOrInvalid.
  ///
  /// In en, this message translates to:
  /// **'This verification link is invalid or missing a token. You can send a new email.'**
  String get emailVerificationMissingOrInvalid;

  /// No description provided for @emailVerificationExpired.
  ///
  /// In en, this message translates to:
  /// **'This verification link has expired. Send a new verification email.'**
  String get emailVerificationExpired;

  /// No description provided for @emailVerificationUsed.
  ///
  /// In en, this message translates to:
  /// **'This verification link has already been used. If you still cannot login, send a new email or contact an administrator.'**
  String get emailVerificationUsed;

  /// No description provided for @emailVerificationGenericError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while verifying your email.'**
  String get emailVerificationGenericError;

  /// No description provided for @emailVerificationVerified.
  ///
  /// In en, this message translates to:
  /// **'Your email is verified. Please return to login.'**
  String get emailVerificationVerified;

  /// No description provided for @emailVerificationPendingApproval.
  ///
  /// In en, this message translates to:
  /// **'Your email is verified. Your account is waiting for administrator approval.'**
  String get emailVerificationPendingApproval;

  /// No description provided for @emailVerificationEnterEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter the email used for registration.'**
  String get emailVerificationEnterEmail;

  /// No description provided for @emailVerificationResend.
  ///
  /// In en, this message translates to:
  /// **'Resend verification email'**
  String get emailVerificationResend;

  /// No description provided for @emailVerificationResendSent.
  ///
  /// In en, this message translates to:
  /// **'If this email is registered and not yet verified, a verification email has been sent.'**
  String get emailVerificationResendSent;

  /// No description provided for @notificationDiagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification check'**
  String get notificationDiagnosticsTitle;

  /// No description provided for @notificationMissingUserId.
  ///
  /// In en, this message translates to:
  /// **'Missing user ID. Please sign in again.'**
  String get notificationMissingUserId;

  /// No description provided for @notificationTokenUploaded.
  ///
  /// In en, this message translates to:
  /// **'FCM token uploaded.'**
  String get notificationTokenUploaded;

  /// No description provided for @notificationSignInBeforeTest.
  ///
  /// In en, this message translates to:
  /// **'Please sign in before sending a test notification.'**
  String get notificationSignInBeforeTest;

  /// No description provided for @notificationTestSent.
  ///
  /// In en, this message translates to:
  /// **'Test notification sent.'**
  String get notificationTestSent;

  /// No description provided for @notificationFirebaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Firebase'**
  String get notificationFirebaseLabel;

  /// No description provided for @notificationConfigured.
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get notificationConfigured;

  /// No description provided for @notificationNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get notificationNotConfigured;

  /// No description provided for @notificationPermission.
  ///
  /// In en, this message translates to:
  /// **'Permission'**
  String get notificationPermission;

  /// No description provided for @notificationLastUpload.
  ///
  /// In en, this message translates to:
  /// **'Last upload'**
  String get notificationLastUpload;

  /// No description provided for @notificationMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get notificationMissing;

  /// No description provided for @notificationServiceWorker.
  ///
  /// In en, this message translates to:
  /// **'Service worker'**
  String get notificationServiceWorker;

  /// No description provided for @notificationUploadToken.
  ///
  /// In en, this message translates to:
  /// **'Upload token'**
  String get notificationUploadToken;

  /// No description provided for @notificationTestNotification.
  ///
  /// In en, this message translates to:
  /// **'Test notification'**
  String get notificationTestNotification;

  /// No description provided for @notificationCenterTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification center'**
  String get notificationCenterTitle;

  /// No description provided for @notificationLoadMoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load more notifications: {error}'**
  String notificationLoadMoreFailed(String error);

  /// No description provided for @notificationMarkReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to mark notification as read: {error}'**
  String notificationMarkReadFailed(String error);

  /// No description provided for @notificationMarkAllReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to mark all notifications as read: {error}'**
  String notificationMarkAllReadFailed(String error);

  /// No description provided for @notificationOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to open notification link: {error}'**
  String notificationOpenFailed(String error);

  /// No description provided for @notificationFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get notificationFilterAll;

  /// No description provided for @notificationFilterUnread.
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get notificationFilterUnread;

  /// No description provided for @notificationFilterSignature.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get notificationFilterSignature;

  /// No description provided for @notificationFilterViolation.
  ///
  /// In en, this message translates to:
  /// **'Violation'**
  String get notificationFilterViolation;

  /// No description provided for @notificationFilterDocument.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get notificationFilterDocument;

  /// No description provided for @notificationFilterSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get notificationFilterSystem;

  /// No description provided for @notificationJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get notificationJustNow;

  /// No description provided for @notificationMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{minutes} minutes ago'**
  String notificationMinutesAgo(int minutes);

  /// No description provided for @notificationHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{hours} hours ago'**
  String notificationHoursAgo(int hours);

  /// No description provided for @notificationDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days} days ago'**
  String notificationDaysAgo(int days);

  /// No description provided for @notificationMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get notificationMarkAllRead;

  /// No description provided for @notificationUnreadCount.
  ///
  /// In en, this message translates to:
  /// **'{count} unread'**
  String notificationUnreadCount(int count);

  /// No description provided for @notificationNoUnread.
  ///
  /// In en, this message translates to:
  /// **'No unread'**
  String get notificationNoUnread;

  /// No description provided for @notificationEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get notificationEmpty;

  /// No description provided for @notificationLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load notifications'**
  String get notificationLoadFailed;

  /// No description provided for @notificationFallbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Notification'**
  String get notificationFallbackTitle;

  /// No description provided for @violationNoMatchingRecords.
  ///
  /// In en, this message translates to:
  /// **'No matching records'**
  String get violationNoMatchingRecords;

  /// No description provided for @violationRecordsTab.
  ///
  /// In en, this message translates to:
  /// **'Records'**
  String get violationRecordsTab;

  /// No description provided for @violationAnalyticsTab.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get violationAnalyticsTab;

  /// No description provided for @violationGroup.
  ///
  /// In en, this message translates to:
  /// **'Group'**
  String get violationGroup;

  /// No description provided for @violationAllGroups.
  ///
  /// In en, this message translates to:
  /// **'All groups'**
  String get violationAllGroups;

  /// No description provided for @violationRangeLastDay.
  ///
  /// In en, this message translates to:
  /// **'Last day'**
  String get violationRangeLastDay;

  /// No description provided for @violationRangeLast30Days.
  ///
  /// In en, this message translates to:
  /// **'30 days'**
  String get violationRangeLast30Days;

  /// No description provided for @violationRangeLastHalfYear.
  ///
  /// In en, this message translates to:
  /// **'6 months'**
  String get violationRangeLastHalfYear;

  /// No description provided for @violationRangeLastYear.
  ///
  /// In en, this message translates to:
  /// **'1 year'**
  String get violationRangeLastYear;

  /// No description provided for @violationRangeYearToDate.
  ///
  /// In en, this message translates to:
  /// **'YTD'**
  String get violationRangeYearToDate;

  /// No description provided for @violationUnnamedGroup.
  ///
  /// In en, this message translates to:
  /// **'Unnamed group'**
  String get violationUnnamedGroup;

  /// No description provided for @reviewFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get reviewFilterAll;

  /// No description provided for @reviewFilterFlagged.
  ///
  /// In en, this message translates to:
  /// **'Flagged'**
  String get reviewFilterFlagged;

  /// No description provided for @reviewFilterPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get reviewFilterPending;

  /// No description provided for @reviewFilterResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get reviewFilterResolved;

  /// No description provided for @reviewFilterDismissed.
  ///
  /// In en, this message translates to:
  /// **'Dismissed'**
  String get reviewFilterDismissed;

  /// No description provided for @reviewStatusReviewed.
  ///
  /// In en, this message translates to:
  /// **'Reviewed'**
  String get reviewStatusReviewed;

  /// No description provided for @reviewStatusNotSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Not submitted'**
  String get reviewStatusNotSubmitted;

  /// No description provided for @reviewFlagReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Flag reason'**
  String get reviewFlagReasonLabel;

  /// No description provided for @reviewSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reviewSectionTitle;

  /// No description provided for @reviewFlaggedBadge.
  ///
  /// In en, this message translates to:
  /// **'Flagged'**
  String get reviewFlaggedBadge;

  /// No description provided for @reviewPendingNote.
  ///
  /// In en, this message translates to:
  /// **'Pending note'**
  String get reviewPendingNote;

  /// No description provided for @reviewNote.
  ///
  /// In en, this message translates to:
  /// **'Review note'**
  String get reviewNote;

  /// No description provided for @reviewHandled.
  ///
  /// In en, this message translates to:
  /// **'Handled'**
  String get reviewHandled;

  /// No description provided for @reviewNoteOptional.
  ///
  /// In en, this message translates to:
  /// **'Review note, optional'**
  String get reviewNoteOptional;

  /// No description provided for @reviewAuditTrail.
  ///
  /// In en, this message translates to:
  /// **'Audit trail'**
  String get reviewAuditTrail;

  /// No description provided for @reviewAuditTrailLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load audit trail: {error}'**
  String reviewAuditTrailLoadFailed(String error);

  /// No description provided for @reviewAuditTrailEmpty.
  ///
  /// In en, this message translates to:
  /// **'No audit trail yet.'**
  String get reviewAuditTrailEmpty;

  /// No description provided for @overlayLabel.
  ///
  /// In en, this message translates to:
  /// **'Overlay'**
  String get overlayLabel;

  /// No description provided for @overlayHidden.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get overlayHidden;

  /// No description provided for @overlayAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get overlayAll;

  /// No description provided for @overlayFlaggedOnly.
  ///
  /// In en, this message translates to:
  /// **'Flagged only'**
  String get overlayFlaggedOnly;

  /// No description provided for @reviewChangeMarkerColor.
  ///
  /// In en, this message translates to:
  /// **'Change marker color'**
  String get reviewChangeMarkerColor;

  /// No description provided for @reviewActionResolve.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get reviewActionResolve;

  /// No description provided for @reviewActionDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get reviewActionDismiss;

  /// No description provided for @reviewActionPending.
  ///
  /// In en, this message translates to:
  /// **'Set pending'**
  String get reviewActionPending;

  /// No description provided for @reviewMissingRecordUpdate.
  ///
  /// In en, this message translates to:
  /// **'Unable to update review because the record ID is missing.'**
  String get reviewMissingRecordUpdate;

  /// No description provided for @reviewSignInRequiredUpdate.
  ///
  /// In en, this message translates to:
  /// **'You must be signed in to update review status.'**
  String get reviewSignInRequiredUpdate;

  /// No description provided for @reviewUpdated.
  ///
  /// In en, this message translates to:
  /// **'Review status updated.'**
  String get reviewUpdated;

  /// No description provided for @reviewUpdatedNext.
  ///
  /// In en, this message translates to:
  /// **'Review updated. Moving to the next pending item.'**
  String get reviewUpdatedNext;

  /// No description provided for @reviewUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update review: {error}'**
  String reviewUpdateFailed(String error);

  /// No description provided for @reviewReasonFalsePositive.
  ///
  /// In en, this message translates to:
  /// **'False positive: the detection was reported as incorrect'**
  String get reviewReasonFalsePositive;

  /// No description provided for @reviewReasonFalseNegative.
  ///
  /// In en, this message translates to:
  /// **'Missed detection: an object was missing from the results'**
  String get reviewReasonFalseNegative;

  /// No description provided for @reviewReasonWrongClass.
  ///
  /// In en, this message translates to:
  /// **'Wrong class: the detection label needs correction'**
  String get reviewReasonWrongClass;

  /// No description provided for @reviewReasonBadBox.
  ///
  /// In en, this message translates to:
  /// **'Bad box: the bounding box needs correction'**
  String get reviewReasonBadBox;

  /// No description provided for @detectionFeedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Detection feedback'**
  String get detectionFeedbackTitle;

  /// No description provided for @detectionFeedbackDescription.
  ///
  /// In en, this message translates to:
  /// **'Mark false positives or missed detections for model improvement review.'**
  String get detectionFeedbackDescription;

  /// No description provided for @detectionFeedbackFalsePositive.
  ///
  /// In en, this message translates to:
  /// **'Mark wrong'**
  String get detectionFeedbackFalsePositive;

  /// No description provided for @detectionFeedbackMissed.
  ///
  /// In en, this message translates to:
  /// **'Draw missed'**
  String get detectionFeedbackMissed;

  /// No description provided for @detectionFeedbackNoBoxes.
  ///
  /// In en, this message translates to:
  /// **'No detection boxes are available to select.'**
  String get detectionFeedbackNoBoxes;

  /// No description provided for @detectionFeedbackMissedLabel.
  ///
  /// In en, this message translates to:
  /// **'Missed label'**
  String get detectionFeedbackMissedLabel;

  /// No description provided for @detectionFeedbackNoteOptional.
  ///
  /// In en, this message translates to:
  /// **'Note, optional'**
  String get detectionFeedbackNoteOptional;

  /// No description provided for @detectionFeedbackNoMissedTarget.
  ///
  /// In en, this message translates to:
  /// **'No missed target selected'**
  String get detectionFeedbackNoMissedTarget;

  /// No description provided for @detectionFeedbackSelectedBox.
  ///
  /// In en, this message translates to:
  /// **'Selected {bbox}'**
  String detectionFeedbackSelectedBox(String bbox);

  /// No description provided for @detectionFeedbackSubmitMissed.
  ///
  /// In en, this message translates to:
  /// **'Submit missed'**
  String get detectionFeedbackSubmitMissed;

  /// No description provided for @detectionFeedbackFalsePositiveHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the wrong detection box in the image.'**
  String get detectionFeedbackFalsePositiveHint;

  /// No description provided for @detectionFeedbackMissedHint.
  ///
  /// In en, this message translates to:
  /// **'Drag on the image to draw the missed target.'**
  String get detectionFeedbackMissedHint;

  /// No description provided for @detectionFeedbackBoxes.
  ///
  /// In en, this message translates to:
  /// **'Boxes'**
  String get detectionFeedbackBoxes;

  /// No description provided for @feedbackNoDetectionSelected.
  ///
  /// In en, this message translates to:
  /// **'No detection box was selected. Tap inside a box.'**
  String get feedbackNoDetectionSelected;

  /// No description provided for @feedbackSelectionTooSmall.
  ///
  /// In en, this message translates to:
  /// **'The selected area is too small. Please draw it again.'**
  String get feedbackSelectionTooSmall;

  /// No description provided for @feedbackFalsePositiveDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Report false positive'**
  String get feedbackFalsePositiveDialogTitle;

  /// No description provided for @feedbackFalsePositiveDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'This detection will be marked as a false positive for review.'**
  String get feedbackFalsePositiveDialogMessage;

  /// No description provided for @feedbackDrawMissedFirst.
  ///
  /// In en, this message translates to:
  /// **'Draw the missed target in the image first.'**
  String get feedbackDrawMissedFirst;

  /// No description provided for @feedbackMissingRecord.
  ///
  /// In en, this message translates to:
  /// **'Unable to submit feedback because the record ID is missing.'**
  String get feedbackMissingRecord;

  /// No description provided for @feedbackSignInRequired.
  ///
  /// In en, this message translates to:
  /// **'You must be signed in to submit feedback.'**
  String get feedbackSignInRequired;

  /// No description provided for @feedbackSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Feedback submitted. Thank you.'**
  String get feedbackSubmitted;

  /// No description provided for @feedbackSubmitFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit feedback: {error}'**
  String feedbackSubmitFailed(String error);

  /// No description provided for @imageViewerTitle.
  ///
  /// In en, this message translates to:
  /// **'Image viewer'**
  String get imageViewerTitle;

  /// No description provided for @imageViewerRotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get imageViewerRotate;

  /// No description provided for @imageViewerResetZoom.
  ///
  /// In en, this message translates to:
  /// **'Reset zoom'**
  String get imageViewerResetZoom;

  /// No description provided for @falsePositivePickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Select wrong detection'**
  String get falsePositivePickerTitle;

  /// No description provided for @falsePositivePickerHint.
  ///
  /// In en, this message translates to:
  /// **'Double tap to zoom, pan, then tap a box or label.'**
  String get falsePositivePickerHint;

  /// No description provided for @falsePositivePickerBottomHint.
  ///
  /// In en, this message translates to:
  /// **'Tap a highlighted box or label to report'**
  String get falsePositivePickerBottomHint;

  /// No description provided for @falsePositivePickerMiss.
  ///
  /// In en, this message translates to:
  /// **'Tap a box or label. Zoom in if needed.'**
  String get falsePositivePickerMiss;

  /// No description provided for @saveSuccess.
  ///
  /// In en, this message translates to:
  /// **'Saved successfully.'**
  String get saveSuccess;

  /// No description provided for @editAuditFixDocTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit audit improvement document'**
  String get editAuditFixDocTitle;

  /// No description provided for @addAuditFixDocTitle.
  ///
  /// In en, this message translates to:
  /// **'Add audit improvement document'**
  String get addAuditFixDocTitle;

  /// No description provided for @multiSelectAlbum.
  ///
  /// In en, this message translates to:
  /// **'Select from album'**
  String get multiSelectAlbum;

  /// No description provided for @auditDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Audit date'**
  String get auditDateLabel;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Today: {date}'**
  String todayLabel(String date);

  /// No description provided for @addPhotoViaCamera.
  ///
  /// In en, this message translates to:
  /// **'Add photos with camera or album'**
  String get addPhotoViaCamera;

  /// No description provided for @showDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Show date stamp'**
  String get showDateLabel;

  /// No description provided for @dateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get dateLabel;

  /// No description provided for @descriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionLabel;

  /// No description provided for @descBeforeLabel.
  ///
  /// In en, this message translates to:
  /// **'Before improvement'**
  String get descBeforeLabel;

  /// No description provided for @descDuringLabel.
  ///
  /// In en, this message translates to:
  /// **'During improvement'**
  String get descDuringLabel;

  /// No description provided for @descAfterLabel.
  ///
  /// In en, this message translates to:
  /// **'After improvement'**
  String get descAfterLabel;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Group {number}'**
  String groupNumberLabel(String number);

  /// No description provided for @applyDescriptionToAllGroups.
  ///
  /// In en, this message translates to:
  /// **'Apply description to following groups'**
  String get applyDescriptionToAllGroups;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Done ({count})'**
  String doneWithCount(String count);

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Load failed: {error}'**
  String loadFailedError(String error);

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Please select a signer for {field}'**
  String pleaseSelectSignerFor(String field);

  /// No description provided for @submitted.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get submitted;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String failedWith(String error);

  /// No description provided for @editDocumentTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit document'**
  String get editDocumentTitle;

  /// No description provided for @headerSection.
  ///
  /// In en, this message translates to:
  /// **'Header'**
  String get headerSection;

  /// No description provided for @bodySection.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get bodySection;

  /// No description provided for @footerSection.
  ///
  /// In en, this message translates to:
  /// **'Footer'**
  String get footerSection;

  /// No description provided for @saveAndSubmit.
  ///
  /// In en, this message translates to:
  /// **'Save and submit'**
  String get saveAndSubmit;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Table {number}'**
  String tableLabel(String number);

  /// No description provided for @unnamedSite.
  ///
  /// In en, this message translates to:
  /// **'Unnamed site'**
  String get unnamedSite;

  /// No description provided for @addImage.
  ///
  /// In en, this message translates to:
  /// **'Add image'**
  String get addImage;

  /// No description provided for @tapToSign.
  ///
  /// In en, this message translates to:
  /// **'Tap to sign'**
  String get tapToSign;

  /// No description provided for @signatureSection.
  ///
  /// In en, this message translates to:
  /// **'Signature'**
  String get signatureSection;

  /// No description provided for @signatureFlow.
  ///
  /// In en, this message translates to:
  /// **'Signature flow'**
  String get signatureFlow;

  /// No description provided for @orderedSigningActive.
  ///
  /// In en, this message translates to:
  /// **'Ordered signing is active.'**
  String get orderedSigningActive;

  /// No description provided for @freeSigningActive.
  ///
  /// In en, this message translates to:
  /// **'Any-order signing is active.'**
  String get freeSigningActive;

  /// No description provided for @signingOrderLocked.
  ///
  /// In en, this message translates to:
  /// **'Signing order is locked after tasks are created.'**
  String get signingOrderLocked;

  /// No description provided for @anyOrder.
  ///
  /// In en, this message translates to:
  /// **'Any order'**
  String get anyOrder;

  /// No description provided for @signInOrder.
  ///
  /// In en, this message translates to:
  /// **'Sign in order'**
  String get signInOrder;

  /// No description provided for @orderedSigningDragHint.
  ///
  /// In en, this message translates to:
  /// **'Drag signers to adjust the signing order before submitting.'**
  String get orderedSigningDragHint;

  /// No description provided for @freeSigningHint.
  ///
  /// In en, this message translates to:
  /// **'All assigned signers can sign without a fixed order.'**
  String get freeSigningHint;

  /// No description provided for @selectSignerHint.
  ///
  /// In en, this message translates to:
  /// **'Select signer'**
  String get selectSignerHint;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Order {rank}'**
  String orderRank(String rank);

  /// No description provided for @signatureFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Signature field'**
  String get signatureFieldLabel;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Comment: {comment}'**
  String commentLabel(String comment);

  /// No description provided for @sitesNotLoaded.
  ///
  /// In en, this message translates to:
  /// **'Sites have not been loaded yet.'**
  String get sitesNotLoaded;

  /// No description provided for @documentListTitle.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get documentListTitle;

  /// No description provided for @creatorLabel.
  ///
  /// In en, this message translates to:
  /// **'Creator'**
  String get creatorLabel;

  /// No description provided for @editorLabel.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get editorLabel;

  /// No description provided for @signerLabel.
  ///
  /// In en, this message translates to:
  /// **'Signer'**
  String get signerLabel;

  /// No description provided for @selectSiteFirstHint.
  ///
  /// In en, this message translates to:
  /// **'Select a site first to load members.'**
  String get selectSiteFirstHint;

  /// No description provided for @loadingMemberList.
  ///
  /// In en, this message translates to:
  /// **'Loading members...'**
  String get loadingMemberList;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Failed to load members: {error}'**
  String memberLoadFailed(String error);

  /// No description provided for @noMemberListForSite.
  ///
  /// In en, this message translates to:
  /// **'No members are available for this site.'**
  String get noMemberListForSite;

  /// No description provided for @uploadButton.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get uploadButton;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'All {label}'**
  String allFilter(String label);

  /// No description provided for @unclassified.
  ///
  /// In en, this message translates to:
  /// **'Unclassified'**
  String get unclassified;

  /// No description provided for @documentLocked.
  ///
  /// In en, this message translates to:
  /// **'Document locked'**
  String get documentLocked;

  /// No description provided for @mySignTasks.
  ///
  /// In en, this message translates to:
  /// **'My signature tasks'**
  String get mySignTasks;

  /// No description provided for @browserDownloadStarted.
  ///
  /// In en, this message translates to:
  /// **'Browser download started.'**
  String get browserDownloadStarted;

  /// No description provided for @storagePermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Storage permission is required to download files.'**
  String get storagePermissionRequired;

  /// No description provided for @downloadComplete.
  ///
  /// In en, this message translates to:
  /// **'Download complete.'**
  String get downloadComplete;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String downloadFailedError(String error);

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Delete version {version}?'**
  String deleteVersionConfirm(String version);

  /// No description provided for @versionDeleted.
  ///
  /// In en, this message translates to:
  /// **'Version deleted.'**
  String get versionDeleted;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete version: {error}'**
  String deleteVersionFailedError(String error);

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Versions for {document}'**
  String documentVersionListTitle(String document);

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String versionNumber(String version);

  /// No description provided for @downloadDocx.
  ///
  /// In en, this message translates to:
  /// **'Download DOCX'**
  String get downloadDocx;

  /// No description provided for @downloadPdf.
  ///
  /// In en, this message translates to:
  /// **'Download PDF'**
  String get downloadPdf;

  /// No description provided for @pdfConverting.
  ///
  /// In en, this message translates to:
  /// **'PDF converting'**
  String get pdfConverting;

  /// No description provided for @deleteVersionTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete version'**
  String get deleteVersionTooltip;

  /// No description provided for @pdfNotReady.
  ///
  /// In en, this message translates to:
  /// **'PDF is not ready yet'**
  String get pdfNotReady;

  /// No description provided for @addPhotoDocTitle.
  ///
  /// In en, this message translates to:
  /// **'Add photo document'**
  String get addPhotoDocTitle;

  /// No description provided for @editPhotoDocTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit photo document'**
  String get editPhotoDocTitle;

  /// No description provided for @requiredSelect.
  ///
  /// In en, this message translates to:
  /// **'Please select an option'**
  String get requiredSelect;

  /// No description provided for @projectNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Project name'**
  String get projectNameLabel;

  /// No description provided for @addPhotosHint.
  ///
  /// In en, this message translates to:
  /// **'Take photos or select images from album.'**
  String get addPhotosHint;

  /// No description provided for @locationLabel.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationLabel;

  /// No description provided for @applyImageDataToAll.
  ///
  /// In en, this message translates to:
  /// **'Apply image data to following items'**
  String get applyImageDataToAll;

  /// No description provided for @notificationSettings.
  ///
  /// In en, this message translates to:
  /// **'Notification settings'**
  String get notificationSettings;

  /// No description provided for @siteNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Site notifications'**
  String get siteNotificationTitle;

  /// No description provided for @siteNotificationDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose which site alerts you want to receive.'**
  String get siteNotificationDescription;

  /// No description provided for @noSiteNotification.
  ///
  /// In en, this message translates to:
  /// **'No site notification items.'**
  String get noSiteNotification;

  /// No description provided for @notificationSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search notifications'**
  String get notificationSearchHint;

  /// No description provided for @siteNotificationSaveSuccess.
  ///
  /// In en, this message translates to:
  /// **'Site notification settings saved.'**
  String get siteNotificationSaveSuccess;

  /// No description provided for @documentNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Document notifications'**
  String get documentNotificationTitle;

  /// No description provided for @documentNotificationDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose which document workflow notifications you want to receive.'**
  String get documentNotificationDescription;

  /// No description provided for @noDocumentNotification.
  ///
  /// In en, this message translates to:
  /// **'No document notification items.'**
  String get noDocumentNotification;

  /// No description provided for @documentNotificationSaveSuccess.
  ///
  /// In en, this message translates to:
  /// **'Document notification settings saved.'**
  String get documentNotificationSaveSuccess;

  /// No description provided for @siteNotificationChannel.
  ///
  /// In en, this message translates to:
  /// **'Site alerts'**
  String get siteNotificationChannel;

  /// No description provided for @documentNotificationChannel.
  ///
  /// In en, this message translates to:
  /// **'Document workflow'**
  String get documentNotificationChannel;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Failed to save notification settings: {error}'**
  String notificationSaveFailed(String error);

  /// No description provided for @notificationSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No notification settings match your search.'**
  String get notificationSearchEmpty;

  /// No description provided for @allSiteGroups.
  ///
  /// In en, this message translates to:
  /// **'All site groups'**
  String get allSiteGroups;

  /// No description provided for @notificationEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get notificationEnabled;

  /// No description provided for @notificationPendingSave.
  ///
  /// In en, this message translates to:
  /// **'Pending save'**
  String get notificationPendingSave;

  /// No description provided for @notificationStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get notificationStatus;

  /// No description provided for @notificationSaving.
  ///
  /// In en, this message translates to:
  /// **'Saving'**
  String get notificationSaving;

  /// No description provided for @notificationSynced.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get notificationSynced;

  /// No description provided for @enableAllNotifications.
  ///
  /// In en, this message translates to:
  /// **'Enable all'**
  String get enableAllNotifications;

  /// No description provided for @disableAllNotifications.
  ///
  /// In en, this message translates to:
  /// **'Disable all'**
  String get disableAllNotifications;

  /// No description provided for @saveNotificationChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveNotificationChanges;

  /// No description provided for @notificationAlreadySynced.
  ///
  /// In en, this message translates to:
  /// **'Already synced'**
  String get notificationAlreadySynced;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'{enabled}/{total} enabled'**
  String notificationEnabledCount(String enabled, String total);

  /// No description provided for @notificationUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get notificationUnsaved;

  /// No description provided for @pendingSignStatus.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pendingSignStatus;

  /// No description provided for @signedStatus.
  ///
  /// In en, this message translates to:
  /// **'Signed'**
  String get signedStatus;

  /// No description provided for @commentedStatus.
  ///
  /// In en, this message translates to:
  /// **'Commented'**
  String get commentedStatus;

  /// No description provided for @skippedStatus.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get skippedStatus;

  /// No description provided for @rejectedStatus.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejectedStatus;

  /// No description provided for @commentedStatusDescription.
  ///
  /// In en, this message translates to:
  /// **'Return with a comment for revision.'**
  String get commentedStatusDescription;

  /// No description provided for @skippedStatusDescription.
  ///
  /// In en, this message translates to:
  /// **'Skip this signature step.'**
  String get skippedStatusDescription;

  /// No description provided for @rejectedStatusDescription.
  ///
  /// In en, this message translates to:
  /// **'Reject and return the document.'**
  String get rejectedStatusDescription;

  /// No description provided for @signedStatusDescription.
  ///
  /// In en, this message translates to:
  /// **'Sign and approve this step.'**
  String get signedStatusDescription;

  /// No description provided for @chooseDocumentTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose document type'**
  String get chooseDocumentTypeTitle;

  /// No description provided for @documentTypeSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search document types'**
  String get documentTypeSearchHint;

  /// No description provided for @noAvailableCategories.
  ///
  /// In en, this message translates to:
  /// **'No available categories'**
  String get noAvailableCategories;

  /// No description provided for @noMatchingDocumentTypes.
  ///
  /// In en, this message translates to:
  /// **'No matching document types'**
  String get noMatchingDocumentTypes;

  /// No description provided for @documentTypePrefixUnset.
  ///
  /// In en, this message translates to:
  /// **'Prefix not set'**
  String get documentTypePrefixUnset;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Prefix: {prefix}'**
  String documentTypePrefixValue(String prefix);

  /// No description provided for @approveUser.
  ///
  /// In en, this message translates to:
  /// **'Approve user'**
  String get approveUser;

  /// No description provided for @selectGroupForUser.
  ///
  /// In en, this message translates to:
  /// **'Select a group for this user.'**
  String get selectGroupForUser;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @pendingApprovalTitle.
  ///
  /// In en, this message translates to:
  /// **'Pending approval'**
  String get pendingApprovalTitle;

  /// No description provided for @pendingApprovalMessage.
  ///
  /// In en, this message translates to:
  /// **'Your account is waiting for administrator approval.'**
  String get pendingApprovalMessage;

  /// No description provided for @signDocument.
  ///
  /// In en, this message translates to:
  /// **'Sign document'**
  String get signDocument;

  /// No description provided for @goToMyTasks.
  ///
  /// In en, this message translates to:
  /// **'Go to my tasks'**
  String get goToMyTasks;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Failed to load signature task: {error}'**
  String loadSignTaskFailed(String error);

  /// No description provided for @signTaskNotFound.
  ///
  /// In en, this message translates to:
  /// **'Signature task not found.'**
  String get signTaskNotFound;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Failed to load signature task: {error}'**
  String signTaskLoadFailed(String error);

  /// No description provided for @pleaseSignFirst.
  ///
  /// In en, this message translates to:
  /// **'Please sign before submitting.'**
  String get pleaseSignFirst;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Submit failed: {error}'**
  String submitFailed(String error);

  /// No description provided for @documentVersionUpdated.
  ///
  /// In en, this message translates to:
  /// **'Document version has been updated. Please reload.'**
  String get documentVersionUpdated;

  /// No description provided for @revisionCommentLabel.
  ///
  /// In en, this message translates to:
  /// **'Revision comment'**
  String get revisionCommentLabel;

  /// No description provided for @revisionCommentHint.
  ///
  /// In en, this message translates to:
  /// **'Describe what should be revised.'**
  String get revisionCommentHint;

  /// No description provided for @rejectionReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Rejection reason'**
  String get rejectionReasonLabel;

  /// No description provided for @rejectionReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Describe why this document is rejected.'**
  String get rejectionReasonHint;

  /// No description provided for @signAction.
  ///
  /// In en, this message translates to:
  /// **'Sign'**
  String get signAction;

  /// No description provided for @commentAction.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get commentAction;

  /// No description provided for @skipAction.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skipAction;

  /// No description provided for @rejectAction.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get rejectAction;

  /// No description provided for @signResult.
  ///
  /// In en, this message translates to:
  /// **'Signature result'**
  String get signResult;

  /// No description provided for @handwrittenSignature.
  ///
  /// In en, this message translates to:
  /// **'Handwritten signature'**
  String get handwrittenSignature;

  /// No description provided for @resignature.
  ///
  /// In en, this message translates to:
  /// **'Sign again'**
  String get resignature;

  /// No description provided for @signatureConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Signature confirmed.'**
  String get signatureConfirmed;

  /// No description provided for @confirmSignature.
  ///
  /// In en, this message translates to:
  /// **'Confirm signature'**
  String get confirmSignature;

  /// No description provided for @signaturePreview.
  ///
  /// In en, this message translates to:
  /// **'Signature preview'**
  String get signaturePreview;

  /// No description provided for @confirmSubmit.
  ///
  /// In en, this message translates to:
  /// **'Confirm submit'**
  String get confirmSubmit;

  /// No description provided for @startSign.
  ///
  /// In en, this message translates to:
  /// **'Start signing'**
  String get startSign;

  /// No description provided for @signatureHint.
  ///
  /// In en, this message translates to:
  /// **'Please provide your signature.'**
  String get signatureHint;

  /// No description provided for @noSignTasks.
  ///
  /// In en, this message translates to:
  /// **'No signature tasks.'**
  String get noSignTasks;

  /// No description provided for @createdTime.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get createdTime;

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Task {taskId} · {status}'**
  String taskNumberStatus(String taskId, String status);

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Version {version} · {placeholder}'**
  String versionPlaceholder(String version, String placeholder);

  /// Generated placeholder metadata.
  ///
  /// In en, this message translates to:
  /// **'Failed to load PDF: {error}'**
  String pdfLoadFailed(String error);

  /// No description provided for @commentRequired.
  ///
  /// In en, this message translates to:
  /// **'Comment is required for this action.'**
  String get commentRequired;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'fr', 'id', 'ja', 'th', 'vi', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {

  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh': {
  switch (locale.countryCode) {
    case 'CN': return AppLocalizationsZhCn();
   }
  break;
   }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'fr': return AppLocalizationsFr();
    case 'id': return AppLocalizationsId();
    case 'ja': return AppLocalizationsJa();
    case 'th': return AppLocalizationsTh();
    case 'vi': return AppLocalizationsVi();
    case 'zh': return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
