// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get appTitle => 'Visionnaire Application';

  @override
  String get deviceLang => 'en-UK';

  @override
  String get login => 'Login';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get chatList => 'Chat List';

  @override
  String get chatTitleCannotBeEmpty => 'Chat title cannot be empty or whitespace only';

  @override
  String get cameraList => 'Camera Streams';

  @override
  String get detection => 'Object Detection';

  @override
  String get logout => 'Logout';

  @override
  String get changeLanguage => 'Change Language';

  @override
  String get site => 'Site';

  @override
  String get stream => 'Stream';

  @override
  String get detectionTime => 'Detection Time';

  @override
  String get violationMessage => 'Thông báo vi phạm';

  @override
  String get loadingImageError => 'Failed to load image';

  @override
  String get violationRecordQuery => 'Nhật ký vi phạm';

  @override
  String get keyword => 'Từ khóa (camera hoặc thông báo)';

  @override
  String get startTime => 'Thời gian bắt đầu';

  @override
  String get endTime => 'Thời gian kết thúc';

  @override
  String get query => 'Tìm kiếm';

  @override
  String get noRecords => 'No records available';

  @override
  String get streamingWebSettings => 'Live Monitoring';

  @override
  String get streamingWebUrl => 'Streaming Web URL (with http:// or https://)';

  @override
  String get save => 'Save';

  @override
  String get goToLabels => 'Go to Locations';

  @override
  String get currentUrl => 'Current URL';

  @override
  String get labelList => 'Locations';

  @override
  String get label => 'Label';

  @override
  String get noImage => 'No camera images available';

  @override
  String get warnings => 'Cảnh báo';

  @override
  String get lastUpdated => 'Last updated';

  @override
  String get noWarnings => 'No warnings';

  @override
  String get detectionResult => 'Detection Result';

  @override
  String get chooseModel => 'Choose Model';

  @override
  String get noImageSelected => 'No image selected';

  @override
  String get noDetectionResult => 'No detection result';

  @override
  String get takePhoto => 'Take Photo';

  @override
  String get photoLibrary => 'Photo Library';

  @override
  String get startDetection => 'Start Detection';

  @override
  String get cannotOpenCamera => 'Cannot open camera';

  @override
  String get cannotOpenGallery => 'Cannot open gallery';

  @override
  String get getImageSizeFailed => 'Failed to get image size';

  @override
  String get notLoggedIn => 'Not logged in (Detection service token invalid)';

  @override
  String get tokenRefreshFailed => 'Token refresh failed';

  @override
  String get chatLoadFailed => 'Failed to load chat';

  @override
  String get chatRoom => 'Chat Room';

  @override
  String get inputMessage => 'Enter message...';

  @override
  String get newChatRoom => 'New Chat Room';

  @override
  String get enterChatRoomTitle => 'Enter chat room title';

  @override
  String get create => 'Create';

  @override
  String get createFailed => 'Creation failed';

  @override
  String get confirmDeleteChatRoom => 'Are you sure you want to delete this chat room?';

  @override
  String get cancel => 'Hủy';

  @override
  String get delete => 'Delete';

  @override
  String get deleteFailed => 'Deletion failed';

  @override
  String get selectSite => 'Chọn công trường';

  @override
  String get notSelected => 'Chưa chọn';

  @override
  String errorPrefix(String error) {
    return 'Lỗi: $error';
  }

  @override
  String get sitePrefix => 'Công trường: ';

  @override
  String get streamPrefix => 'Luồng: ';

  @override
  String get detectionTimePrefix => 'Thời gian phát hiện: ';

  @override
  String get urlUpdated => 'Updated Streaming Web Base URL to:';

  @override
  String get streamingWebIndexTitle => 'Locations';

  @override
  String get unknownError => 'Unknown error';

  @override
  String get noLabels => 'No labels available';

  @override
  String get chatMessageCannotBeEmpty => 'Chat message cannot be empty';

  @override
  String get editQuestionHint => 'Please enter the new question';

  @override
  String get confirm => 'Confirm';

  @override
  String get editQuestion => 'Edit Question';

  @override
  String get regenerateAnswer => 'Regenerate Answer';

  @override
  String get removeQuestionChain => 'Remove Question (with subsequent dialog)';

  @override
  String get failedToLoadHistory => 'Failed to load history';

  @override
  String get failedToLoadHistoryAfterRefresh => 'Failed to load history after refresh';

  @override
  String get failedToAskAfterRefresh => 'Failed to ask after refresh';

  @override
  String get editFailed => 'Edit failed';

  @override
  String get editFailedAfterRefresh => 'Edit failed after refresh';

  @override
  String get regenerateFailed => 'Regenerate failed';

  @override
  String get regenerateFailedAfterRefresh => 'Regenerate failed after refresh';

  @override
  String get removeFailed => 'Remove failed';

  @override
  String get removeFailedAfterRefresh => 'Remove failed after refresh';

  @override
  String get sendMessage => 'Gửi tin nhắn';

  @override
  String get addImages => 'Thêm hình ảnh';

  @override
  String get addFiles => 'Thêm tệp';

  @override
  String attachmentCount(int count) {
    return '$count tệp đính kèm';
  }

  @override
  String get cancelGeneration => 'Hủy tạo';

  @override
  String get createChatRoom => 'Tạo phòng chat';

  @override
  String attachmentUploadFailed(String error) {
    return 'Tải lên tệp đính kèm thất bại: $error';
  }

  @override
  String attachmentDeleteFailed(String error) {
    return 'Xóa tệp đính kèm thất bại: $error';
  }

  @override
  String get selectLabel => 'Chọn nhãn';

  @override
  String get showDetectionResults => 'Hiển thị kết quả phát hiện';

  @override
  String get hardhat => 'Mũ bảo hộ';

  @override
  String get vest => 'Áo phản quang';

  @override
  String get machinery => 'Máy thi công';

  @override
  String get vehicle => 'Phương tiện';

  @override
  String get no_hardhat => 'Không đội mũ bảo hộ';

  @override
  String get no_vest => 'Không mặc áo phản quang';

  @override
  String get person => 'Người';

  @override
  String get cone => 'Cọc tiêu giao thông';

  @override
  String get mask => 'Khẩu trang';

  @override
  String get no_mask => 'Không đeo khẩu trang';

  @override
  String get utility_pole => 'Cột điện';

  @override
  String warning_people_in_controlled_area(int count) {
    return 'Cảnh báo: Có $count người đã vào khu vực kiểm soát!';
  }

  @override
  String warning_people_in_utility_pole_controlled_area(int count) {
    return 'Cảnh báo: Có $count người đã vào khu vực hạn chế quanh cột điện!';
  }

  @override
  String warning_no_hardhat(int count) {
    return 'Cảnh báo: Có $count người không đội mũ bảo hộ!';
  }

  @override
  String warning_no_safety_vest(int count) {
    return 'Cảnh báo: Có $count người không mặc áo phản quang!';
  }

  @override
  String warning_close_to_machinery(int count) {
    return 'Cảnh báo: Có $count người ở quá gần máy thi công!';
  }

  @override
  String warning_close_to_vehicle(int count) {
    return 'Cảnh báo: Có $count người ở quá gần phương tiện!';
  }

  @override
  String detect_machinery_close_to_pole(int count) {
    return 'Cảnh báo: Có $count máy thi công ở quá gần cột điện!';
  }

  @override
  String get showOverlay => 'Hiện chú thích';

  @override
  String get add => 'Add';

  @override
  String get edit => 'Edit';

  @override
  String get submit => 'Submit';

  @override
  String get build => 'Create';

  @override
  String get saving => 'Saving...';

  @override
  String get saveConfig => 'Save Configuration';

  @override
  String get configSavedSuccessfully => 'Configuration saved successfully';

  @override
  String get saveConfigFailed => 'Failed to save configuration';

  @override
  String get confirmResetAllConfigs => 'Are you sure you want to reset all API configurations to default values? This action cannot be undone.';

  @override
  String confirmResetConfig(String name) {
    return 'Are you sure you want to reset $name to default values?';
  }

  @override
  String get confirmDelete => 'Confirm Delete?';

  @override
  String permanentDeleteWarning(String name) {
    return 'Will permanently delete \"$name\". This action cannot be undone!';
  }

  @override
  String deleteWarning(String name) {
    return 'Will delete \"$name\". This action cannot be undone.';
  }

  @override
  String get siteCreated => '✅ Site created';

  @override
  String get deleted => '✅ Deleted';

  @override
  String get added => '✅ Added';

  @override
  String get featureAdded => '✅ Feature added';

  @override
  String editFeature(String name) {
    return 'Edit \"$name\"';
  }

  @override
  String editUser(String username) {
    return 'Edit \"$username\"';
  }

  @override
  String get addUser => 'Add User';

  @override
  String get addFeature => 'Add Feature';

  @override
  String get addGroup => 'Add Group';

  @override
  String get editGroup => 'Edit Group';

  @override
  String get confirmDeleteFile => 'Confirm Delete';

  @override
  String get confirmDeleteFileMessage => 'Are you sure you want to delete this file?';

  @override
  String get fileDeleted => 'File deleted';

  @override
  String get deleteFileFailed => 'Delete failed';

  @override
  String get createAuditDoc => 'Create Audit Improvement Document';

  @override
  String get createDocx => 'Create DOCX';

  @override
  String get addPhotoPrompt => 'Please add photos by taking photos or from album';

  @override
  String createFailedWith(String error) {
    return 'Creation failed: $error';
  }

  @override
  String get addFile => 'Add File';

  @override
  String get noConfigChangesDetected => 'No configuration changes detected';

  @override
  String get resetToDefaults => 'Reset to Defaults';

  @override
  String get resetSuccess => 'Reset to default configuration';

  @override
  String get resetFailed => 'Reset failed';

  @override
  String resetEndpointSuccess(String name) {
    return 'Reset $name successfully';
  }

  @override
  String resetEndpoint(String name) {
    return 'Reset $name';
  }

  @override
  String get notLoggedInOrInvalidToken => 'Not logged in or invalid token';

  @override
  String uploadFailed(String error) {
    return 'Upload failed: $error';
  }

  @override
  String get pleaseWaitForSiteList => 'Site list not yet loaded, please wait';

  @override
  String get selectConstructionSite => 'Select Construction Site';

  @override
  String get allSites => 'Tất cả công trường';

  @override
  String get startDate => 'Start Date';

  @override
  String get endDate => 'End Date';

  @override
  String get versions => 'Versions';

  @override
  String get fileTypeNotConfigured => 'This file type has no file_prefix configured, cannot use template';

  @override
  String get noUsers => 'No users yet';

  @override
  String nameDisplay(String name, String email, String role, String group) {
    return 'Name: $name | Email: $email | Role: $role | Group: $group';
  }

  @override
  String get deactivate => 'Deactivate';

  @override
  String get activate => 'Activate';

  @override
  String get permissionDenied => 'Permission denied';

  @override
  String get userManagement => 'User Management';

  @override
  String get account => 'Account';

  @override
  String get familyName => 'Family Name';

  @override
  String get middleName => 'Middle Name';

  @override
  String get givenName => 'Given Name';

  @override
  String get email => 'Email';

  @override
  String get mobile => 'Mobile';

  @override
  String get resetPassword => 'Reset Password';

  @override
  String get role => 'Role';

  @override
  String get group => 'Group';

  @override
  String get required => 'Required';

  @override
  String get emailFormatError => 'Please enter a valid email address';

  @override
  String get selectGroup => 'Please select a group';

  @override
  String get mobileOptional => 'Mobile (Optional)';

  @override
  String get middleNameOptional => 'Middle Name (Optional)';

  @override
  String get updated => '✅ Updated';

  @override
  String get apiConfig => 'API Configuration';

  @override
  String get custom => 'Custom';

  @override
  String deleteFeatureConfirmation(Object name) {
    return 'Will delete feature \\\"$name\\\". This action cannot be undone.';
  }

  @override
  String assignGroups(Object name) {
    return 'Assign Groups - $name';
  }

  @override
  String get setGroups => 'Set Groups';

  @override
  String get reload => 'Reload';

  @override
  String get copy => 'Copy';

  @override
  String get passwordChanged => '✅ Password changed, please login again with new password';

  @override
  String get oldPassword => 'Old Password';

  @override
  String get newPassword => 'New Password';

  @override
  String get pleaseLoginFirst => 'Please login first';

  @override
  String get changePassword => 'Change Password';

  @override
  String get minimumPasswordLength => 'At least 8 characters';

  @override
  String get featureManagement => 'Feature Management';

  @override
  String get featureName => 'Feature Name';

  @override
  String get descriptionOptional => 'Description (optional)';

  @override
  String assignGroup(String name) {
    return 'Assign Group - $name';
  }

  @override
  String get noFeatures => 'No features';

  @override
  String get groupPermissionsUpdated => '✅ Group permissions updated';

  @override
  String get setGroup => 'Set Group';

  @override
  String get groupManagement => 'Group Management';

  @override
  String get groupName => 'Group Name';

  @override
  String get uniformNumber => 'Uniform Number (8 digits)';

  @override
  String get uniformNumberError => 'Uniform number requires 8 digits';

  @override
  String get noGroups => 'No groups';

  @override
  String uniformLabel(String uniformNumber) {
    return 'Uniform: $uniformNumber';
  }

  @override
  String get uniformNumberValidation => 'Must be 8 digits';

  @override
  String get name => 'Name';

  @override
  String get siteManagement => 'Site Management';

  @override
  String get siteName => 'Site Name';

  @override
  String get noSites => 'No sites';

  @override
  String get userUpdated => '✅ User updated';

  @override
  String get deleteSite => 'Delete Site';

  @override
  String get configureUsers => 'Configure Users';

  @override
  String get configureStream => 'Configure Stream';

  @override
  String managementTitle(String siteName) {
    return 'Site Management - $siteName';
  }

  @override
  String groupLabel(String groupName) {
    return 'group: $groupName';
  }

  @override
  String get loginTitle => 'Visionnaire App';

  @override
  String get loginFailed => '❌ Login failed';

  @override
  String get loginRequired => 'Please enter username and password';

  @override
  String get admin => 'Admin';

  @override
  String get user => 'User';

  @override
  String get error => 'Error';

  @override
  String get success => 'Success';

  @override
  String get warning => 'Warning';

  @override
  String get info => 'Information';

  @override
  String get loading => 'Loading...';

  @override
  String get noData => 'No data';

  @override
  String get refreshData => 'Refresh data';

  @override
  String get search => 'Search';

  @override
  String get filter => 'Filter';

  @override
  String get selectAll => 'Select All';

  @override
  String get clearSelection => 'Xóa lựa chọn';

  @override
  String get back => 'Back';

  @override
  String get next => 'Next';

  @override
  String get previous => 'Previous';

  @override
  String get finish => 'Finish';

  @override
  String get close => 'Close';

  @override
  String get apiConfigTitle => 'API Configuration';

  @override
  String get loadConfigFailed => 'Failed to load configuration';

  @override
  String get customConfig => 'Custom';

  @override
  String get copyToClipboard => 'Copy to clipboard';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get resetToDefault => 'Reset to default';

  @override
  String get apiUrlHint => 'Please enter API URL';

  @override
  String get validUrlError => 'Please enter a valid URL';

  @override
  String defaultValue(String value) {
    return 'Default value: $value';
  }

  @override
  String get refresh => 'Làm mới';

  @override
  String get resetAll => 'Reset All to Defaults';

  @override
  String get apiUrlLabel => 'API URL';

  @override
  String get roleUser => 'User';

  @override
  String get roleGuest => 'Guest';

  @override
  String get roleAdmin => 'Admin';

  @override
  String errorMessage(String error) {
    return '❌ $error';
  }

  @override
  String get streamConfig => 'Stream Configuration';

  @override
  String streamConfigTitle(String siteName) {
    return 'Stream Configuration - $siteName';
  }

  @override
  String streamUsage(int used, int max) {
    return 'Used $used / Limit $max';
  }

  @override
  String streamLimitReached(int maxStreams) {
    return '⚠️ Stream limit reached ($maxStreams)';
  }

  @override
  String get addStream => 'Add Stream';

  @override
  String get streamName => 'Stream Name';

  @override
  String get rtspHttpUrl => 'RTSP / HTTP URL';

  @override
  String get modelKey => 'Model key';

  @override
  String get startHour => 'Start Hour (0-23)';

  @override
  String get endHour => 'End Hour (0-23)';

  @override
  String get recognitionEnabled => 'Enable recognition stream';

  @override
  String get recognitionEnabledHint => 'When off, the configuration is saved, but recognition does not run and the stream is hidden from the live wall.';

  @override
  String get expireDate => 'Expire Date (optional)';

  @override
  String get notSet => 'Not Set';

  @override
  String editStream(String streamName) {
    return 'Edit - $streamName';
  }

  @override
  String get deleteStream => 'Delete Stream';

  @override
  String get deleteStreamConfirmation => 'Are you sure? This action cannot be undone';

  @override
  String get streamAdded => '✅ Stream added';

  @override
  String get streamUpdated => '✅ Updated';

  @override
  String get streamDeleted => '✅ Deleted';

  @override
  String get noStreamConfigs => 'No stream configurations';

  @override
  String get editTooltip => 'Edit';

  @override
  String get deleteTooltip => 'Delete';

  @override
  String get noSafetyVestOrHelmet => 'No Safety Vest/Helmet';

  @override
  String get nearMachineryOrVehicle => 'Near Machinery/Vehicle';

  @override
  String get inRestrictedArea => 'In Restricted Area';

  @override
  String get inUtilityPoleArea => 'In Utility Pole Area';

  @override
  String get machineryNearPole => 'Machinery Near Pole';

  @override
  String get expiryDate => 'Expiry Date (optional)';

  @override
  String get noStreamConfig => 'No stream configuration';

  @override
  String get fileManagement => 'File Management';

  @override
  String get apiConfiguration => 'API Configuration';

  @override
  String get loadingApiConfig => 'Loading API configuration...';

  @override
  String get apiConfigStatus => 'API Configuration Status';

  @override
  String customConfigCount(Object count) {
    return '$count Custom';
  }

  @override
  String get usingDefaults => 'Using Defaults';

  @override
  String customApiEndpointsMessage(Object count) {
    return 'You have customized $count API endpoint URLs.';
  }

  @override
  String get allEndpointsUseDefaults => 'All API endpoints use default URLs.';

  @override
  String get apiEndpointDetails => 'API Endpoint Details';

  @override
  String get chatApiDescription => 'Chat conversation API service';

  @override
  String get detectionApiDescription => 'Object detection API service';

  @override
  String get managementApiDescription => 'System management API service';

  @override
  String get notificationApiDescription => 'Notification push API service';

  @override
  String get streamingApiDescription => 'Streaming media API service';

  @override
  String get fileManagementApiDescription => 'File management API service';

  @override
  String get violationRecordsApiDescription => 'Violation records API service';

  @override
  String get apiService => 'API Service';

  @override
  String welcomeUser(String username) {
    return 'Welcome, $username!';
  }

  @override
  String roleLabel(String role) {
    return 'Role: $role';
  }

  @override
  String get guestUser => 'Guest User';

  @override
  String get pleaseLogin => 'Please login to access features';

  @override
  String get downloadImage => 'Download Image';

  @override
  String get copyImage => 'Copy Image';

  @override
  String get shareImage => 'Share Link';

  @override
  String get imageDownloaded => 'Image downloaded to device';

  @override
  String get imageSavedToGallery => 'Image saved to photo gallery';

  @override
  String get imageCopied => 'Image copied to clipboard';

  @override
  String get downloadFailed => 'Download failed';

  @override
  String get copyFailed => 'Copy failed';

  @override
  String get shareFailed => 'Share failed';

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
  String get violationNoMatchingRecords => 'Không có bản ghi phù hợp';

  @override
  String get violationRecordsTab => 'Bản ghi';

  @override
  String get violationAnalyticsTab => 'Thống kê';

  @override
  String get violationGroup => 'Nhóm';

  @override
  String get violationAllGroups => 'Tất cả nhóm';

  @override
  String get violationRangeLastDay => '24 giờ qua';

  @override
  String get violationRangeLast30Days => '30 ngày qua';

  @override
  String get violationRangeLastHalfYear => '6 tháng qua';

  @override
  String get violationRangeLastYear => '1 năm qua';

  @override
  String get violationRangeYearToDate => 'Từ đầu năm';

  @override
  String get violationUnnamedGroup => 'Nhóm chưa đặt tên';

  @override
  String get reviewFilterAll => 'Tất cả';

  @override
  String get reviewFilterFlagged => 'Đã đánh dấu';

  @override
  String get reviewFilterPending => 'Đang chờ';

  @override
  String get reviewFilterResolved => 'Đã xử lý';

  @override
  String get reviewFilterDismissed => 'Đã bác bỏ';

  @override
  String get reviewStatusReviewed => 'Đã xem xét';

  @override
  String get reviewStatusNotSubmitted => 'Chưa gửi';

  @override
  String get reviewFlagReasonLabel => 'Lý do đánh dấu';

  @override
  String get reviewSectionTitle => 'Xem xét';

  @override
  String get reviewFlaggedBadge => 'Đã đánh dấu';

  @override
  String get reviewPendingNote => 'Ghi chú đang chờ';

  @override
  String get reviewNote => 'Ghi chú xem xét';

  @override
  String get reviewHandled => 'Đã xử lý';

  @override
  String get reviewNoteOptional => 'Ghi chú xem xét (tùy chọn)';

  @override
  String get reviewAuditTrail => 'Nhật ký xem xét';

  @override
  String reviewAuditTrailLoadFailed(String error) {
    return 'Không thể tải nhật ký xem xét: $error';
  }

  @override
  String get reviewAuditTrailEmpty => 'Chưa có nhật ký xem xét.';

  @override
  String get overlayLabel => 'Chú thích';

  @override
  String get overlayHidden => 'Tắt';

  @override
  String get overlayAll => 'Tất cả';

  @override
  String get overlayFlaggedOnly => 'Chỉ mục đã đánh dấu';

  @override
  String get reviewChangeMarkerColor => 'Đổi màu dấu đánh dấu';

  @override
  String get reviewActionResolve => 'Đánh dấu đã xử lý';

  @override
  String get reviewActionDismiss => 'Bác bỏ';

  @override
  String get reviewActionPending => 'Chuyển sang chờ xử lý';

  @override
  String get reviewMissingRecordUpdate => 'Không thể cập nhật vì thiếu mã bản ghi.';

  @override
  String get reviewSignInRequiredUpdate => 'Đăng nhập để cập nhật trạng thái xem xét.';

  @override
  String get reviewUpdated => 'Đã cập nhật trạng thái xem xét.';

  @override
  String get reviewUpdatedNext => 'Đã cập nhật. Chuyển đến mục đang chờ tiếp theo.';

  @override
  String reviewUpdateFailed(String error) {
    return 'Không thể cập nhật xem xét: $error';
  }

  @override
  String get reviewReasonFalsePositive => 'Phát hiện nhầm: kết quả phát hiện đã được báo là không đúng';

  @override
  String get reviewReasonFalseNegative => 'Bỏ sót: một đối tượng không có trong kết quả';

  @override
  String get reviewReasonWrongClass => 'Sai loại: cần sửa nhãn phát hiện';

  @override
  String get reviewReasonBadBox => 'Sai khung: cần sửa khung giới hạn';

  @override
  String get detectionFeedbackTitle => 'Phản hồi về phát hiện';

  @override
  String get detectionFeedbackDescription => 'Đánh dấu các phát hiện nhầm hoặc đối tượng bị bỏ sót để cải thiện mô hình.';

  @override
  String get detectionFeedbackFalsePositive => 'Báo phát hiện nhầm';

  @override
  String get detectionFeedbackMissed => 'Vẽ khung đối tượng bị bỏ sót';

  @override
  String get detectionFeedbackNoBoxes => 'Không có khung phát hiện để chọn.';

  @override
  String get detectionFeedbackMissedLabel => 'Loại đối tượng bị bỏ sót';

  @override
  String get detectionFeedbackNoteOptional => 'Ghi chú (tùy chọn)';

  @override
  String get detectionFeedbackNoMissedTarget => 'Chưa chọn đối tượng bị bỏ sót';

  @override
  String detectionFeedbackSelectedBox(String bbox) {
    return 'Khung đã chọn: $bbox';
  }

  @override
  String get detectionFeedbackSubmitMissed => 'Gửi báo cáo bỏ sót';

  @override
  String get detectionFeedbackFalsePositiveHint => 'Chạm vào khung phát hiện sai trong ảnh.';

  @override
  String get detectionFeedbackMissedHint => 'Kéo trên ảnh để khoanh đối tượng bị bỏ sót.';

  @override
  String get detectionFeedbackBoxes => 'Khung';

  @override
  String get feedbackNoDetectionSelected => 'Chưa chọn khung phát hiện. Chạm vào bên trong một khung.';

  @override
  String get feedbackSelectionTooSmall => 'Vùng đã chọn quá nhỏ. Vui lòng vẽ lại.';

  @override
  String get feedbackFalsePositiveDialogTitle => 'Báo cáo phát hiện nhầm';

  @override
  String get feedbackFalsePositiveDialogMessage => 'Kết quả này sẽ được đánh dấu là phát hiện nhầm để xem xét.';

  @override
  String get feedbackDrawMissedFirst => 'Hãy khoanh đối tượng bị bỏ sót trong ảnh trước.';

  @override
  String get feedbackMissingRecord => 'Không thể gửi phản hồi vì thiếu mã bản ghi.';

  @override
  String get feedbackSignInRequired => 'Đăng nhập để gửi phản hồi.';

  @override
  String get feedbackSubmitted => 'Đã gửi phản hồi. Cảm ơn bạn.';

  @override
  String feedbackSubmitFailed(String error) {
    return 'Không thể gửi phản hồi: $error';
  }

  @override
  String get imageViewerTitle => 'Trình xem ảnh';

  @override
  String get imageViewerRotate => 'Xoay';

  @override
  String get imageViewerResetZoom => 'Đặt lại độ thu phóng';

  @override
  String get falsePositivePickerTitle => 'Chọn phát hiện nhầm';

  @override
  String get falsePositivePickerHint => 'Chạm hai lần để phóng to, di chuyển ảnh, rồi chạm vào khung hoặc nhãn.';

  @override
  String get falsePositivePickerBottomHint => 'Chạm vào khung hoặc nhãn được làm nổi bật để báo cáo.';

  @override
  String get falsePositivePickerMiss => 'Chạm vào khung hoặc nhãn. Phóng to nếu cần.';

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

  @override
  String get violationResultsHeading => 'Kết quả';

  @override
  String get violationEvidenceImage => 'Ảnh';

  @override
  String get violationSiteStreamHeading => 'Công trường / Luồng';

  @override
  String get violationTimeRange => 'Khoảng thời gian';

  @override
  String get violationReviewStatus => 'Trạng thái xem xét';

  @override
  String get violationFiltersHeading => 'Bộ lọc';

  @override
  String get violationFiltersDescription => 'Lọc bản ghi theo công trường, camera, loại vi phạm, thời gian và trạng thái xem xét.';

  @override
  String get violationAllCameras => 'Tất cả camera';

  @override
  String get violationCameraLabel => 'Camera';

  @override
  String get violationAllTypes => 'Tất cả loại vi phạm';

  @override
  String get violationTypeLabel => 'Loại vi phạm';

  @override
  String get violationAnalyticsTotal => 'Tổng số vi phạm';

  @override
  String get violationAnalyticsToday => 'Hôm nay';

  @override
  String get violationAnalyticsTopSite => 'Công trường có nhiều vi phạm nhất';

  @override
  String get violationAnalyticsTopType => 'Loại vi phạm phổ biến nhất';

  @override
  String get violationAnalyticsTrend => 'Xu hướng vi phạm';

  @override
  String get violationAnalyticsNoTrend => 'Không có dữ liệu xu hướng';

  @override
  String get violationAnalyticsTypeBreakdown => 'Phân bố theo loại';

  @override
  String get violationAnalyticsNoType => 'Không có dữ liệu theo loại';

  @override
  String get violationAnalyticsTypeRanking => 'Xếp hạng loại vi phạm';

  @override
  String get violationAnalyticsSiteRanking => 'Xếp hạng công trường';

  @override
  String get violationAnalyticsHourly => 'Phân bố theo giờ';

  @override
  String get violationAnalyticsNoHourly => 'Không có dữ liệu theo giờ';

  @override
  String get violationAnalyticsNoRanking => 'Không có dữ liệu xếp hạng';

  @override
  String get violationAnalyticsUnavailable => 'Không thể tải dữ liệu thống kê';

  @override
  String get violationAnalyticsEmpty => 'Không có dữ liệu thống kê';
}
