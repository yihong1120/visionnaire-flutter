import 'package:flutter/material.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

class ChatWelcomeScreen extends StatelessWidget {
  final ValueChanged<String> onPromptSelected;

  const ChatWelcomeScreen({
    super.key,
    required this.onPromptSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final local = AppLocalizations.of(context)!;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 48,
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              local.newChatRoom,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              local.inputMessage,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                _PromptCard(
                  icon: Icons.lightbulb_outline,
                  text: '幫我分析文件內容',
                  onTap: () => onPromptSelected('幫我分析文件內容'),
                ),
                _PromptCard(
                  icon: Icons.code,
                  text: '解釋這段程式碼',
                  onTap: () => onPromptSelected('解釋這段程式碼'),
                ),
                _PromptCard(
                  icon: Icons.summarize,
                  text: '總結重點資訊',
                  onTap: () => onPromptSelected('總結重點資訊'),
                ),
                _PromptCard(
                  icon: Icons.translate,
                  text: '翻譯文件',
                  onTap: () => onPromptSelected('翻譯文件'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PromptCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const _PromptCard({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: scheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
