import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/locale_provider.dart';
import '../providers/unified_auth_provider.dart';
import '../services/api_config_service.dart';
import '../services/deployment_profile_service.dart';
import '../widgets/app_transitions.dart';
import '../widgets/responsive_scaffold.dart';
import 'api_config_page.dart';
import 'deployment_enrollment_page.dart';
import 'managements/account_security_page.dart';
import 'notification_site_settings_page.dart';

enum _SettingsPane {
  overview,
  language,
  account,
  notifications,
  api,
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _SettingsPane _pane = _SettingsPane.overview;
  bool _reactivatingDevice = false;

  void _openPane(_SettingsPane pane) {
    setState(() => _pane = pane);
  }

  void _openOverview() {
    setState(() => _pane = _SettingsPane.overview);
  }

  Future<void> _beginDeviceReactivation() async {
    if (kIsWeb || _reactivatingDevice) return;

    setState(() => _reactivatingDevice = true);
    try {
      await context
          .read<UnifiedAuthProvider>()
          .clearLocalSessionForDeploymentChange();
      await ApiConfigService.clearRuntimeEndpointOverridesForDeploymentChange();
      await DeploymentProfileService.shared.resetNativeEnrollment();
      if (!mounted) return;

      final bool? activated = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (BuildContext activationContext) => PopScope(
            canPop: false,
            child: DeploymentEnrollmentPage(
              onCompleted: () async {
                Navigator.of(activationContext).pop(true);
              },
            ),
          ),
        ),
      );
      if (activated == true && mounted) {
        context.go('/login');
      }
    } finally {
      if (mounted) setState(() => _reactivatingDevice = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool inDetail = _pane != _SettingsPane.overview;
    final bool canReactivate =
        !kIsWeb && context.watch<UnifiedAuthProvider>().isLoggedIn;

    return ResponsiveScaffold(
      title: _titleForPane(context, _pane),
      isFullscreen: inDetail,
      onBackPressed: inDetail ? _openOverview : null,
      body: AppFadeScaleSwitcher(
        child: _SettingsLayout(
          key: ValueKey<_SettingsPane>(_pane),
          pane: _pane,
          onSelectPane: _openPane,
          onReactivationRequested:
              canReactivate ? _beginDeviceReactivation : null,
        ),
      ),
    );
  }
}

class _SettingsLayout extends StatelessWidget {
  const _SettingsLayout({
    super.key,
    required this.pane,
    required this.onSelectPane,
    required this.onReactivationRequested,
  });

  final _SettingsPane pane;
  final ValueChanged<_SettingsPane> onSelectPane;
  final DeploymentReactivationIntentHandler? onReactivationRequested;

  @override
  Widget build(BuildContext context) {
    if (pane == _SettingsPane.overview) {
      return _SettingsOverview(onSelectPane: onSelectPane);
    }

    return _SettingsPaneBody(
      pane: pane,
      onReactivationRequested: onReactivationRequested,
    );
  }
}

class _SettingsLayoutSpec {
  const _SettingsLayoutSpec({
    required this.overviewPadding,
    required this.detailPadding,
    required this.overviewMaxWidth,
  });

  factory _SettingsLayoutSpec.fromWidth(double width) {
    if (width < 600) {
      return const _SettingsLayoutSpec(
        overviewPadding: EdgeInsets.fromLTRB(16, 10, 16, 28),
        detailPadding: EdgeInsets.fromLTRB(16, 12, 16, 28),
        overviewMaxWidth: 560,
      );
    }

    if (width < 1024) {
      return const _SettingsLayoutSpec(
        overviewPadding: EdgeInsets.fromLTRB(24, 18, 24, 36),
        detailPadding: EdgeInsets.fromLTRB(24, 22, 24, 36),
        overviewMaxWidth: 760,
      );
    }

    return const _SettingsLayoutSpec(
      overviewPadding: EdgeInsets.fromLTRB(32, 28, 32, 44),
      detailPadding: EdgeInsets.fromLTRB(32, 28, 32, 44),
      overviewMaxWidth: 1040,
    );
  }

  final EdgeInsets overviewPadding;
  final EdgeInsets detailPadding;
  final double overviewMaxWidth;

  double detailMaxWidthFor(_SettingsPane pane) {
    return switch (pane) {
      _SettingsPane.api => 1180,
      _SettingsPane.notifications => 980,
      _SettingsPane.account => 860,
      _SettingsPane.language => 680,
      _SettingsPane.overview => overviewMaxWidth,
    };
  }
}

class _SettingsOverview extends StatelessWidget {
  const _SettingsOverview({
    required this.onSelectPane,
  });

  final ValueChanged<_SettingsPane> onSelectPane;

  @override
  Widget build(BuildContext context) {
    final UnifiedAuthProvider auth = context.watch<UnifiedAuthProvider>();
    final String language = _currentLanguageLabel(context);
    final bool loggedIn = auth.isLoggedIn;

    final List<Widget> groups = <Widget>[
      _SettingsGroup(
        title: _copy(
          context,
          zh: '一般',
          en: 'General',
          fr: 'Général',
          ja: '一般',
        ),
        children: <Widget>[
          _SettingsRow(
            icon: Icons.language,
            title: AppLocalizations.of(context)!.changeLanguage,
            value: language,
            onTap: () => onSelectPane(_SettingsPane.language),
          ),
        ],
      ),
      _SettingsGroup(
        title: _copy(
          context,
          zh: '帳號',
          en: 'Account',
          fr: 'Compte',
          ja: 'アカウント',
        ),
        children: <Widget>[
          _SettingsRow(
            icon: Icons.shield_outlined,
            title: _copy(
              context,
              zh: '帳號設定',
              en: 'Account settings',
              fr: 'Paramètres du compte',
              ja: 'アカウント設定',
            ),
            value: loggedIn
                ? _copy(
                    context,
                    zh: '密碼、生物辨識、Google / Apple',
                    en: 'Password, biometrics, Google / Apple',
                    fr: 'Mot de passe, biométrie, Google / Apple',
                    ja: 'パスワード、生体認証、Google / Apple',
                  )
                : AppLocalizations.of(context)!.pleaseLogin,
            onTap: loggedIn
                ? () => onSelectPane(_SettingsPane.account)
                : () => context.go('/login'),
          ),
        ],
      ),
      _SettingsGroup(
        title: _copy(
          context,
          zh: '通知',
          en: 'Notifications',
          fr: 'Notifications',
          ja: '通知',
        ),
        children: <Widget>[
          _SettingsRow(
            icon: Icons.notifications_active_outlined,
            title: AppLocalizations.of(context)!.notificationSettings,
            value: loggedIn
                ? _copy(
                    context,
                    zh: '工地與文件通知',
                    en: 'Site and document alerts',
                    fr: 'Alertes de chantier et document',
                    ja: '現場と文書の通知',
                  )
                : AppLocalizations.of(context)!.pleaseLogin,
            onTap: loggedIn
                ? () => onSelectPane(_SettingsPane.notifications)
                : () => context.go('/login'),
          ),
        ],
      ),
      _SettingsGroup(
        title: _copy(
          context,
          zh: '連線',
          en: 'Connection',
          fr: 'Connexion',
          ja: '接続',
        ),
        children: <Widget>[
          _SettingsRow(
            icon: Icons.api_outlined,
            title: AppLocalizations.of(context)!.apiConfiguration,
            value: _copy(
              context,
              zh: '服務端點',
              en: 'Service endpoints',
              fr: 'Points de terminaison',
              ja: 'サービスエンドポイント',
            ),
            onTap: () => onSelectPane(_SettingsPane.api),
          ),
        ],
      ),
    ];

    return _ResponsiveSettingsGroups(groups: groups);
  }
}

class _ResponsiveSettingsGroups extends StatelessWidget {
  const _ResponsiveSettingsGroups({
    required this.groups,
  });

  final List<Widget> groups;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final _SettingsLayoutSpec spec =
            _SettingsLayoutSpec.fromWidth(constraints.maxWidth);
        final double availableWidth =
            (constraints.maxWidth - spec.overviewPadding.horizontal)
                .clamp(0.0, spec.overviewMaxWidth)
                .toDouble();
        final bool useTwoColumns = availableWidth >= 820;
        final double groupWidth =
            useTwoColumns ? (availableWidth - 18) / 2 : availableWidth;

        final Widget content = useTwoColumns
            ? Wrap(
                spacing: 18,
                runSpacing: 20,
                children: groups
                    .map(
                      (Widget group) => SizedBox(
                        width: groupWidth,
                        child: group,
                      ),
                    )
                    .toList(),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < groups.length; i++) ...<Widget>[
                    groups[i],
                    if (i != groups.length - 1) const SizedBox(height: 22),
                  ],
                ],
              );

        return ListView(
          padding: spec.overviewPadding,
          children: <Widget>[
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: availableWidth),
                child: content,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SettingsPaneBody extends StatelessWidget {
  const _SettingsPaneBody({
    required this.pane,
    required this.onReactivationRequested,
  });

  final _SettingsPane pane;
  final DeploymentReactivationIntentHandler? onReactivationRequested;

  @override
  Widget build(BuildContext context) {
    final Widget child = switch (pane) {
      _SettingsPane.language => const _LanguageSettingsPane(),
      _SettingsPane.account => const AccountSecurityPage(embedded: true),
      _SettingsPane.notifications => const NotificationSiteSettingsPage(
          embedded: true,
        ),
      _SettingsPane.api => ApiConfigPage(
          embedded: true,
          onReactivationRequested: kIsWeb ? null : onReactivationRequested,
        ),
      _SettingsPane.overview => const SizedBox.shrink(),
    };

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final _SettingsLayoutSpec spec =
            _SettingsLayoutSpec.fromWidth(constraints.maxWidth);

        return ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: spec.detailMaxWidthFor(pane),
              ),
              child: ListView(
                padding: spec.detailPadding,
                children: <Widget>[child],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LanguageSettingsPane extends StatelessWidget {
  const _LanguageSettingsPane();

  @override
  Widget build(BuildContext context) {
    final Locale currentLocale = Localizations.localeOf(context);
    final String currentKey =
        '${currentLocale.languageCode}_${currentLocale.countryCode ?? ''}';

    return _FlatList(
      children: _languages.entries.map((MapEntry<String, String> entry) {
        final bool selected = entry.key == currentKey ||
            (currentLocale.countryCode == null &&
                entry.key.startsWith('${currentLocale.languageCode}_'));
        return _LanguageOptionTile(
          label: entry.value,
          selected: selected,
          onTap: () => _setLanguage(context, entry.key),
        );
      }).toList(),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _FlatList(children: children),
      ],
    );
  }
}

class _FlatList extends StatelessWidget {
  const _FlatList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Column(
          children: <Widget>[
            for (int i = 0; i < children.length; i++) ...<Widget>[
              children[i],
              if (i != children.length - 1)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: 56,
                  color: theme.colorScheme.outlineVariant,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              Icon(icon, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageOptionTile extends StatelessWidget {
  const _LanguageOptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Material(
      color: selected
          ? colorScheme.primaryContainer.withValues(alpha: 0.42)
          : Colors.transparent,
      child: InkWell(
        onTap: selected ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.translate_outlined,
                color: selected
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (selected)
                Icon(
                  Icons.check_circle,
                  color: colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _titleForPane(BuildContext context, _SettingsPane pane) {
  return switch (pane) {
    _SettingsPane.overview => _copy(
        context,
        zh: '設定',
        en: 'Settings',
        fr: 'Paramètres',
        ja: '設定',
      ),
    _SettingsPane.language => AppLocalizations.of(context)!.changeLanguage,
    _SettingsPane.account => _copy(
        context,
        zh: '帳號設定',
        en: 'Account settings',
        fr: 'Paramètres du compte',
        ja: 'アカウント設定',
      ),
    _SettingsPane.notifications =>
      AppLocalizations.of(context)!.notificationSettings,
    _SettingsPane.api => AppLocalizations.of(context)!.apiConfiguration,
  };
}

String _currentLanguageLabel(BuildContext context) {
  final Locale locale = Localizations.localeOf(context);
  final String key = '${locale.languageCode}_${locale.countryCode ?? ''}';
  return _languages[key] ?? _languages[locale.languageCode] ?? 'English';
}

Future<void> _setLanguage(BuildContext context, String languageKey) async {
  final List<String> parts = languageKey.split('_');
  final Locale newLocale = Locale(parts[0], parts.length > 1 ? parts[1] : null);
  context.read<LocaleProvider>().setLocale(newLocale);
}

const Map<String, String> _languages = <String, String>{
  'zh_TW': '繁體中文',
  'en_GB': 'English',
  'fr_FR': 'Français',
  'id_ID': 'Bahasa Indonesia',
  'ja_JP': '日本語',
  'th_TH': 'ภาษาไทย',
  'vi_VN': 'Tiếng Việt',
};

String _copy(
  BuildContext context, {
  required String zh,
  required String en,
  String? fr,
  String? ja,
}) {
  switch (Localizations.localeOf(context).languageCode) {
    case 'zh':
      return zh;
    case 'fr':
      return fr ?? en;
    case 'ja':
      return ja ?? en;
    default:
      return en;
  }
}
