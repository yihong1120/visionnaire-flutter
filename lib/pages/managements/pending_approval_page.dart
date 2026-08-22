import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:visionnaire/l10n/app_localizations.dart';

import '../../providers/unified_auth_provider.dart';
import '../../widgets/web_selectable_content.dart';

class PendingApprovalPage extends StatelessWidget {
  const PendingApprovalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final local = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(local.pendingApprovalTitle)),
      body: WebSelectableContent(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.hourglass_top_rounded,
                  size: 80,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                const SizedBox(height: 24),
                Text(
                  local.pendingApprovalTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  local.pendingApprovalMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                WebNonSelectableContent(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        context.read<UnifiedAuthProvider>().logout(),
                    icon: const Icon(Icons.logout),
                    label: Text(local.logout),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
