part of 'chat_page.dart';

mixin _ChatPageSheets on _ChatPageStateBase {
  Future<void> _showRightSideSheet({
    required String barrierLabel,
    required Widget child,
  }) async {
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: barrierLabel,
      barrierColor: Colors.black54,
      transitionDuration: AppMotion.maybeZero(context, AppMotion.sheet),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        final width = MediaQuery.sizeOf(ctx).width * 0.8;
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: width.clamp(280.0, 360.0),
              height: double.infinity,
              child: SafeArea(child: child),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        return appTransitionBuilder(
          context: ctx,
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          transition: AppRouteTransition.rightSheet,
          child: child,
        );
      },
    );
  }

  @override
  Future<void> _openSourcesSideSheet(List<Map<String, dynamic>> sources) async {
    if (sources.isEmpty) return;
    await _showRightSideSheet(
      barrierLabel: 'Sources',
      child: ChatCitationsPanel(
        sources: sources,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }

  @override
  void _showImageViewer(
    BuildContext context, {
    Uint8List? imageBytes,
    Map<String, dynamic>? attachment,
  }) {
    if (imageBytes == null && attachment == null) return;

    final size = MediaQuery.of(context).size;
    final image = imageBytes != null
        ? Image.memory(imageBytes)
        : ChatAttachmentImage(
            attachment: attachment!,
            getBytes: _getAttachmentBytes,
            width: size.width * 0.9,
            maxHeight: size.height * 0.9,
            hideWhenViewerOpen: false,
          );

    showChatImageViewerDialog(context, image: image);
  }

  @override
  Widget _userActions(Map<String, dynamic> m) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    final id = m['id'] as int?;
    if (m['role'] != 'user' || id == null || _editingId == id) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerRight,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (_editingId == null)
          IconButton(
            icon: Icon(Icons.edit, color: colors.tertiary),
            tooltip: AppLocalizations.of(context)!.editQuestion,
            onPressed: () => _startEdit(
              id,
              m['content'] as String? ?? '',
              m['attachments'] as List<dynamic>?,
            ),
          ),
        IconButton(
          icon: Icon(Icons.delete, color: colors.error),
          tooltip: AppLocalizations.of(context)!.removeQuestionChain,
          onPressed: () => _remove(id),
        ),
      ]),
    );
  }
}
