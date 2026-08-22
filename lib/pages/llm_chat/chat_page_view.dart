part of 'chat_page.dart';

mixin _ChatPageView on _ChatPageStateBase {
  Widget _buildChatPage(BuildContext context) {
    final local = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.of(context).size.width >= 1100;
    final isPhone = MediaQuery.sizeOf(context).shortestSide < 600;
    final showBackButton = !widget.isEmbedded;

    final bool useMobileEnterForNewline = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);

    final topInset = MediaQuery.viewPaddingOf(context).top;

    return Scaffold(
      resizeToAvoidBottomInset: isPhone && _editingId == null && _isAtBottom,
      backgroundColor: scheme.surfaceContainerHigh,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.only(top: topInset),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      color: scheme.surfaceContainerHigh,
                      child: Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: wide ? 24 : 12),
                        child: Column(
                          children: [
                            if (_error != null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: scheme.errorContainer,
                                  border: Border(
                                    left: BorderSide(
                                      color: scheme.error,
                                      width: 4,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _error!,
                                  style:
                                      TextStyle(color: scheme.onErrorContainer),
                                ),
                              ),
                            Expanded(
                              child: Stack(
                                children: [
                                  NotificationListener<ScrollNotification>(
                                    onNotification: _handleScrollNotification,
                                    child: WebSelectableContent(
                                      enabled: !widget.isEmbedded,
                                      child: ChatMessagesList(
                                        isPhone: isPhone,
                                        actualChatId: _actualChatId,
                                        isLoadingHistory: _isLoadingHistory,
                                        messages: _messages,
                                        scrollController: _scroll,
                                        editingId: _editingId,
                                        welcome: ChatWelcomeScreen(
                                          onPromptSelected: (text) {
                                            _controller.text = text;
                                          },
                                        ),
                                        bubbleBuilder: (m, pairedQId) =>
                                            ChatBubble(
                                          key: ValueKey(m["id"] ??
                                              m["uuid"] ??
                                              m.hashCode),
                                          message: m,
                                          pairedQuestionId: pairedQId,
                                          getAttachmentBytes:
                                              _getAttachmentBytes,
                                          isEditing: m['id'] == _editingId,
                                          editController: _editCtl,
                                          editingAttachments:
                                              _editingAttachments,
                                          onCancelEdit: _cancelEdit,
                                          onConfirmEdit: _confirmEdit,
                                          onPickImagesForEdit: () =>
                                              _pickImages(forEditing: true),
                                          onPickFilesForEdit: () =>
                                              _pickFiles(forEditing: true),
                                          onRemoveAttachment: (index) =>
                                              setState(() => _editingAttachments
                                                  .removeAt(index)),
                                          onFileTap: _handleFileTap,
                                          onImageTap: (bytes, attachment) =>
                                              _showImageViewer(
                                            context,
                                            imageBytes: bytes,
                                            attachment: attachment,
                                          ),
                                          onStartEdit: _startEdit,
                                          onRemoveMessage: _remove,
                                          onRegenerate: _regenerate,
                                          onOpenSources: _openSourcesSideSheet,
                                          onLinkTap: (url) async {
                                            final uri = Uri.tryParse(url);
                                            if (uri == null) return;
                                            final baseUri = Uri.parse(
                                              await ChatAPIService.baseUrl,
                                            );
                                            if (AuthenticatedUri.isTrusted(
                                              uri,
                                              baseUri,
                                            )) {
                                              await _downloadWithAuth(
                                                AuthenticatedUri.resolve(
                                                  uri,
                                                  baseUri,
                                                ),
                                              );
                                              return;
                                            }
                                            await launchUrl(
                                              uri,
                                              mode: LaunchMode
                                                  .externalApplication,
                                            );
                                          },
                                          runState: _runState,
                                          isLastMessage: m == _messages.last,
                                        ),
                                        userActionsBuilder: _userActions,
                                      ),
                                    ),
                                  ),
                                  if (_showScrollToBottom)
                                    Positioned(
                                      bottom: 16 +
                                          ((isPhone && !_isAtBottom)
                                              ? MediaQuery.of(context)
                                                  .viewInsets
                                                  .bottom
                                              : 0),
                                      left: 0,
                                      right: 0,
                                      child: Center(
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            onTap: _animateToBottom,
                                            child: Container(
                                              width: 40,
                                              height: 40,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.08),
                                                border: Border.all(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .outline
                                                      .withValues(alpha: 0.3),
                                                ),
                                              ),
                                              child: const Icon(
                                                  Icons.arrow_downward,
                                                  size: 20),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Transform.translate(
                              offset: Offset(
                                0,
                                (isPhone && !_isAtBottom)
                                    ? -MediaQuery.of(context).viewInsets.bottom
                                    : 0,
                              ),
                              child: ChatInputArea(
                                controller: _controller,
                                focusNode: _inputFocusNode,
                                draftAttachments: _draftAttachments,
                                isBusy: _isBusy,
                                runState: _runState,
                                isWide: wide,
                                useMobileEnterForNewline:
                                    useMobileEnterForNewline,
                                onSend: _handleSend,
                                onPickImages: _pickImages,
                                onPickFiles: _pickFiles,
                                onRemovePendingImage: (index) {
                                  // Call API to delete attachment
                                  final att = _draftAttachments[index];
                                  AuthUtils.withAuthRetry(
                                    context,
                                    (token) =>
                                        _api.deleteAttachment(token, att.id),
                                    notLoggedInMessage:
                                        local.notLoggedInOrInvalidToken,
                                  ).then((_) {
                                    if (mounted) {
                                      setState(() =>
                                          _draftAttachments.removeAt(index));
                                    }
                                  }).catchError((e) {
                                    if (mounted) {
                                      setState(() => _error =
                                          local.attachmentDeleteFailed(
                                              e.toString()));
                                    }
                                  });
                                },
                                onAttachmentTap: (att) =>
                                    _showImageViewer(context, attachment: {
                                  'url': att.url,
                                  'preview_url': att.previewUrl,
                                }),
                                onLoadAttachmentPreview: (att) =>
                                    _getAttachmentBytes(
                                  att.previewUrl ?? att.url,
                                ),
                                onCancelStream: _cancelStream,
                                onFilesDropped: (files) =>
                                    _uploadPickedFiles(files),
                                onError: (msg) => setState(() => _error = msg),
                                onInputTap: _handleInputTap,
                                isEditing: _editingId != null,
                                chatId: _actualChatId,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (showBackButton)
              SafeArea(
                child: Align(
                  alignment: AlignmentDirectional.topStart,
                  child: ChatFloatingCircleButton(
                    scheme: scheme,
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
