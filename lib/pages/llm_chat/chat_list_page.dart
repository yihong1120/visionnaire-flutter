import 'package:flutter/material.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

import '../../services/chat_api_service.dart';
import '../../widgets/responsive_scaffold.dart';
import '../../widgets/app_transitions.dart';
import '../../utils/auth_utils.dart';
import 'chat_page.dart';

class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  final _api = ChatAPIService();

  List<Map<String, dynamic>> _rooms = [];
  String? _error;
  bool _isLoading = false;
  // Currently selected room for wide-screen split view
  // Default to new chat (id: null)
  Map<String, dynamic>? _selectedRoom = {'id': null, 'title': ''};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchChats());
  }

  /* ---------------- 取得聊天室 ---------------- */
  Future<void> _fetchChats() async {
    final local = AppLocalizations.of(context)!;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await AuthUtils.withAuthRetry(
          context, (token) => _api.getChats(token),
          notLoggedInMessage: local.notLoggedIn);
      if (!mounted) return;
      setState(() => _rooms = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = "${local.chatLoadFailed}: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /* ---------------- 建立聊天室 ---------------- */
  Future<void> _createChat() async {
    // Directly open a new blank chat page without dialog
    final isWide = MediaQuery.of(context).size.width >= 900;

    if (isWide) {
      // In wide mode, set selected room to null which will show blank chat
      setState(() {
        _selectedRoom = {
          'id': null,
          'title': '',
        };
      });
    } else {
      // In narrow mode, navigate to new chat page
      pushAppPage<void>(
        context,
        builder: (_) => ChatPage(
          chatId: null,
          title: '',
          isEmbedded: false,
          onMessageSent: (newChatId, newChatTitle,
              {String? pendingQuestion}) async {
            // Refresh chat list when message is sent
            await _fetchChats();
          },
        ),
      ).then((_) {
        // Refresh chat list after returning
        _fetchChats();
      });
    }
  }

  /* ---------------- 編輯聊天室 ---------------- */
  Future<void> _editChat(int roomId, int index, String currentTitle) async {
    final local = AppLocalizations.of(context)!;
    final ctl = TextEditingController(text: currentTitle);

    final newTitle = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(local.edit),
        content: TextField(
          controller: ctl,
          decoration: InputDecoration(hintText: local.enterChatRoomTitle),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(local.cancel),
          ),
          TextButton(
            onPressed: () {
              final title = ctl.text.trim();
              if (title.isEmpty) {
                return;
              }
              Navigator.pop(context, title);
            },
            child: Text(local.confirm),
          ),
        ],
      ),
    );

    if (newTitle == null || newTitle == currentTitle) return;

    if (!mounted) return;

    try {
      await AuthUtils.withAuthRetry(
        context,
        (token) => _api.updateRoom(token, roomId, newTitle),
      );
      if (!mounted) return;
      setState(() {
        _rooms[index]['title'] = newTitle;
        if (_selectedRoom != null && _selectedRoom!['id'] == roomId) {
          _selectedRoom!['title'] = newTitle;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('聊天室名稱已更新')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("更新失敗: $e")),
        );
      }
    }
  }

  /* ---------------- 刪除聊天室 ---------------- */
  Future<void> _confirmDelete(int roomId, int index) async {
    final local = AppLocalizations.of(context)!;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(local.chatList),
        content: Text(local.confirmDeleteChatRoom),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(local.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(local.delete),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;

    try {
      await AuthUtils.withAuthRetry(
        context,
        (token) => _api.deleteRoom(token, roomId),
      );
      if (!mounted) return;
      setState(() {
        _rooms.removeAt(index);

        // Auto-navigation logic after deletion
        final isWide = MediaQuery.of(context).size.width >= 900;
        if (_rooms.isEmpty) {
          // If list is empty, go to new chat
          if (isWide) {
            _selectedRoom = {'id': null, 'title': ''};
          } else {
            _createChat();
          }
        } else {
          // If list is not empty, switch to the newest (top) chat
          // This is primarily for wide mode to ensure we don't stay on a deleted chat
          // or an arbitrary one.
          if (isWide) {
            _selectedRoom = _rooms.first;
          }
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("${local.deleteFailed}: $e")),
        );
      }
    }
  }

  /* ---------------- UI ---------------- */
  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context)!;

    Widget buildRoomList({required bool isWide}) {
      final list = _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  itemCount: _rooms.length,
                  itemBuilder: (ctx, idx) {
                    final ColorScheme colors = Theme.of(ctx).colorScheme;
                    final room = _rooms[idx];
                    final selected = isWide &&
                        _selectedRoom != null &&
                        _selectedRoom!['id'] == room['id'];
                    return ListTile(
                      selected: selected,
                      title: Text(room['title'] ?? ''),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.edit, color: colors.tertiary),
                            tooltip: local.edit,
                            onPressed: () => _editChat(
                              room['id'] as int,
                              idx,
                              room['title'] as String? ?? '',
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, color: colors.error),
                            tooltip: local.delete,
                            onPressed: () =>
                                _confirmDelete(room['id'] as int, idx),
                          ),
                        ],
                      ),
                      onTap: () {
                        if (isWide) {
                          setState(() => _selectedRoom = room);
                        } else {
                          pushAppPage<void>(
                            context,
                            builder: (_) => ChatPage(
                              chatId: room['id'] as int,
                              title: room['title'] ?? '',
                              isEmbedded: false,
                              onMessageSent: (_, __,
                                  {String? pendingQuestion}) {
                                // Just refresh list for existing chats
                                _fetchChats();
                              },
                            ),
                          );
                        }
                      },
                    );
                  },
                );

      return list;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide =
            constraints.maxWidth >= 900; // breakpoint for desktop/tablet

        if (!isWide) {
          return ResponsiveScaffold(
            title: local.chatList,
            floatingActionButton: FloatingActionButton(
              heroTag: null,
              onPressed: _createChat,
              child: const Icon(Icons.add),
            ),
            body: buildRoomList(isWide: false),
          );
        }

        // Wide web: use a website-style global top navigation. The left pane
        // is the chat room browser only; all app-wide destinations live in the
        // shared web navigation bar.
        return WebWorkspaceScaffold(
          body: Builder(
            builder: (context) {
              final leftPane = Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            local.chatList,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          onPressed: _createChat,
                          icon: const Icon(Icons.add),
                          tooltip: local.newChatRoom,
                        ),
                        IconButton(
                          onPressed: _fetchChats,
                          icon: const Icon(Icons.refresh),
                          tooltip: local.refresh,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: buildRoomList(isWide: true)),
                ],
              );

              final rightPane = _selectedRoom == null
                  ? Center(
                      child: Text(
                        'Select a chat room',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    )
                  : ChatPage(
                      // Use chatId as key to force rebuild when entering new chat
                      key: ValueKey(_selectedRoom!['id']),
                      chatId: _selectedRoom!['id'] as int?,
                      title: _selectedRoom!['title'] as String? ?? '',
                      isEmbedded: true,
                      // Pass pendingQuestion if available
                      pendingQuestion:
                          _selectedRoom!['pendingQuestion'] as String?,
                      onMessageSent: (newChatId, newChatTitle,
                          {String? pendingQuestion}) async {
                        final wasNewChat = _selectedRoom!['id'] == null;

                        // Refresh chat list when message is sent
                        await _fetchChats();

                        // If this was a new chat creation, navigate into the new chat
                        if (wasNewChat && newChatId != null && mounted) {
                          setState(() {
                            _selectedRoom = {
                              'id': newChatId,
                              'title': newChatTitle ?? '',
                              // Pass pending question so it can be auto-sent
                              'pendingQuestion': pendingQuestion,
                            };
                          });
                        }
                      },
                    );

              return Row(
                children: [
                  SizedBox(
                    width: 320,
                    child: Material(
                      color: Theme.of(context).colorScheme.surface,
                      elevation: 1,
                      child: leftPane,
                    ),
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: rightPane),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
