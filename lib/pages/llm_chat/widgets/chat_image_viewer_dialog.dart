import 'package:flutter/material.dart';

import '../../../theme/app_motion.dart';
import '../../../widgets/app_transitions.dart';
import 'chat_browser_context_image.dart';

void showChatImageViewerDialog(
  BuildContext context, {
  required Widget image,
}) {
  void close(BuildContext dialogContext) {
    Navigator.of(dialogContext, rootNavigator: true).maybePop();
  }

  ChatBrowserContextImageRegistry.setViewerOpen(true);
  final dialogFuture = showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Image viewer',
    barrierColor: Colors.black.withValues(alpha: 0.8),
    transitionDuration: AppMotion.maybeZero(context, AppMotion.page),
    pageBuilder: (BuildContext dialogContext, _, __) {
      final size = MediaQuery.sizeOf(dialogContext);
      final maxWidth = (size.width - 64).clamp(240.0, 1200.0);
      final maxHeight = (size.height - 64).clamp(240.0, 1200.0);

      return Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => close(dialogContext),
                child: const SizedBox.expand(),
              ),
            ),
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.deferToChild,
                onTap: () {},
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: maxWidth,
                    maxHeight: maxHeight,
                  ),
                  child: image,
                ),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              child: SafeArea(
                left: false,
                top: true,
                right: true,
                bottom: false,
                minimum: const EdgeInsets.only(top: 20, right: 20),
                child: Material(
                  color: Colors.black.withValues(alpha: 0.32),
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 30),
                    tooltip: 'Close',
                    onPressed: () => close(dialogContext),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return appTransitionBuilder(
        context: context,
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        transition: AppRouteTransition.fadeScale,
        child: child,
      );
    },
  );
  dialogFuture.whenComplete(
    () => ChatBrowserContextImageRegistry.setViewerOpen(false),
  );
}
