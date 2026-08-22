import 'package:flutter/material.dart';

class ChatMessagesList extends StatelessWidget {
  final bool isPhone;
  final int? actualChatId;
  final bool isLoadingHistory;
  final List<Map<String, dynamic>> messages;
  final ScrollController scrollController;
  final int? editingId;
  final Widget welcome;
  final Widget Function(Map<String, dynamic> message, int? pairedQuestionId)
      bubbleBuilder;
  final Widget Function(Map<String, dynamic> message) userActionsBuilder;

  const ChatMessagesList({
    super.key,
    required this.isPhone,
    required this.actualChatId,
    required this.isLoadingHistory,
    required this.messages,
    required this.scrollController,
    required this.editingId,
    required this.welcome,
    required this.bubbleBuilder,
    required this.userActionsBuilder,
  });

  List<int?> _pairedQuestionIdsByIndex() {
    final List<int?> pairedIds =
        List<int?>.filled(messages.length, null, growable: false);
    int? latestUserMessageId;

    for (int index = 0; index < messages.length; index++) {
      final Map<String, dynamic> message = messages[index];
      if (message['role'] == 'user') {
        final dynamic id = message['id'];
        if (id is int) latestUserMessageId = id;
        continue;
      }
      pairedIds[index] = latestUserMessageId;
    }

    return pairedIds;
  }

  @override
  Widget build(BuildContext context) {
    if (actualChatId != null && isLoadingHistory) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }

    if (messages.isEmpty && actualChatId == null) {
      return welcome;
    }

    final List<int?> pairedQuestionIds = _pairedQuestionIdsByIndex();

    if (isPhone) {
      return ListView.separated(
        reverse: true,
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: messages.length,
        separatorBuilder: (_, idx) {
          final realIdx = messages.length - 1 - idx;
          final isEditing = messages[realIdx]['role'] == 'user' &&
              messages[realIdx]['id'] == editingId;
          return SizedBox(height: isEditing ? 16 : 10);
        },
        itemBuilder: (_, idx) {
          final realIdx = messages.length - 1 - idx;
          final m = messages[realIdx];
          final isUser = m['role'] == 'user';
          final int? pairedQId = pairedQuestionIds[realIdx];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              bubbleBuilder(m, pairedQId),
              if (isUser) const SizedBox(height: 5),
              if (isUser) userActionsBuilder(m),
            ],
          );
        },
      );
    }

    return ListView.separated(
      controller: scrollController,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length,
      separatorBuilder: (_, idx) {
        final isEditing =
            messages[idx]['role'] == 'user' && messages[idx]['id'] == editingId;
        return SizedBox(height: isEditing ? 16 : 10);
      },
      itemBuilder: (_, idx) {
        final m = messages[idx];
        final isUser = m['role'] == 'user';
        final int? pairedQId = pairedQuestionIds[idx];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bubbleBuilder(m, pairedQId),
            if (isUser) const SizedBox(height: 5),
            if (isUser) userActionsBuilder(m),
          ],
        );
      },
    );
  }
}
