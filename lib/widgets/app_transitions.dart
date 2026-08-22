import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_motion.dart';

enum AppRouteTransition {
  none,
  fade,
  fadeScale,
  drillIn,
  rightSheet,
}

Page<T> appRoutePage<T>({
  required GoRouterState state,
  required Widget child,
  AppRouteTransition transition = AppRouteTransition.fade,
}) {
  if (!kIsWeb && transition != AppRouteTransition.none) {
    return MaterialPage<T>(
      key: state.pageKey,
      child: child,
    );
  }

  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionDuration: _durationFor(transition),
    reverseTransitionDuration: _durationFor(transition),
    transitionsBuilder: _builderFor(transition),
  );
}

Route<T> appPageRoute<T>({
  required WidgetBuilder builder,
  AppRouteTransition transition = AppRouteTransition.drillIn,
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) {
  if (!kIsWeb && transition == AppRouteTransition.drillIn) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return CupertinoPageRoute<T>(
        builder: builder,
        settings: settings,
        fullscreenDialog: fullscreenDialog,
      );
    }

    return MaterialPageRoute<T>(
      builder: builder,
      settings: settings,
      fullscreenDialog: fullscreenDialog,
    );
  }

  return PageRouteBuilder<T>(
    settings: settings,
    fullscreenDialog: fullscreenDialog,
    transitionDuration: _durationFor(transition),
    reverseTransitionDuration: _durationFor(transition),
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: _builderFor(transition),
  );
}

Future<T?> pushAppPage<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  AppRouteTransition transition = AppRouteTransition.drillIn,
}) {
  return Navigator.of(context).push<T>(
    appPageRoute<T>(builder: builder, transition: transition),
  );
}

Future<T?> pushReplacementAppPage<T, TO>(
  BuildContext context, {
  required WidgetBuilder builder,
  AppRouteTransition transition = AppRouteTransition.drillIn,
  TO? result,
}) {
  return Navigator.of(context).pushReplacement<T, TO>(
    appPageRoute<T>(builder: builder, transition: transition),
    result: result,
  );
}

Widget appTransitionBuilder({
  required BuildContext context,
  required Animation<double> animation,
  required Animation<double> secondaryAnimation,
  required Widget child,
  required AppRouteTransition transition,
}) {
  if (transition == AppRouteTransition.none ||
      AppMotion.reduceMotion(context)) {
    return child;
  }

  final enter = CurvedAnimation(
    parent: animation,
    curve: AppMotion.enterCurve,
    reverseCurve: AppMotion.exitCurve,
  );

  switch (transition) {
    case AppRouteTransition.none:
      return child;
    case AppRouteTransition.fade:
      return FadeTransition(opacity: enter, child: child);
    case AppRouteTransition.fadeScale:
      return FadeTransition(
        opacity: enter,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(enter),
          child: child,
        ),
      );
    case AppRouteTransition.drillIn:
      final slide = Tween<Offset>(
        begin: const Offset(0.08, 0),
        end: Offset.zero,
      ).animate(enter);
      return FadeTransition(
        opacity: enter,
        child: SlideTransition(position: slide, child: child),
      );
    case AppRouteTransition.rightSheet:
      final slide = Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(enter);
      return FadeTransition(
        opacity: enter,
        child: SlideTransition(position: slide, child: child),
      );
  }
}

Duration _durationFor(AppRouteTransition transition) {
  return transition == AppRouteTransition.none ? Duration.zero : AppMotion.page;
}

RouteTransitionsBuilder _builderFor(AppRouteTransition transition) {
  return (context, animation, secondaryAnimation, child) {
    return appTransitionBuilder(
      context: context,
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
      transition: transition,
    );
  };
}

class AppDirectionalSwitcher extends StatelessWidget {
  const AppDirectionalSwitcher({
    super.key,
    required this.child,
    required this.forward,
    this.duration = AppMotion.page,
    this.reverseDuration,
    this.offset = 1.0,
    this.fade = true,
    this.lightweightOutgoing = false,
  });

  final Widget child;
  final bool forward;
  final Duration duration;
  final Duration? reverseDuration;
  final double offset;
  final bool fade;
  final bool lightweightOutgoing;

  @override
  Widget build(BuildContext context) {
    final currentKey = child.key;
    if (AppMotion.reduceMotion(context)) {
      return child;
    }

    return AnimatedSwitcher(
      duration: AppMotion.maybeZero(context, duration),
      reverseDuration: AppMotion.maybeZero(
        context,
        reverseDuration ?? duration,
      ),
      switchInCurve: AppMotion.enterCurve,
      switchOutCurve: AppMotion.exitCurve,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final isIncoming = child.key == currentKey;
        if (lightweightOutgoing && !isIncoming) {
          return fade
              ? FadeTransition(opacity: animation, child: child)
              : child;
        }

        final beginOffset = isIncoming
            ? (forward ? Offset(offset, 0) : Offset(-offset, 0))
            : (forward ? Offset(-offset, 0) : Offset(offset, 0));
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: AppMotion.enterCurve,
          reverseCurve: AppMotion.exitCurve,
        );
        Widget transitionChild = SlideTransition(
          position: Tween<Offset>(
            begin: beginOffset,
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: child,
        );
        if (fade) {
          transitionChild = FadeTransition(
            opacity: animation,
            child: transitionChild,
          );
        }
        return ClipRect(child: transitionChild);
      },
      child: child,
    );
  }
}

class AppFadeScaleSwitcher extends StatelessWidget {
  const AppFadeScaleSwitcher({
    super.key,
    required this.child,
    this.duration = AppMotion.page,
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduceMotion(context)) return child;
    return AnimatedSwitcher(
      duration: AppMotion.maybeZero(context, duration),
      switchInCurve: AppMotion.enterCurve,
      switchOutCurve: AppMotion.exitCurve,
      transitionBuilder: (child, animation) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: AppMotion.enterCurve,
          reverseCurve: AppMotion.exitCurve,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(curvedAnimation),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
