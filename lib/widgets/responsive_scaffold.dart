import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:visionnaire/l10n/app_localizations.dart';
import '../providers/unified_auth_provider.dart';
import '../services/notification_api_service.dart';
import '../utils/auth_utils.dart';
import 'app_drawer.dart';
import 'web_selectable_content.dart';

/// A responsive scaffold that adapts its layout for wide and narrow screens.
///
/// - On web, displays a website-style top navigation and footer.
/// - On native wide screens, displays a fixed drawer on the left and content on the right.
/// - On native narrow screens, uses a standard drawer with animation.
class ResponsiveScaffold extends StatelessWidget {
  /// The title to display in the app bar.
  final String title;

  /// The main content widget to display in the scaffold body.
  final Widget body;

  /// An optional floating action button to display.
  final Widget? floatingActionButton;

  /// A list of Widgets to display in a row after the [title] widget.
  final List<Widget>? actions;

  /// Whether the title should be centered. If null, will auto-adjust based on platform.
  /// iOS: centered, Android/Web: left-aligned
  final bool? centerTitle;

  /// The background color of the app bar.
  final Color? appBarBackgroundColor;

  /// The foreground color of the app bar.
  final Color? appBarForegroundColor;

  /// The elevation of the app bar.
  final double? appBarElevation;

  /// Whether to use fullscreen mode (hide drawer, keep only back button).
  final bool isFullscreen;

  /// Optional callback for the fullscreen back button.
  final VoidCallback? onBackPressed;

  /// Creates a [ResponsiveScaffold].
  ///
  /// [title] and [body] are required. [floatingActionButton] is optional.
  /// [centerTitle] defaults to null, which will auto-adjust based on platform:
  /// iOS: centered, Android/Web: left-aligned
  /// [isFullscreen] defaults to false. When true, hides the drawer and shows only back button.
  const ResponsiveScaffold({
    super.key,
    required this.title,
    required this.body,
    this.floatingActionButton,
    this.actions,
    this.centerTitle,
    this.appBarBackgroundColor,
    this.appBarForegroundColor,
    this.appBarElevation,
    this.isFullscreen = false,
    this.onBackPressed,
  });

  static const double _desktopContentMaxWidth = 1480;

  /// Determines whether the title should be centered based on platform.
  /// iOS: true (centered), Android/Web: false (left-aligned)
  bool get _shouldCenterTitle {
    if (centerTitle != null) return centerTitle!;

    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  Widget build(BuildContext context) {
    // If fullscreen mode is enabled, use a simple scaffold with only back button
    if (isFullscreen) {
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final scaffold = kIsWeb
              ? _WebFullscreenScaffold(
                  title: title,
                  body: body,
                  actions: actions,
                  floatingActionButton: floatingActionButton,
                  onBackPressed: _handleBack,
                )
              : _mobileFullscreenScaffold(context);
          final bool hasRouteBack = _hasRouteBack(context);
          final gestureScaffold = _wrapEdgeBackGesture(
            context: context,
            hasRouteBack: hasRouteBack,
            child: scaffold,
          );

          if (onBackPressed == null || hasRouteBack) {
            return gestureScaffold;
          }

          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              onBackPressed!();
            },
            child: gestureScaffold,
          );
        },
      );
    }

    // Use LayoutBuilder to determine the available width and adapt the layout.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (kIsWeb) {
          return _WebDesktopScaffold(
            title: title,
            body: body,
            actions: actions,
            floatingActionButton: floatingActionButton,
            maxContentWidth: _desktopContentMaxWidth,
          );
        }

        if (!kIsWeb && constraints.maxWidth >= 800) {
          // Wide native tablet: fixed drawer on the left, no animation.
          return Scaffold(
            body: Row(
              children: <Widget>[
                // Left-side fixed drawer
                Container(
                  width: 250,
                  color: Theme.of(context).canvasColor,
                  child: const AppDrawer(),
                ),
                // Right-side content area (fixed AppBar & content)
                Expanded(
                  child: Column(
                    children: <Widget>[
                      AppBar(
                        title: Text(title),
                        centerTitle: _shouldCenterTitle,
                        backgroundColor: appBarBackgroundColor,
                        foregroundColor: appBarForegroundColor,
                        elevation: appBarElevation,
                        automaticallyImplyLeading:
                            false, // Remove hamburger icon
                        actions: actions,
                      ),
                      Expanded(child: body),
                    ],
                  ),
                ),
              ],
            ),
            floatingActionButton: floatingActionButton,
          );
        } else {
          // 📱 Narrow screen (Mobile): standard drawer with animation.
          return Scaffold(
            appBar: AppBar(
              title: Text(title),
              centerTitle: _shouldCenterTitle,
              backgroundColor: appBarBackgroundColor,
              foregroundColor: appBarForegroundColor,
              elevation: appBarElevation,
              actions: actions,
            ),
            drawer: const AppDrawer(),
            body: body,
            floatingActionButton: floatingActionButton,
          );
        }
      },
    );
  }

  Scaffold _mobileFullscreenScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: _shouldCenterTitle,
        backgroundColor: appBarBackgroundColor,
        foregroundColor: appBarForegroundColor,
        elevation: appBarElevation,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _handleBack(context),
        ),
        actions: actions,
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }

  void _handleBack(BuildContext context) {
    if (onBackPressed != null) {
      onBackPressed!();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else if (_hasRouteBack(context)) {
      context.pop();
    }
  }

  Widget _wrapEdgeBackGesture({
    required BuildContext context,
    required bool hasRouteBack,
    required Widget child,
  }) {
    if (!_shouldEnableEdgeBackGesture || hasRouteBack) return child;
    return _FullscreenEdgeBackGesture(
      onBack: onBackPressed!,
      child: child,
    );
  }

  bool _hasRouteBack(BuildContext context) {
    if (Navigator.of(context).canPop()) return true;
    try {
      return context.canPop();
    } on AssertionError {
      // This scaffold is also used in isolated widget trees without GoRouter.
      return false;
    }
  }

  bool get _shouldEnableEdgeBackGesture {
    if (kIsWeb || onBackPressed == null) return false;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }
}

class _WebDesktopScaffold extends StatelessWidget {
  const _WebDesktopScaffold({
    required this.title,
    required this.body,
    required this.maxContentWidth,
    this.actions,
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final double maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool compactWeb = MediaQuery.sizeOf(context).width < 760;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      floatingActionButton: floatingActionButton,
      body: Column(
        children: <Widget>[
          const _WebTopNavigationBar(),
          Expanded(
            child: WebSelectableContent(
              child: DecoratedBox(
                decoration: BoxDecoration(color: colorScheme.surface),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final double contentWidth = compactWeb
                        ? constraints.maxWidth
                        : math.min(constraints.maxWidth, maxContentWidth);
                    return Center(
                      child: SizedBox(
                        width: contentWidth,
                        height: constraints.maxHeight,
                        child: Column(
                          children: <Widget>[
                            _WebPageHeader(title: title, actions: actions),
                            Expanded(child: body),
                            const _WebFooter(),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Desktop web shell for operational workspaces.
///
/// Use this for pages such as streaming and chat that need their own local
/// sidebar. The global app navigation stays in a horizontal top bar, while the
/// page body can manage its own split-pane layout.
class WebWorkspaceScaffold extends StatelessWidget {
  const WebWorkspaceScaffold({
    super.key,
    required this.body,
    this.floatingActionButton,
    this.showFooter = true,
  });

  final Widget body;
  final Widget? floatingActionButton;
  final bool showFooter;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      floatingActionButton: floatingActionButton,
      body: Column(
        children: <Widget>[
          const _WebTopNavigationBar(),
          Expanded(
            child: WebSelectableContent(
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLowest,
                      ),
                      child: body,
                    ),
                  ),
                  if (showFooter) const _WebFooter(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WebFullscreenScaffold extends StatelessWidget {
  const _WebFullscreenScaffold({
    required this.title,
    required this.body,
    required this.onBackPressed,
    this.actions,
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final void Function(BuildContext context) onBackPressed;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      floatingActionButton: floatingActionButton,
      body: WebSelectableContent(
        child: Column(
          children: <Widget>[
            Container(
              height: 72,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                ),
              ),
              child: Row(
                children: <Widget>[
                  WebNonSelectableContent(
                    child: IconButton(
                      tooltip:
                          MaterialLocalizations.of(context).backButtonTooltip,
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => onBackPressed(context),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (actions != null) ...<Widget>[
                    const SizedBox(width: 16),
                    WebNonSelectableContent(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: actions!,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

class _WebPageHeader extends StatelessWidget {
  const _WebPageHeader({
    required this.title,
    this.actions,
  });

  final String title;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool stacked = constraints.maxWidth < 680;
        final Widget titleWidget = Text(
          title,
          maxLines: stacked ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        );
        final Widget? actionWrap = actions == null || actions!.isEmpty
            ? null
            : WebNonSelectableContent(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions!,
                ),
              );

        return Padding(
          padding: EdgeInsets.fromLTRB(
            stacked ? 16 : 24,
            stacked ? 16 : 22,
            stacked ? 16 : 24,
            stacked ? 12 : 14,
          ),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    titleWidget,
                    if (actionWrap != null) ...<Widget>[
                      const SizedBox(height: 12),
                      actionWrap,
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    Expanded(child: titleWidget),
                    if (actionWrap != null) ...<Widget>[
                      const SizedBox(width: 16),
                      actionWrap,
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _WebFooter extends StatelessWidget {
  const _WebFooter();

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final TextStyle? style = theme.textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Wrap(
              spacing: 18,
              runSpacing: 6,
              children: <Widget>[
                Text('Visionnaire Safety Operations', style: style),
                Text('© 2026 Visionnaire', style: style),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WebTopNavigationBar extends StatelessWidget {
  const _WebTopNavigationBar();

  static const double _compactBreakpoint = 1040;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AppLocalizations local = AppLocalizations.of(context)!;
    final UnifiedAuthProvider auth = context.watch<UnifiedAuthProvider>();
    final List<_WebNavItemData> primaryItems =
        _primaryNavigationItems(local, auth);
    final List<_WebNavItemData> managementItems =
        _managementNavigationItems(context, local, auth);
    final String currentPath = GoRouterState.of(context).uri.path;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < _compactBreakpoint;
        final bool veryCompact = constraints.maxWidth < 620;
        final double horizontalPadding = compact ? 14 : 28;

        return Container(
          height: compact ? 64 : 76,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.55),
              ),
            ),
          ),
          child: Row(
            children: <Widget>[
              _WebBrandMark(showText: !veryCompact),
              SizedBox(width: compact ? 12 : 28),
              Expanded(
                child: compact
                    ? _WebNavigationMenu(
                        primaryItems: primaryItems,
                        managementItems: managementItems,
                        currentPath: currentPath,
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: <Widget>[
                            for (final _WebNavItemData item in primaryItems)
                              _WebNavButton(
                                item: item,
                                selected:
                                    _routeMatches(currentPath, item.routePath),
                              ),
                            if (managementItems.isNotEmpty)
                              _WebManagementMenu(
                                items: managementItems,
                                selected: managementItems.any(
                                  (_WebNavItemData item) => _routeMatches(
                                    currentPath,
                                    item.routePath,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              if (auth.isLoggedIn) const _WebNotificationButton(),
              IconButton(
                tooltip: _settingsLabel(context),
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.go('/settings'),
              ),
              const SizedBox(width: 4),
              compact
                  ? const _WebCompactAccountMenu()
                  : const _WebAccountMenu(),
            ],
          ),
        );
      },
    );
  }
}

class _WebNavigationMenu extends StatelessWidget {
  const _WebNavigationMenu({
    required this.primaryItems,
    required this.managementItems,
    required this.currentPath,
  });

  final List<_WebNavItemData> primaryItems;
  final List<_WebNavItemData> managementItems;
  final String currentPath;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final List<_WebNavItemData> allItems = <_WebNavItemData>[
      ...primaryItems,
      ...managementItems,
    ];
    if (allItems.isEmpty) return const SizedBox.shrink();

    final String selectedLabel =
        _selectedNavigationLabel(allItems, currentPath) ??
            _navigationLabel(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<String>(
        tooltip: _navigationLabel(context),
        onSelected: (String routePath) => context.go(routePath),
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
          for (final _WebNavItemData item in primaryItems)
            _WebNavigationMenuItem(
              item: item,
              selected: _routeMatches(currentPath, item.routePath),
            ),
          if (primaryItems.isNotEmpty && managementItems.isNotEmpty)
            const PopupMenuDivider(),
          for (final _WebNavItemData item in managementItems)
            _WebNavigationMenuItem(
              item: item,
              selected: _routeMatches(currentPath, item.routePath),
            ),
        ],
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.75),
            ),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.menu_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  selectedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebNavigationMenuItem extends PopupMenuItem<String> {
  _WebNavigationMenuItem({
    required _WebNavItemData item,
    required bool selected,
  }) : super(
          value: item.routePath,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(item.icon),
            title: Text(
              item.label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
            trailing: selected ? const Icon(Icons.check, size: 18) : null,
          ),
        );
}

class _WebCompactAccountMenu extends StatelessWidget {
  const _WebCompactAccountMenu();

  @override
  Widget build(BuildContext context) {
    final UnifiedAuthProvider auth = context.watch<UnifiedAuthProvider>();
    final AppLocalizations local = AppLocalizations.of(context)!;
    if (!auth.isLoggedIn) {
      return IconButton(
        tooltip: local.login,
        onPressed: () => context.go('/login'),
        icon: const Icon(Icons.login),
      );
    }

    final String displayName = auth.displayName ?? auth.username ?? 'User';
    return PopupMenuButton<String>(
      tooltip: displayName,
      onSelected: (String value) {
        switch (value) {
          case 'settings':
            context.go('/settings');
          case 'logout':
            unawaited(context.read<UnifiedAuthProvider>().logout());
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                displayName,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                local.roleLabel(auth.role?.toUpperCase() ?? 'USER'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'settings',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_outlined),
            title: Text(_settingsLabel(context)),
          ),
        ),
        PopupMenuItem<String>(
          value: 'logout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout),
            title: Text(local.logout),
          ),
        ),
      ],
      child: CircleAvatar(
        radius: 17,
        child: Text(
          displayName.trim().isEmpty
              ? 'U'
              : displayName.characters.first.toUpperCase(),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _WebBrandMark extends StatelessWidget {
  const _WebBrandMark({this.showText = true});

  final bool showText;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => context.go('/violations'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.remove_red_eye,
                color: colorScheme.onPrimary,
              ),
            ),
            if (showText) ...<Widget>[
              const SizedBox(width: 10),
              Text(
                'Visionnaire',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WebNavButton extends StatelessWidget {
  const _WebNavButton({
    required this.item,
    required this.selected,
  });

  final _WebNavItemData item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => context.go(item.routePath),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}

class _WebManagementMenu extends StatelessWidget {
  const _WebManagementMenu({
    required this.items,
    required this.selected,
  });

  final List<_WebNavItemData> items;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String currentPath = GoRouterState.of(context).uri.path;

    return MenuAnchor(
      alignmentOffset: const Offset(0, 8),
      style: MenuStyle(
        alignment: AlignmentDirectional.bottomStart,
        backgroundColor: WidgetStatePropertyAll<Color>(colorScheme.surface),
        elevation: const WidgetStatePropertyAll<double>(6),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(vertical: 8),
        ),
        minimumSize: const WidgetStatePropertyAll<Size>(Size(236, 0)),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        side: WidgetStatePropertyAll<BorderSide>(
          BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.65),
          ),
        ),
      ),
      menuChildren: <Widget>[
        for (final _WebNavItemData item in items)
          MenuItemButton(
            onPressed: () => context.go(item.routePath),
            leadingIcon: Icon(item.icon),
            trailingIcon: _routeMatches(currentPath, item.routePath)
                ? Icon(
                    Icons.check_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  )
                : null,
            style: ButtonStyle(
              padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
              minimumSize: const WidgetStatePropertyAll<Size>(Size(236, 48)),
              textStyle: WidgetStatePropertyAll<TextStyle?>(
                theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            child: Text(item.label),
          ),
      ],
      builder: (
        BuildContext context,
        MenuController controller,
        Widget? child,
      ) {
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(left: 2),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? colorScheme.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: <Widget>[
                Text(
                  _managementLabel(context),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: selected
                        ? colorScheme.onPrimary
                        : colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  controller.isOpen
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                  color: selected
                      ? colorScheme.onPrimary
                      : colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WebNotificationButton extends StatefulWidget {
  const _WebNotificationButton();

  @override
  State<_WebNotificationButton> createState() => _WebNotificationButtonState();
}

class _WebNotificationButtonState extends State<_WebNotificationButton> {
  bool _requested = false;
  int? _unreadCount;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool isLoggedIn = context.read<UnifiedAuthProvider>().isLoggedIn;
    if (!isLoggedIn) {
      _requested = false;
      _unreadCount = null;
      return;
    }
    if (!_requested) {
      _requested = true;
      unawaited(_loadUnreadCount());
    }
  }

  Future<void> _loadUnreadCount() async {
    try {
      final int count = await AuthUtils.withAuthRetry(
        context,
        (String token) => NotificationAPIService().getUnreadNotificationCount(
          token: token,
        ),
      );
      if (!mounted) return;
      setState(() => _unreadCount = count);
    } catch (_) {
      if (!mounted) return;
      setState(() => _unreadCount = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int count = _unreadCount ?? 0;
    return IconButton(
      tooltip: _notificationCenterLabel(context),
      onPressed: () => context.go('/notifications'),
      icon: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          const Icon(Icons.notifications_none_outlined),
          if (count > 0)
            Positioned(
              right: -8,
              top: -8,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  count > 99 ? '99+' : count.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onErrorContainer,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WebAccountMenu extends StatelessWidget {
  const _WebAccountMenu();

  @override
  Widget build(BuildContext context) {
    final UnifiedAuthProvider auth = context.watch<UnifiedAuthProvider>();
    final AppLocalizations local = AppLocalizations.of(context)!;
    if (!auth.isLoggedIn) {
      return FilledButton.icon(
        onPressed: () => context.go('/login'),
        icon: const Icon(Icons.login, size: 18),
        label: Text(local.login),
      );
    }

    final String displayName = auth.displayName ?? auth.username ?? 'User';
    return PopupMenuButton<String>(
      tooltip: displayName,
      onSelected: (String value) {
        switch (value) {
          case 'settings':
            context.go('/settings');
          case 'logout':
            unawaited(_logout(context));
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                displayName,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                local.roleLabel(auth.role?.toUpperCase() ?? 'USER'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'settings',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_outlined),
            title: Text(_settingsLabel(context)),
          ),
        ),
        PopupMenuItem<String>(
          value: 'logout',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.logout),
            title: Text(local.logout),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .outlineVariant
                .withValues(alpha: 0.7),
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: <Widget>[
            CircleAvatar(
              radius: 14,
              child: Text(
                displayName.trim().isEmpty
                    ? 'U'
                    : displayName.characters.first.toUpperCase(),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await context.read<UnifiedAuthProvider>().logout();
    } catch (error) {
      debugPrint('Logout error: $error');
    }
  }
}

class _WebNavItemData {
  const _WebNavItemData({
    required this.icon,
    required this.label,
    required this.routePath,
  });

  final IconData icon;
  final String label;
  final String routePath;
}

List<_WebNavItemData> _primaryNavigationItems(
  AppLocalizations local,
  UnifiedAuthProvider auth,
) {
  if (!auth.isLoggedIn) return const <_WebNavItemData>[];

  final List<_WebNavItemData> items = <_WebNavItemData>[];
  if (auth.hasFeature('doc_chat')) {
    items.add(_WebNavItemData(
      icon: Icons.chat_bubble_outline,
      label: local.chatList,
      routePath: '/chat',
    ));
  }
  if (auth.hasFeature('yolo_api')) {
    items.addAll(<_WebNavItemData>[
      _WebNavItemData(
        icon: Icons.videocam_outlined,
        label: local.streamingWebSettings,
        routePath: '/stream',
      ),
      _WebNavItemData(
        icon: Icons.photo_camera_outlined,
        label: local.detection,
        routePath: '/detection',
      ),
      _WebNavItemData(
        icon: Icons.warning_amber_outlined,
        label: local.violationRecordQuery,
        routePath: '/violations',
      ),
    ]);
  }
  if (auth.hasFeature('file_manage')) {
    items.add(_WebNavItemData(
      icon: Icons.description_outlined,
      label: local.fileManagement,
      routePath: '/files',
    ));
  }
  return items;
}

List<_WebNavItemData> _managementNavigationItems(
  BuildContext context,
  AppLocalizations local,
  UnifiedAuthProvider auth,
) {
  if (!auth.isLoggedIn) return const <_WebNavItemData>[];

  final bool isSuper = auth.isSuperAdmin;
  if (!isSuper && auth.role != 'admin') {
    return const <_WebNavItemData>[];
  }

  final List<_WebNavItemData> items = <_WebNavItemData>[
    _WebNavItemData(
      icon: Icons.home_work_outlined,
      label: local.siteManagement,
      routePath: '/sites',
    ),
    _WebNavItemData(
      icon: Icons.manage_accounts_outlined,
      label: local.userManagement,
      routePath: '/users',
    ),
    _WebNavItemData(
      icon: Icons.devices_outlined,
      label: _deviceInvitationsLabel(context),
      routePath: '/device-invitations',
    ),
  ];
  if (isSuper) {
    items.addAll(<_WebNavItemData>[
      _WebNavItemData(
        icon: Icons.group_work_outlined,
        label: local.groupManagement,
        routePath: '/groups',
      ),
      _WebNavItemData(
        icon: Icons.extension_outlined,
        label: local.featureManagement,
        routePath: '/features',
      ),
    ]);
  }
  return items;
}

bool _routeMatches(String currentPath, String routePath) {
  return currentPath == routePath || currentPath.startsWith('$routePath/');
}

String? _selectedNavigationLabel(
  List<_WebNavItemData> items,
  String currentPath,
) {
  for (final _WebNavItemData item in items) {
    if (_routeMatches(currentPath, item.routePath)) {
      return item.label;
    }
  }
  return null;
}

String _navigationLabel(BuildContext context) {
  switch (Localizations.localeOf(context).languageCode) {
    case 'zh':
      return '導覽';
    case 'fr':
      return 'Navigation';
    case 'ja':
      return 'ナビゲーション';
    default:
      return 'Navigation';
  }
}

String _settingsLabel(BuildContext context) {
  switch (Localizations.localeOf(context).languageCode) {
    case 'zh':
      return '設定';
    case 'fr':
      return 'Paramètres';
    case 'ja':
      return '設定';
    default:
      return 'Settings';
  }
}

String _deviceInvitationsLabel(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'zh'
      ? '裝置邀請'
      : 'Device invitations';
}

String _notificationCenterLabel(BuildContext context) {
  return Localizations.localeOf(context).languageCode == 'zh'
      ? '通知中心'
      : 'Notification center';
}

String _managementLabel(BuildContext context) {
  switch (Localizations.localeOf(context).languageCode) {
    case 'zh':
      return '管理';
    case 'fr':
      return 'Gestion';
    case 'ja':
      return '管理';
    default:
      return 'Management';
  }
}

class _FullscreenEdgeBackGesture extends StatefulWidget {
  const _FullscreenEdgeBackGesture({
    required this.child,
    required this.onBack,
  });

  final Widget child;
  final VoidCallback onBack;

  @override
  State<_FullscreenEdgeBackGesture> createState() =>
      _FullscreenEdgeBackGestureState();
}

class _FullscreenEdgeBackGestureState
    extends State<_FullscreenEdgeBackGesture> {
  static const double _edgeWidth = 28;
  static const double _triggerDistance = 72;
  static const double _triggerVelocity = 450;

  bool _tracking = false;
  bool _triggered = false;
  double _dx = 0;
  double _dy = 0;

  void _reset() {
    _tracking = false;
    _triggered = false;
    _dx = 0;
    _dy = 0;
  }

  void _maybeTrigger({double velocity = 0}) {
    if (!_tracking || _triggered) return;
    final horizontalIntent = _dx > 0 && _dx.abs() > (_dy.abs() * 1.4);
    final farEnough = _dx >= _triggerDistance;
    final fastEnough = velocity >= _triggerVelocity;
    if (horizontalIntent && (farEnough || fastEnough)) {
      _triggered = true;
      widget.onBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        final isAtLeadingEdge = details.localPosition.dx <= _edgeWidth;
        if (!isAtLeadingEdge) {
          _reset();
          return;
        }
        _tracking = true;
        _triggered = false;
        _dx = 0;
        _dy = 0;
      },
      onHorizontalDragUpdate: (details) {
        if (!_tracking) return;
        _dx += details.delta.dx;
        _dy += details.delta.dy;
        if (_dx < -8 || _dy.abs() > 48) {
          _reset();
          return;
        }
        _maybeTrigger();
      },
      onHorizontalDragEnd: (details) {
        _maybeTrigger(velocity: details.primaryVelocity ?? 0);
        _reset();
      },
      onHorizontalDragCancel: _reset,
      child: widget.child,
    );
  }
}
