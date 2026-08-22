import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart'
    as http; // needed by chat_page_state.dart for _streamClient
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

import '../../services/chat_api_service.dart';
import '../../services/auth_request_headers.dart';
import '../../theme/app_motion.dart';
import '../../utils/authenticated_http.dart';
import '../../utils/auth_utils.dart';
import '../../utils/authenticated_uri.dart';
import '../../utils/cross_platform_download.dart' as cp;
import '../../widgets/app_transitions.dart';
import '../../widgets/web_selectable_content.dart';
import 'chat_citations_panel.dart';
import 'models/chat_attachment_model.dart';
import 'utils/chat_utils.dart';
import 'utils/file_saver.dart';
import 'widgets/chat_attachment_image.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/chat_floating_circle_button.dart';
import 'widgets/chat_image_viewer_dialog.dart';
import 'widgets/chat_input_area.dart';
import 'widgets/chat_messages_list.dart';
import 'widgets/chat_welcome_screen.dart';

part 'chat_page_actions.dart';
part 'chat_page_attachments.dart';
part 'chat_page_scroll.dart';
part 'chat_page_sheets.dart';
part 'chat_page_state.dart';
part 'chat_page_streaming.dart';
part 'chat_page_view.dart';

class ChatPage extends StatefulWidget {
  final int? chatId; // null means new chat
  final String title;

  /// If provided, this question will be sent immediately after entering
  /// a newly created chat (standalone mode navigation).
  final String? pendingQuestion;

  /// Whether this page is embedded in a split view (true) or standalone (false)
  final bool isEmbedded;

  /// Callback when a new message is successfully sent (e.g., to refresh chat list)
  /// For new chats, passes the chat ID, title, and optional pending question;
  /// otherwise passes null values
  final void Function(int? newChatId, String? newChatTitle,
      {String? pendingQuestion})? onMessageSent;

  const ChatPage({
    super.key,
    this.chatId,
    this.title = '',
    this.isEmbedded = false,
    this.onMessageSent,
    this.pendingQuestion,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}
