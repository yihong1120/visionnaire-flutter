part of 'chat_page.dart';

abstract class _ChatPageStateBase extends State<ChatPage> {
  final _api = ChatAPIService();
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  // Actual chat ID (can be updated after first message for new chats)
  int? _actualChatId;
  List<Map<String, dynamic>> _messages = [];
  int? _editingId;
  final _editCtl = TextEditingController();

  bool _isBusy = false;
  bool _isLoadingHistory = false;
  String? _error;

  // Streaming state
  String? _streamingAnswer; // Accumulating answer during streaming

  // HTTP client for the active stream — close it to abort (cancel).
  http.Client? _streamClient;
  bool _isCancelling = false;

  // Interrupt state for the current in-flight generation: 'running' | null
  String? _runState;

  // Show a floating button to jump to bottom when the user is scrolled up
  bool _showScrollToBottom = false;

  // Avoid jitter/overscroll by preventing competing programmatic scrolls.
  bool _isAnimatingToBottom = false;
  bool _isAutoScrollingToBottom = false;
  bool _hasPendingScrollToBottom = false;
  DateTime? _lastUserScrollAt;

  // Whether the viewport is currently at bottom (used to decide keyboard push).
  bool _isAtBottom = true;
  static const double _scrollBottomThreshold = 120; // px
  static const double _autoScrollBottomThreshold = 32; // px
  static const Duration _userScrollSettleDuration = Duration(milliseconds: 180);

  // (knowledge-source references removed — not supported by new orchestrator backend)

  // Image attachments (ChatGPT-like)
  final List<ChatAttachment> _draftAttachments = [];
  final List<ChatEditingAttachment> _editingAttachments = [];

  // Image bytes cache (avoid refetch on scroll)
  final Map<String, Uint8List> _attachmentImageCache = {};

  bool get _isPhoneLayout {
    final size = MediaQuery.sizeOf(context);
    return size.shortestSide < 600;
  }

  bool get _hasActiveComposition {
    final composing = _controller.value.composing;
    return composing.isValid && !composing.isCollapsed;
  }

  // ---- Cross-part method contracts (implemented by mixins / concrete state) ----
  // Scroll / input
  void _handleSend();
  void _scrollToBottom({bool force = false});
  Future<void> _animateToBottom();
  void _handleInputTap();
  bool _handleScrollNotification(ScrollNotification notification);

  // Attachments / downloads
  Future<Uint8List> _getAttachmentBytes(String url);
  Future<void> _pickImages({bool forEditing});
  Future<void> _pickFiles({bool forEditing});
  Future<void> _uploadPickedFiles(List<LocalAttachmentBytes> files);
  Future<void> _downloadWithAuth(Uri uri);
  void _handleFileTap(Map<String, dynamic> attachment);

  // Streaming
  Future<void> _handleStreamEvent(Map<String, dynamic> event);
  Future<void> _cancelStream();

  // Chat actions
  void _startEdit(int id, String text, List<dynamic>? attachments);
  void _cancelEdit();
  Future<void> _confirmEdit(int qId);
  Future<void> _regenerate(int qId);
  Future<void> _remove(int msgId);

  // Sheets / UI helpers
  Future<void> _openSourcesSideSheet(List<Map<String, dynamic>> sources);
  void _showImageViewer(
    BuildContext context, {
    Uint8List? imageBytes,
    Map<String, dynamic>? attachment,
  });
  Widget _userActions(Map<String, dynamic> m);
}

class _ChatPageState extends _ChatPageStateBase
    with
        _ChatPageScroll,
        _ChatPageStreaming,
        _ChatPageAttachments,
        _ChatPageActions,
        _ChatPageSheets,
        _ChatPageView {
  @override
  void initState() {
    super.initState();
    _actualChatId = widget.chatId;

    if (_actualChatId != null) {
      _isLoadingHistory = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadHistory();

        final pq = widget.pendingQuestion;
        if (pq != null && pq.trim().isNotEmpty) {
          _controller.text = pq;
          _send();
        }
      });
    }

    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    _editCtl.dispose();
    _inputFocusNode.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void _handleSend() {
    if (_isBusy || _hasActiveComposition) return;
    if (_actualChatId == null) {
      _createAndNavigate();
    } else {
      _send();
    }
  }

  @override
  Widget build(BuildContext context) => _buildChatPage(context);
}
