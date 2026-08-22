// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Visionnaire 應用程式';

  @override
  String get deviceLang => 'zh-TW';

  @override
  String get login => '登入';

  @override
  String get username => '使用者名稱';

  @override
  String get password => '密碼';

  @override
  String get chatList => '聊天列表';

  @override
  String get chatTitleCannotBeEmpty => '聊天標題不能為空或僅包含空格';

  @override
  String get cameraList => '監視器串流';

  @override
  String get detection => '物件偵測';

  @override
  String get logout => '登出';

  @override
  String get changeLanguage => '切換語言';

  @override
  String get site => '工地';

  @override
  String get stream => '串流';

  @override
  String get detectionTime => '偵測時間';

  @override
  String get violationMessage => '違規訊息';

  @override
  String get loadingImageError => '無法載入影像';

  @override
  String get violationRecordQuery => '違規紀錄查詢';

  @override
  String get keyword => '關鍵字 (stream_name 或訊息)';

  @override
  String get startTime => '開始時間';

  @override
  String get endTime => '結束時間';

  @override
  String get query => '查詢';

  @override
  String get noRecords => '目前尚無標籤資料';

  @override
  String get streamingWebSettings => '即時影像';

  @override
  String get streamingWebUrl => 'Streaming Web URL (含 http:// 或 https://)';

  @override
  String get save => '儲存';

  @override
  String get goToLabels => '前往地點列表';

  @override
  String get currentUrl => '目前 URL';

  @override
  String get labelList => '地點';

  @override
  String get label => '標籤';

  @override
  String get noImage => '尚無攝影機畫面資料';

  @override
  String get warnings => '警告訊息';

  @override
  String get lastUpdated => '最後更新時間';

  @override
  String get noWarnings => '沒有警告訊息';

  @override
  String get detectionResult => '偵測結果';

  @override
  String get chooseModel => '選擇模型';

  @override
  String get noImageSelected => '尚未選擇圖片';

  @override
  String get noDetectionResult => '尚無偵測結果';

  @override
  String get takePhoto => '拍照';

  @override
  String get photoLibrary => '相簿';

  @override
  String get startDetection => '開始偵測';

  @override
  String get cannotOpenCamera => '無法開啟相機';

  @override
  String get cannotOpenGallery => '無法開啟相簿';

  @override
  String get getImageSizeFailed => '取得圖片尺寸失敗';

  @override
  String get notLoggedIn => '尚未登入 (偵測服務 Token 無效)';

  @override
  String get tokenRefreshFailed => 'Token 刷新失敗';

  @override
  String get chatLoadFailed => '載入對話失敗';

  @override
  String get chatRoom => '對話房';

  @override
  String get inputMessage => '輸入訊息...';

  @override
  String get newChatRoom => '新聊天室';

  @override
  String get enterChatRoomTitle => '輸入聊天室標題';

  @override
  String get create => '創建';

  @override
  String get createFailed => '創建失敗';

  @override
  String get confirmDeleteChatRoom => '你確定要刪除此聊天房間嗎？';

  @override
  String get cancel => '取消';

  @override
  String get delete => '刪除';

  @override
  String get deleteFailed => '刪除失敗';

  @override
  String get selectSite => '選擇工地';

  @override
  String get notSelected => '未選擇';

  @override
  String errorPrefix(String error) {
    return '錯誤：$error';
  }

  @override
  String get sitePrefix => '工地：';

  @override
  String get streamPrefix => '串流：';

  @override
  String get detectionTimePrefix => '偵測時間：';

  @override
  String get urlUpdated => '已更新 Streaming Web Base URL 為：';

  @override
  String get streamingWebIndexTitle => '地點';

  @override
  String get unknownError => '未知錯誤';

  @override
  String get noLabels => '目前尚無標籤資料';

  @override
  String get chatMessageCannotBeEmpty => '不可輸入空問題';

  @override
  String get editQuestionHint => '請輸入新的問題';

  @override
  String get confirm => '確定';

  @override
  String get editQuestion => '編輯問題';

  @override
  String get regenerateAnswer => '重新生成答案';

  @override
  String get removeQuestionChain => '移除問題(含後續對話)';

  @override
  String get failedToLoadHistory => '載入歷史失敗';

  @override
  String get failedToLoadHistoryAfterRefresh => '刷新後仍載入歷史失敗';

  @override
  String get failedToAskAfterRefresh => '刷新後提問失敗';

  @override
  String get editFailed => '編輯失敗';

  @override
  String get editFailedAfterRefresh => '刷新後仍編輯失敗';

  @override
  String get regenerateFailed => '重新生成失敗';

  @override
  String get regenerateFailedAfterRefresh => '刷新後仍重新生成失敗';

  @override
  String get removeFailed => '移除失敗';

  @override
  String get removeFailedAfterRefresh => '刷新後仍移除失敗';

  @override
  String get sendMessage => '發送訊息';

  @override
  String get addImages => '新增圖片';

  @override
  String get addFiles => '新增檔案';

  @override
  String attachmentCount(int count) {
    return '$count 個附件';
  }

  @override
  String get cancelGeneration => '取消生成';

  @override
  String get createChatRoom => '創建聊天室';

  @override
  String attachmentUploadFailed(String error) {
    return '上傳附件失敗：$error';
  }

  @override
  String attachmentDeleteFailed(String error) {
    return '刪除附件失敗：$error';
  }

  @override
  String get selectLabel => '選擇標籤';

  @override
  String get showDetectionResults => '顯示辨識結果';

  @override
  String get hardhat => '安全帽';

  @override
  String get vest => '背心';

  @override
  String get machinery => '機具';

  @override
  String get vehicle => '車輛';

  @override
  String get no_hardhat => '無安全帽';

  @override
  String get no_vest => '無安全背心';

  @override
  String get person => '人員';

  @override
  String get cone => '安全錐';

  @override
  String get mask => '口罩';

  @override
  String get no_mask => '無口罩';

  @override
  String get utility_pole => '電桿';

  @override
  String warning_people_in_controlled_area(int count) {
    return '警告：$count 人進入受控區域！';
  }

  @override
  String warning_people_in_utility_pole_controlled_area(int count) {
    return '警告：$count 人進入電桿受控區域！';
  }

  @override
  String warning_no_hardhat(int count) {
    return '警告: 有$count人未佩戴安全帽！';
  }

  @override
  String warning_no_safety_vest(int count) {
    return '警告: 有$count人未穿著安全背心！';
  }

  @override
  String warning_close_to_machinery(int count) {
    return '警告：$count 人靠近機具！';
  }

  @override
  String warning_close_to_vehicle(int count) {
    return '警告：$count 人靠近車輛！';
  }

  @override
  String detect_machinery_close_to_pole(int count) {
    return '警告：$count 台機具靠近電桿！';
  }

  @override
  String get showOverlay => '顯示覆蓋層';

  @override
  String get add => '新增';

  @override
  String get edit => '編輯';

  @override
  String get submit => '送出';

  @override
  String get build => '建立';

  @override
  String get saving => '儲存中...';

  @override
  String get saveConfig => '儲存配置';

  @override
  String get configSavedSuccessfully => '配置已成功儲存';

  @override
  String get saveConfigFailed => '儲存配置失敗';

  @override
  String get confirmResetAllConfigs => '確定要將所有 API 配置重置為預設值嗎？此操作無法復原。';

  @override
  String confirmResetConfig(String name) {
    return '確定要將 $name 重置為預設值嗎？';
  }

  @override
  String get confirmDelete => '確定刪除？';

  @override
  String permanentDeleteWarning(String name) {
    return '將永久刪除「$name」。此動作無法復原！';
  }

  @override
  String deleteWarning(String name) {
    return '將刪除「$name」。此動作無法復原。';
  }

  @override
  String get siteCreated => '✅ 已建立工地';

  @override
  String get deleted => '✅ 已刪除';

  @override
  String get added => '✅ 已新增';

  @override
  String get featureAdded => '✅ 已新增功能';

  @override
  String editFeature(String name) {
    return '編輯「$name」';
  }

  @override
  String editUser(String username) {
    return '編輯「$username」';
  }

  @override
  String get addUser => '新增使用者';

  @override
  String get addFeature => '新增功能';

  @override
  String get addGroup => '新增群組';

  @override
  String get editGroup => '編輯群組';

  @override
  String get confirmDeleteFile => '確認刪除';

  @override
  String get confirmDeleteFileMessage => '確定要刪除此文件？';

  @override
  String get fileDeleted => '已刪除文件';

  @override
  String get deleteFileFailed => '刪除失敗';

  @override
  String get createAuditDoc => '新增稽核缺失改善';

  @override
  String get createDocx => '建立 DOCX';

  @override
  String get addPhotoPrompt => '請透過拍照/相簿新增照片';

  @override
  String createFailedWith(String error) {
    return '建立失敗：$error';
  }

  @override
  String get addFile => '新增檔案';

  @override
  String get noConfigChangesDetected => '未偵測到配置變更';

  @override
  String get resetToDefaults => '重置為預設值';

  @override
  String get resetSuccess => '已重置為預設配置';

  @override
  String get resetFailed => '重置失敗';

  @override
  String resetEndpointSuccess(String name) {
    return '已成功重置 $name';
  }

  @override
  String resetEndpoint(String name) {
    return '重置 $name';
  }

  @override
  String get notLoggedInOrInvalidToken => '未登入或 Token 無效';

  @override
  String uploadFailed(String error) {
    return '上傳失敗：$error';
  }

  @override
  String get pleaseWaitForSiteList => '尚未取得站點清單，請稍候';

  @override
  String get selectConstructionSite => '選擇施工站點';

  @override
  String get allSites => '全部站點';

  @override
  String get startDate => '開始日期';

  @override
  String get endDate => '結束日期';

  @override
  String get versions => '歷史版本';

  @override
  String get fileTypeNotConfigured => '此文件類型未設定 file_prefix，無法使用範本';

  @override
  String get noUsers => '尚無使用者';

  @override
  String nameDisplay(String name, String email, String role, String group) {
    return '名稱: $name | 電子郵件: $email | 角色: $role | 群組: $group';
  }

  @override
  String get deactivate => '停用';

  @override
  String get activate => '啟用';

  @override
  String get permissionDenied => '權限不足';

  @override
  String get userManagement => '使用者管理';

  @override
  String get account => '帳號';

  @override
  String get familyName => '姓氏';

  @override
  String get middleName => '中間名';

  @override
  String get givenName => '名字';

  @override
  String get email => '電子郵件';

  @override
  String get mobile => '手機';

  @override
  String get resetPassword => '重設密碼';

  @override
  String get role => '角色';

  @override
  String get group => '群組';

  @override
  String get required => '必填';

  @override
  String get emailFormatError => '請輸入有效的電子郵件地址';

  @override
  String get selectGroup => '請選擇群組';

  @override
  String get mobileOptional => '手機 (選填)';

  @override
  String get middleNameOptional => '中間名 (選填)';

  @override
  String get updated => '✅ 已更新';

  @override
  String get apiConfig => 'API 配置';

  @override
  String get custom => '自訂';

  @override
  String deleteFeatureConfirmation(Object name) {
    return '將刪除功能「$name」。此動作無法復原。';
  }

  @override
  String assignGroups(Object name) {
    return '指派群組 - $name';
  }

  @override
  String get setGroups => '設定群組';

  @override
  String get reload => '重新載入';

  @override
  String get copy => '複製';

  @override
  String get passwordChanged => '✅ 密碼已變更，請使用新密碼重新登入';

  @override
  String get oldPassword => '舊密碼';

  @override
  String get newPassword => '新密碼';

  @override
  String get pleaseLoginFirst => '請先登入';

  @override
  String get changePassword => '變更密碼';

  @override
  String get minimumPasswordLength => '至少 8 碼';

  @override
  String get featureManagement => '功能管理';

  @override
  String get featureName => '功能名稱';

  @override
  String get descriptionOptional => '描述 (可省略)';

  @override
  String assignGroup(String name) {
    return '指派群組 - $name';
  }

  @override
  String get noFeatures => '尚無功能';

  @override
  String get groupPermissionsUpdated => '✅ 已更新群組權限';

  @override
  String get setGroup => '設定群組';

  @override
  String get groupManagement => '群組管理';

  @override
  String get groupName => '群組名稱';

  @override
  String get uniformNumber => '統一編號 (8 碼)';

  @override
  String get uniformNumberError => '統一編號需 8 位數字';

  @override
  String get noGroups => '尚無群組';

  @override
  String uniformLabel(String uniformNumber) {
    return '統編：$uniformNumber';
  }

  @override
  String get uniformNumberValidation => '必須 8 位數字';

  @override
  String get name => '名稱';

  @override
  String get siteManagement => '工地管理';

  @override
  String get siteName => '工地名稱';

  @override
  String get noSites => '尚無工地';

  @override
  String get userUpdated => '✅ 使用者已更新';

  @override
  String get deleteSite => '刪除工地';

  @override
  String get configureUsers => '設定使用者';

  @override
  String get configureStream => '設定串流';

  @override
  String managementTitle(String siteName) {
    return '工地管理 - $siteName';
  }

  @override
  String groupLabel(String groupName) {
    return '群組: $groupName';
  }

  @override
  String get loginTitle => 'Visionnaire App';

  @override
  String get loginFailed => '❌ 登入失敗';

  @override
  String get loginRequired => '請輸入使用者名稱和密碼';

  @override
  String get admin => '管理員';

  @override
  String get user => '使用者';

  @override
  String get error => '錯誤';

  @override
  String get success => '成功';

  @override
  String get warning => '警告';

  @override
  String get info => '資訊';

  @override
  String get loading => '載入中...';

  @override
  String get noData => '無資料';

  @override
  String get refreshData => '重新整理資料';

  @override
  String get search => '搜尋';

  @override
  String get filter => '篩選';

  @override
  String get selectAll => '全選';

  @override
  String get clearSelection => '清除選取';

  @override
  String get back => '返回';

  @override
  String get next => '下一步';

  @override
  String get previous => '上一步';

  @override
  String get finish => '完成';

  @override
  String get close => '關閉';

  @override
  String get apiConfigTitle => 'API 配置';

  @override
  String get loadConfigFailed => '載入配置失敗';

  @override
  String get customConfig => '自訂';

  @override
  String get copyToClipboard => '複製';

  @override
  String get copiedToClipboard => '已複製到剪貼簿';

  @override
  String get resetToDefault => '重置為預設值';

  @override
  String get apiUrlHint => '請輸入 API URL';

  @override
  String get validUrlError => '請輸入有效的 URL';

  @override
  String defaultValue(String value) {
    return '預設值: $value';
  }

  @override
  String get refresh => '重新載入';

  @override
  String get resetAll => '重置全部為預設值';

  @override
  String get apiUrlLabel => 'API URL';

  @override
  String get roleUser => '使用者';

  @override
  String get roleGuest => '訪客';

  @override
  String get roleAdmin => '管理員';

  @override
  String errorMessage(String error) {
    return '❌ $error';
  }

  @override
  String get streamConfig => '串流設定';

  @override
  String streamConfigTitle(String siteName) {
    return '串流設定 - $siteName';
  }

  @override
  String streamUsage(int used, int max) {
    return '已用 $used / 上限 $max';
  }

  @override
  String streamLimitReached(int maxStreams) {
    return '⚠️ 已達串流上限（$maxStreams）';
  }

  @override
  String get addStream => '新增串流';

  @override
  String get streamName => '串流名稱';

  @override
  String get rtspHttpUrl => 'RTSP / HTTP URL';

  @override
  String get modelKey => 'Model key';

  @override
  String get startHour => '開始時 (0-23)';

  @override
  String get endHour => '結束時 (0-23)';

  @override
  String get recognitionEnabled => '啟用辨識串流';

  @override
  String get recognitionEnabledHint => '關閉後會保留設定，但不會執行辨識，也不會顯示於即時影像。';

  @override
  String get expireDate => '到期日 (optional)';

  @override
  String get notSet => '未設定';

  @override
  String editStream(String streamName) {
    return '編輯 - $streamName';
  }

  @override
  String get deleteStream => '刪除串流';

  @override
  String get deleteStreamConfirmation => '確定刪除？此動作無法復原';

  @override
  String get streamAdded => '✅ 已新增串流';

  @override
  String get streamUpdated => '✅ 已更新';

  @override
  String get streamDeleted => '✅ 已刪除';

  @override
  String get noStreamConfigs => '尚無串流設定';

  @override
  String get editTooltip => '編輯';

  @override
  String get deleteTooltip => '刪除';

  @override
  String get noSafetyVestOrHelmet => '無背心/安全帽';

  @override
  String get nearMachineryOrVehicle => '靠近機具/車輛';

  @override
  String get inRestrictedArea => '闖入管制區';

  @override
  String get inUtilityPoleArea => '闖入電杆區';

  @override
  String get machineryNearPole => '機具靠近電杆';

  @override
  String get expiryDate => '到期日 (optional)';

  @override
  String get noStreamConfig => '尚無串流設定';

  @override
  String get fileManagement => '文件管理';

  @override
  String get apiConfiguration => 'API 配置';

  @override
  String get loadingApiConfig => '載入 API 配置中...';

  @override
  String get apiConfigStatus => 'API 配置狀態';

  @override
  String customConfigCount(Object count) {
    return '$count 個自訂';
  }

  @override
  String get usingDefaults => '使用預設值';

  @override
  String customApiEndpointsMessage(Object count) {
    return '您已自訂 $count 個 API 端點的 URL。';
  }

  @override
  String get allEndpointsUseDefaults => '所有 API 端點都使用預設 URL。';

  @override
  String get apiEndpointDetails => 'API 端點詳情';

  @override
  String get chatApiDescription => '聊天對話 API 服務';

  @override
  String get detectionApiDescription => '物件偵測 API 服務';

  @override
  String get managementApiDescription => '系統管理 API 服務';

  @override
  String get notificationApiDescription => '通知推送 API 服務';

  @override
  String get streamingApiDescription => '串流媒體 API 服務';

  @override
  String get fileManagementApiDescription => '檔案管理 API 服務';

  @override
  String get violationRecordsApiDescription => '違規記錄 API 服務';

  @override
  String get apiService => 'API 服務';

  @override
  String welcomeUser(String username) {
    return '歡迎，$username！';
  }

  @override
  String roleLabel(String role) {
    return '角色：$role';
  }

  @override
  String get guestUser => '訪客用戶';

  @override
  String get pleaseLogin => '請登入以使用功能';

  @override
  String get downloadImage => '下載圖片';

  @override
  String get copyImage => '複製圖片';

  @override
  String get shareImage => '分享連結';

  @override
  String get imageDownloaded => '圖片已下載到設備';

  @override
  String get imageSavedToGallery => '圖片已保存到相簿';

  @override
  String get imageCopied => '圖片已複製到剪貼簿';

  @override
  String get downloadFailed => '下載失敗';

  @override
  String get copyFailed => '複製失敗';

  @override
  String get shareFailed => '分享失敗';

  @override
  String get signupConsentMissingError => '請先勾選三項同意內容。';

  @override
  String get signUp => '註冊';

  @override
  String get requiredField => '必填';

  @override
  String get confirmPassword => '確認密碼';

  @override
  String get passwordMismatch => '密碼不一致';

  @override
  String get signupLegalFallbackNotice => '目前使用預設條款內容，送出時仍會記錄同意版本。';

  @override
  String get signupTermsTitle => '使用條款';

  @override
  String get signupTermsContent => 'Visionnaire 提供工地安全紀錄、偵測審核、通知、文件與協作等功能。使用者應提供正確帳號資料，妥善保管登入憑證，並僅於授權工作目的內使用本服務。AI 偵測與系統警示僅作為輔助工具，不取代現場安全管理、專業判斷或法定責任。禁止未授權存取、濫用、逆向工程、資料擷取或提交違法內容。';

  @override
  String get signupPrivacyTitle => '隱私權政策';

  @override
  String get signupPrivacyContent => 'Visionnaire 可能蒐集帳號與個人資料、工地與群組資訊、串流中繼資料、違規紀錄、圖片、審核備註、裝置通知 token、IP 位址、user agent 與使用紀錄。資料將用於安全偵測、審核流程、通知、稽核軌跡、資安維護、服務營運與改善。資料可能依組織設定透過雲端基礎設施、Firebase Cloud Messaging 與授權 AI 服務處理。';

  @override
  String get signupAiTermsTitle => 'LLM 與 AI Agent 使用條款';

  @override
  String get signupAiTermsContent => 'LLM 與 AI Agent 的輸出為系統輔助生成，可能不完整、不正確或非即時資訊。使用者在將輸出用於安全、法規、法律、財務或營運決策前，應自行確認與判斷。除非所屬組織已授權，請勿輸入機密、敏感、個資或違法內容。提示詞、檔案、上下文、輸出與操作紀錄可能為提供服務、資安、稽核與改善目的而被記錄。';

  @override
  String get signupSocialTitle => '使用社群帳號快速申請';

  @override
  String get signupSocialSubtitle => '若建立新帳號，請先完成信箱驗證，接著等待管理員審核。';

  @override
  String get signupSubmittedTitle => '請先驗證電子郵件';

  @override
  String get signupSubmittedMessage => '申請已送出。我們已寄出一次性且有期限的驗證連結，請到信箱完成驗證。驗證後帳號會進入管理員審核。';

  @override
  String get signupConsentTitle => '同意事項';

  @override
  String get signupAcceptTermsPrivacyPrefix => '我已閱讀並同意';

  @override
  String get signupConsentAnd => '與';

  @override
  String get signupAcceptNotifications => '我同意接收安全警示與審核通知';

  @override
  String get signupAcceptAiTermsPrefix => '我了解並同意';

  @override
  String get signupConsentRequirement => '需勾選三項同意內容後才能送出申請。';

  @override
  String get emailVerificationTitle => '驗證電子郵件';

  @override
  String get emailVerificationChecking => '正在確認驗證連結。此連結只能使用一次，並會在期限後失效。';

  @override
  String get emailVerificationMissingOrInvalid => '此驗證連結無效或缺少 token。你可以重新寄送驗證信。';

  @override
  String get emailVerificationExpired => '此驗證連結已過期。請重新寄送驗證信。';

  @override
  String get emailVerificationUsed => '此驗證連結已使用過。若帳號仍無法登入，請重新寄送驗證信或聯絡管理員。';

  @override
  String get emailVerificationGenericError => '驗證時發生錯誤，請稍後再試。';

  @override
  String get emailVerificationVerified => '電子郵件已驗證完成，請回到登入頁繼續使用。';

  @override
  String get emailVerificationPendingApproval => '電子郵件已驗證完成，帳號正在等待管理員審核。';

  @override
  String get emailVerificationEnterEmail => '請輸入註冊用電子郵件。';

  @override
  String get emailVerificationResend => '重新寄送驗證信';

  @override
  String get emailVerificationResendSent => '如果此電子郵件已註冊且尚未驗證，驗證信已寄出。請檢查收件匣或垃圾郵件。';

  @override
  String get notificationDiagnosticsTitle => '通知狀態檢查';

  @override
  String get notificationMissingUserId => '尚未取得使用者 ID，請重新登入。';

  @override
  String get notificationTokenUploaded => 'FCM token 已重新上傳。';

  @override
  String get notificationSignInBeforeTest => '尚未登入，無法送出測試通知。';

  @override
  String get notificationTestSent => '已送出測試通知。';

  @override
  String get notificationFirebaseLabel => 'Firebase 初始化';

  @override
  String get notificationConfigured => '已完成';

  @override
  String get notificationNotConfigured => '未完成';

  @override
  String get notificationPermission => '通知權限';

  @override
  String get notificationLastUpload => '最近上傳';

  @override
  String get notificationMissing => '未設定';

  @override
  String get notificationServiceWorker => 'Service worker';

  @override
  String get notificationUploadToken => '重新上傳 token';

  @override
  String get notificationTestNotification => '測試通知';

  @override
  String get notificationCenterTitle => '通知中心';

  @override
  String notificationLoadMoreFailed(String error) {
    return '載入更多通知失敗：$error';
  }

  @override
  String notificationMarkReadFailed(String error) {
    return '標記已讀失敗：$error';
  }

  @override
  String notificationMarkAllReadFailed(String error) {
    return '全部標記已讀失敗：$error';
  }

  @override
  String notificationOpenFailed(String error) {
    return '通知連結無法開啟：$error';
  }

  @override
  String get notificationFilterAll => '全部';

  @override
  String get notificationFilterUnread => '未讀';

  @override
  String get notificationFilterSignature => '簽核';

  @override
  String get notificationFilterViolation => '違規';

  @override
  String get notificationFilterDocument => '文件';

  @override
  String get notificationFilterSystem => '系統';

  @override
  String get notificationJustNow => '剛剛';

  @override
  String notificationMinutesAgo(int minutes) {
    return '$minutes 分鐘前';
  }

  @override
  String notificationHoursAgo(int hours) {
    return '$hours 小時前';
  }

  @override
  String notificationDaysAgo(int days) {
    return '$days 天前';
  }

  @override
  String get notificationMarkAllRead => '全部標記已讀';

  @override
  String notificationUnreadCount(int count) {
    return '$count 則未讀';
  }

  @override
  String get notificationNoUnread => '無未讀';

  @override
  String get notificationEmpty => '目前沒有通知';

  @override
  String get notificationLoadFailed => '通知載入失敗';

  @override
  String get notificationFallbackTitle => '通知';

  @override
  String get violationNoMatchingRecords => '沒有符合條件的紀錄';

  @override
  String get violationRecordsTab => '紀錄';

  @override
  String get violationAnalyticsTab => '統計';

  @override
  String get violationGroup => '群組';

  @override
  String get violationAllGroups => '所有群組';

  @override
  String get violationRangeLastDay => '過去一天';

  @override
  String get violationRangeLast30Days => '過去30天';

  @override
  String get violationRangeLastHalfYear => '過去半年';

  @override
  String get violationRangeLastYear => '過去一年';

  @override
  String get violationRangeYearToDate => '年初至今';

  @override
  String get violationUnnamedGroup => '未命名群組';

  @override
  String get reviewFilterAll => '全部';

  @override
  String get reviewFilterFlagged => '被標記';

  @override
  String get reviewFilterPending => '待審';

  @override
  String get reviewFilterResolved => '已處理';

  @override
  String get reviewFilterDismissed => '已忽略';

  @override
  String get reviewStatusReviewed => '已審';

  @override
  String get reviewStatusNotSubmitted => '未提交';

  @override
  String get reviewFlagReasonLabel => '標記原因';

  @override
  String get reviewSectionTitle => '審核處理';

  @override
  String get reviewFlaggedBadge => '被標記';

  @override
  String get reviewPendingNote => '待審備註';

  @override
  String get reviewNote => '審核備註';

  @override
  String get reviewHandled => '處理紀錄';

  @override
  String get reviewNoteOptional => '審核備註，可選';

  @override
  String get reviewAuditTrail => '審核歷史';

  @override
  String reviewAuditTrailLoadFailed(String error) {
    return '目前無法載入審核歷史：$error';
  }

  @override
  String get reviewAuditTrailEmpty => '目前沒有審核歷史。';

  @override
  String get overlayLabel => '覆蓋層';

  @override
  String get overlayHidden => '關閉';

  @override
  String get overlayAll => '全部';

  @override
  String get overlayFlaggedOnly => '只標記';

  @override
  String get reviewChangeMarkerColor => '切換標記顏色';

  @override
  String get reviewActionResolve => '標為已處理';

  @override
  String get reviewActionDismiss => '標為忽略';

  @override
  String get reviewActionPending => '退回待審';

  @override
  String get reviewMissingRecordUpdate => '找不到這筆紀錄的 ID，無法更新審核狀態。';

  @override
  String get reviewSignInRequiredUpdate => '尚未登入，無法更新審核狀態。';

  @override
  String get reviewUpdated => '審核狀態已更新。';

  @override
  String get reviewUpdatedNext => '審核狀態已更新，前往下一筆待審。';

  @override
  String reviewUpdateFailed(String error) {
    return '審核更新失敗：$error';
  }

  @override
  String get reviewReasonFalsePositive => '標記誤判：偵測結果被回報為誤判';

  @override
  String get reviewReasonFalseNegative => '框選漏判：畫面中有漏掉的目標';

  @override
  String get reviewReasonWrongClass => '類別錯誤：偵測類別需要修正';

  @override
  String get reviewReasonBadBox => '框選位置錯誤：偵測框位置需要修正';

  @override
  String get detectionFeedbackTitle => '偵測結果回饋';

  @override
  String get detectionFeedbackDescription => '標記誤判或漏判，後端會收集成模型改善候選資料。';

  @override
  String get detectionFeedbackFalsePositive => '標記誤判';

  @override
  String get detectionFeedbackMissed => '框選漏判';

  @override
  String get detectionFeedbackNoBoxes => '目前沒有可點選的偵測框。';

  @override
  String get detectionFeedbackMissedLabel => '漏判類別';

  @override
  String get detectionFeedbackNoteOptional => '備註，可選';

  @override
  String get detectionFeedbackNoMissedTarget => '尚未框選漏判目標';

  @override
  String detectionFeedbackSelectedBox(String bbox) {
    return '已框選 $bbox';
  }

  @override
  String get detectionFeedbackSubmitMissed => '送出漏判';

  @override
  String get detectionFeedbackFalsePositiveHint => '請點選圖片中的錯誤偵測框。';

  @override
  String get detectionFeedbackMissedHint => '請在圖片中拖曳框出漏掉的目標。';

  @override
  String get detectionFeedbackBoxes => '可選框數';

  @override
  String get feedbackNoDetectionSelected => '沒有點到偵測框，請直接點框內。';

  @override
  String get feedbackSelectionTooSmall => '框選範圍太小，請重新框選。';

  @override
  String get feedbackFalsePositiveDialogTitle => '回報誤判';

  @override
  String get feedbackFalsePositiveDialogMessage => '這筆偵測會被標記為誤判，送出後可供後端審核與模型改善。';

  @override
  String get feedbackDrawMissedFirst => '請先在圖片中框選漏判目標。';

  @override
  String get feedbackMissingRecord => '找不到這筆紀錄的 ID，無法送出回饋。';

  @override
  String get feedbackSignInRequired => '尚未登入，無法送出回饋。';

  @override
  String get feedbackSubmitted => '已送出回饋，謝謝你的協助。';

  @override
  String feedbackSubmitFailed(String error) {
    return '回饋送出失敗：$error';
  }

  @override
  String get imageViewerTitle => '圖片瀏覽';

  @override
  String get imageViewerRotate => '旋轉';

  @override
  String get imageViewerResetZoom => '重設縮放';

  @override
  String get falsePositivePickerTitle => '選擇誤判項目';

  @override
  String get falsePositivePickerHint => '雙擊縮放，拖曳移動，點選框或文字標籤。';

  @override
  String get falsePositivePickerBottomHint => '點選標示框或標籤送出誤判';

  @override
  String get falsePositivePickerMiss => '沒有點到框或標籤，請放大後再點一次。';

  @override
  String get saveSuccess => '儲存成功。';

  @override
  String get editAuditFixDocTitle => '編輯缺失稽核改善';

  @override
  String get addAuditFixDocTitle => '新增缺失稽核改善';

  @override
  String get multiSelectAlbum => '從相簿選取';

  @override
  String get auditDateLabel => '稽核日期';

  @override
  String todayLabel(String date) {
    return '今日：$date';
  }

  @override
  String get addPhotoViaCamera => '使用相機或相簿新增照片';

  @override
  String get showDateLabel => '顯示日期戳記';

  @override
  String get dateLabel => '日期';

  @override
  String get descriptionLabel => '說明';

  @override
  String get descBeforeLabel => '改善前';

  @override
  String get descDuringLabel => '改善中';

  @override
  String get descAfterLabel => '改善後';

  @override
  String groupNumberLabel(String number) {
    return '第 $number 組';
  }

  @override
  String get applyDescriptionToAllGroups => '套用描述到後續群組';

  @override
  String doneWithCount(String count) {
    return '完成（$count）';
  }

  @override
  String loadFailedError(String error) {
    return '載入失敗：$error';
  }

  @override
  String get tryAgain => '重試';

  @override
  String pleaseSelectSignerFor(String field) {
    return '請為「$field」選擇簽核人員';
  }

  @override
  String get submitted => '已送出';

  @override
  String failedWith(String error) {
    return '失敗：$error';
  }

  @override
  String get editDocumentTitle => '編輯文件';

  @override
  String get headerSection => '表頭';

  @override
  String get bodySection => '內容';

  @override
  String get footerSection => '頁尾';

  @override
  String get saveAndSubmit => '儲存並送出';

  @override
  String tableLabel(String number) {
    return '表格 $number';
  }

  @override
  String get unnamedSite => '未命名工地';

  @override
  String get addImage => '新增圖片';

  @override
  String get tapToSign => '點擊簽名';

  @override
  String get signatureSection => '簽名';

  @override
  String get signatureFlow => '簽核流程';

  @override
  String get orderedSigningActive => '目前啟用依序簽核。';

  @override
  String get freeSigningActive => '目前啟用不限順序簽核。';

  @override
  String get signingOrderLocked => '簽核任務建立後，簽核順序已鎖定。';

  @override
  String get anyOrder => '不限順序';

  @override
  String get signInOrder => '依序簽核';

  @override
  String get orderedSigningDragHint => '送出前可拖曳簽核人員調整順序。';

  @override
  String get freeSigningHint => '所有被指派的簽核人員可不依固定順序簽核。';

  @override
  String get selectSignerHint => '選擇簽核人員';

  @override
  String orderRank(String rank) {
    return '順序 $rank';
  }

  @override
  String get signatureFieldLabel => '簽名欄位';

  @override
  String commentLabel(String comment) {
    return '備註：$comment';
  }

  @override
  String get sitesNotLoaded => '尚未載入工地資料。';

  @override
  String get documentListTitle => '文件列表';

  @override
  String get creatorLabel => '建立者';

  @override
  String get editorLabel => '編輯者';

  @override
  String get signerLabel => '簽核者';

  @override
  String get selectSiteFirstHint => '請先選擇工地以載入成員。';

  @override
  String get loadingMemberList => '正在載入成員...';

  @override
  String memberLoadFailed(String error) {
    return '成員載入失敗：$error';
  }

  @override
  String get noMemberListForSite => '此工地沒有可用成員。';

  @override
  String get uploadButton => '上傳';

  @override
  String allFilter(String label) {
    return '全部$label';
  }

  @override
  String get unclassified => '未分類';

  @override
  String get documentLocked => '文件已鎖定';

  @override
  String get mySignTasks => '我的簽核任務';

  @override
  String get browserDownloadStarted => '已開始瀏覽器下載。';

  @override
  String get storagePermissionRequired => '下載檔案需要儲存權限。';

  @override
  String get downloadComplete => '下載完成。';

  @override
  String downloadFailedError(String error) {
    return '下載失敗：$error';
  }

  @override
  String deleteVersionConfirm(String version) {
    return '確定刪除版本 $version 嗎？';
  }

  @override
  String get versionDeleted => '版本已刪除。';

  @override
  String deleteVersionFailedError(String error) {
    return '刪除版本失敗：$error';
  }

  @override
  String documentVersionListTitle(String document) {
    return '$document 的版本列表';
  }

  @override
  String versionNumber(String version) {
    return '版本 $version';
  }

  @override
  String get downloadDocx => '下載 DOCX';

  @override
  String get downloadPdf => '下載 PDF';

  @override
  String get pdfConverting => 'PDF 轉換中';

  @override
  String get deleteVersionTooltip => '刪除版本';

  @override
  String get pdfNotReady => 'PDF 尚未準備完成';

  @override
  String get addPhotoDocTitle => '新增圖片文件';

  @override
  String get editPhotoDocTitle => '編輯圖片文件';

  @override
  String get requiredSelect => '請選擇項目';

  @override
  String get projectNameLabel => '工程名稱';

  @override
  String get addPhotosHint => '請拍照或從相簿選取圖片。';

  @override
  String get locationLabel => '位置';

  @override
  String get applyImageDataToAll => '套用圖片資料到後續項目';

  @override
  String get notificationSettings => '通知設定';

  @override
  String get siteNotificationTitle => '工地通知';

  @override
  String get siteNotificationDescription => '選擇要接收的工地警示通知。';

  @override
  String get noSiteNotification => '目前沒有工地通知項目。';

  @override
  String get notificationSearchHint => '搜尋通知設定';

  @override
  String get siteNotificationSaveSuccess => '工地通知設定已儲存。';

  @override
  String get documentNotificationTitle => '文件通知';

  @override
  String get documentNotificationDescription => '選擇要接收的文件流程通知。';

  @override
  String get noDocumentNotification => '目前沒有文件通知項目。';

  @override
  String get documentNotificationSaveSuccess => '文件通知設定已儲存。';

  @override
  String get siteNotificationChannel => '工地警示';

  @override
  String get documentNotificationChannel => '文件流程';

  @override
  String notificationSaveFailed(String error) {
    return '通知設定儲存失敗：$error';
  }

  @override
  String get notificationSearchEmpty => '沒有符合搜尋條件的通知設定。';

  @override
  String get allSiteGroups => '所有工地群組';

  @override
  String get notificationEnabled => '已啟用';

  @override
  String get notificationPendingSave => '待儲存';

  @override
  String get notificationStatus => '狀態';

  @override
  String get notificationSaving => '儲存中';

  @override
  String get notificationSynced => '已同步';

  @override
  String get enableAllNotifications => '全部啟用';

  @override
  String get disableAllNotifications => '全部停用';

  @override
  String get saveNotificationChanges => '儲存變更';

  @override
  String get notificationAlreadySynced => '已同步';

  @override
  String notificationEnabledCount(String enabled, String total) {
    return '已啟用 $enabled/$total';
  }

  @override
  String get notificationUnsaved => '尚未儲存';

  @override
  String get pendingSignStatus => '待簽核';

  @override
  String get signedStatus => '已簽核';

  @override
  String get commentedStatus => '已註記';

  @override
  String get skippedStatus => '已跳過';

  @override
  String get rejectedStatus => '已退回';

  @override
  String get commentedStatusDescription => '以註記退回修正。';

  @override
  String get skippedStatusDescription => '跳過此簽核步驟。';

  @override
  String get rejectedStatusDescription => '退回此文件。';

  @override
  String get signedStatusDescription => '簽名並通過此步驟。';

  @override
  String get chooseDocumentTypeTitle => '選擇文件類型';

  @override
  String get documentTypeSearchHint => '搜尋文件類型';

  @override
  String get noAvailableCategories => '沒有可用分類';

  @override
  String get noMatchingDocumentTypes => '沒有符合的文件類型';

  @override
  String get documentTypePrefixUnset => '未設定前綴';

  @override
  String documentTypePrefixValue(String prefix) {
    return '前綴：$prefix';
  }

  @override
  String get approveUser => '核准使用者';

  @override
  String get selectGroupForUser => '請為此使用者選擇群組。';

  @override
  String get statusPending => '待審核';

  @override
  String get pendingApprovalTitle => '等待審核';

  @override
  String get pendingApprovalMessage => '你的帳號正在等待管理員審核。';

  @override
  String get signDocument => '簽核文件';

  @override
  String get goToMyTasks => '前往我的任務';

  @override
  String loadSignTaskFailed(String error) {
    return '簽核任務載入失敗：$error';
  }

  @override
  String get signTaskNotFound => '找不到簽核任務。';

  @override
  String signTaskLoadFailed(String error) {
    return '簽核任務載入失敗：$error';
  }

  @override
  String get pleaseSignFirst => '請先完成簽名再送出。';

  @override
  String submitFailed(String error) {
    return '送出失敗：$error';
  }

  @override
  String get documentVersionUpdated => '文件版本已更新，請重新載入。';

  @override
  String get revisionCommentLabel => '修正註記';

  @override
  String get revisionCommentHint => '請說明需要修正的內容。';

  @override
  String get rejectionReasonLabel => '退回原因';

  @override
  String get rejectionReasonHint => '請說明退回原因。';

  @override
  String get signAction => '簽核';

  @override
  String get commentAction => '註記';

  @override
  String get skipAction => '跳過';

  @override
  String get rejectAction => '退回';

  @override
  String get signResult => '簽核結果';

  @override
  String get handwrittenSignature => '手寫簽名';

  @override
  String get resignature => '重新簽名';

  @override
  String get signatureConfirmed => '簽名已確認。';

  @override
  String get confirmSignature => '確認簽名';

  @override
  String get signaturePreview => '簽名預覽';

  @override
  String get confirmSubmit => '確認送出';

  @override
  String get startSign => '開始簽核';

  @override
  String get signatureHint => '請提供簽名。';

  @override
  String get noSignTasks => '目前沒有簽核任務。';

  @override
  String get createdTime => '建立時間';

  @override
  String taskNumberStatus(String taskId, String status) {
    return '任務 $taskId · $status';
  }

  @override
  String versionPlaceholder(String version, String placeholder) {
    return '版本 $version · $placeholder';
  }

  @override
  String pdfLoadFailed(String error) {
    return 'PDF 載入失敗：$error';
  }

  @override
  String get commentRequired => '此操作需要填寫註記。';
}

/// The translations for Chinese, as used in China (`zh_CN`).
class AppLocalizationsZhCn extends AppLocalizationsZh {
  AppLocalizationsZhCn(): super('zh_CN');

  @override
  String get appTitle => 'Visionnaire 應用程式';

  @override
  String get deviceLang => 'zh-CN';

  @override
  String get login => '登入';

  @override
  String get username => '用戶名';

  @override
  String get password => '密碼';

  @override
  String get chatList => '聊天列表';

  @override
  String get chatTitleCannotBeEmpty => '聊天標題不能為空或僅包含空格';

  @override
  String get cameraList => '監視器串流';

  @override
  String get detection => '物件偵測';

  @override
  String get logout => '登出';

  @override
  String get changeLanguage => '切換語言';

  @override
  String get site => '工地';

  @override
  String get stream => '串流';

  @override
  String get detectionTime => '偵測時間';

  @override
  String get violationMessage => '違規訊息';

  @override
  String get loadingImageError => '無法載入影像';

  @override
  String get violationRecordQuery => '違規紀錄查詢';

  @override
  String get keyword => '關鍵字 (stream_name 或訊息)';

  @override
  String get startTime => '開始時間';

  @override
  String get endTime => '結束時間';

  @override
  String get query => '查詢';

  @override
  String get noRecords => '目前尚無標籤資料';

  @override
  String get streamingWebSettings => '即时影像';

  @override
  String get streamingWebUrl => 'Streaming Web URL (含 http:// 或 https://)';

  @override
  String get save => '儲存';

  @override
  String get goToLabels => '前往地点列表';

  @override
  String get currentUrl => '目前 URL';

  @override
  String get labelList => '地点';

  @override
  String get label => '標籤';

  @override
  String get noImage => '尚無攝影機畫面資料';

  @override
  String get warnings => '警告訊息';

  @override
  String get lastUpdated => '最後更新時間';

  @override
  String get noWarnings => '沒有警告訊息';

  @override
  String get detectionResult => '偵測結果';

  @override
  String get chooseModel => '選擇模型';

  @override
  String get noImageSelected => '尚未選擇圖片';

  @override
  String get noDetectionResult => '尚無偵測結果';

  @override
  String get takePhoto => '拍照';

  @override
  String get photoLibrary => '相簿';

  @override
  String get startDetection => '開始偵測';

  @override
  String get cannotOpenCamera => '無法開啟相機';

  @override
  String get cannotOpenGallery => '無法開啟相簿';

  @override
  String get getImageSizeFailed => '取得圖片尺寸失敗';

  @override
  String get notLoggedIn => '尚未登入 (偵測服務 Token 無效)';

  @override
  String get tokenRefreshFailed => 'Token 刷新失敗';

  @override
  String get chatLoadFailed => '載入對話失敗';

  @override
  String get chatRoom => '對話房';

  @override
  String get inputMessage => '輸入訊息...';

  @override
  String get newChatRoom => '新聊天室';

  @override
  String get enterChatRoomTitle => '輸入聊天室標題';

  @override
  String get create => '創建';

  @override
  String get createFailed => '創建失敗';

  @override
  String get confirmDeleteChatRoom => '你確定要刪除此聊天房間嗎？';

  @override
  String get cancel => '取消';

  @override
  String get delete => '刪除';

  @override
  String get deleteFailed => '刪除失敗';

  @override
  String get selectSite => '選擇工地';

  @override
  String get notSelected => '未選擇';

  @override
  String errorPrefix(String error) {
    return '錯誤：';
  }

  @override
  String get sitePrefix => '工地：';

  @override
  String get streamPrefix => '串流：';

  @override
  String get detectionTimePrefix => '偵測時間：';

  @override
  String get urlUpdated => '已更新 Streaming Web Base URL 為：';

  @override
  String get streamingWebIndexTitle => '地点';

  @override
  String get unknownError => '未知錯誤';

  @override
  String get noLabels => '目前尚無標籤資料';

  @override
  String get chatMessageCannotBeEmpty => '不可輸入空問題';

  @override
  String get editQuestionHint => '請輸入新的問題';

  @override
  String get confirm => '確定';

  @override
  String get editQuestion => '編輯問題';

  @override
  String get regenerateAnswer => '重新生成答案';

  @override
  String get removeQuestionChain => '移除問題(含後續對話)';

  @override
  String get failedToLoadHistory => '載入歷史失敗';

  @override
  String get failedToLoadHistoryAfterRefresh => '刷新後仍載入歷史失敗';

  @override
  String get failedToAskAfterRefresh => '刷新後提問失敗';

  @override
  String get editFailed => '編輯失敗';

  @override
  String get editFailedAfterRefresh => '刷新後仍編輯失敗';

  @override
  String get regenerateFailed => '重新生成失敗';

  @override
  String get regenerateFailedAfterRefresh => '刷新後仍重新生成失敗';

  @override
  String get removeFailed => '移除失敗';

  @override
  String get removeFailedAfterRefresh => '刷新後仍移除失敗';

  @override
  String get sendMessage => '发送消息';

  @override
  String get addImages => '新增图片';

  @override
  String get addFiles => '新增文件';

  @override
  String attachmentCount(int count) {
    return '$count 个附件';
  }

  @override
  String get cancelGeneration => '取消生成';

  @override
  String get createChatRoom => '创建聊天室';

  @override
  String attachmentUploadFailed(String error) {
    return '上传附件失败：$error';
  }

  @override
  String attachmentDeleteFailed(String error) {
    return '删除附件失败：$error';
  }

  @override
  String get selectLabel => '选择标签';

  @override
  String get showDetectionResults => '显示识别结果';

  @override
  String get hardhat => '安全帽';

  @override
  String get vest => '背心';

  @override
  String get machinery => '機具';

  @override
  String get vehicle => '車輛';

  @override
  String get no_hardhat => '無安全帽';

  @override
  String get no_vest => '無安全背心';

  @override
  String get person => '人員';

  @override
  String get cone => '安全錐';

  @override
  String get mask => '口罩';

  @override
  String get no_mask => '無口罩';

  @override
  String get utility_pole => '電桿';

  @override
  String warning_people_in_controlled_area(int count) {
    return '警告：$count 人進入受控區域！';
  }

  @override
  String warning_people_in_utility_pole_controlled_area(int count) {
    return '警告：$count 人進入電桿受控區域！';
  }

  @override
  String warning_no_hardhat(int count) {
    return '警告: 有$count人未佩戴安全帽！';
  }

  @override
  String warning_no_safety_vest(int count) {
    return '警告: 有$count人未穿著安全背心！';
  }

  @override
  String warning_close_to_machinery(int count) {
    return '警告：$count 人靠近機具！';
  }

  @override
  String warning_close_to_vehicle(int count) {
    return '警告：$count 人靠近車輛！';
  }

  @override
  String detect_machinery_close_to_pole(int count) {
    return '警告：$count 台機具靠近電桿！';
  }

  @override
  String get showOverlay => '顯示覆蓋層';
}
