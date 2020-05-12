library panelroute;

// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

typedef PanelWidgetBuilder = Widget Function(BuildContext, DelegatingScrollController);

const double dismissGestureHeight = 50.0;
const double minFlingVelocity = 0.1; // Screen heights per second

// An eyeballed value for the maximum time it takes for a page to animate forward
// if the user releases a page mid swipe.
const int maxDroppedSwipePageForwardAnimationTime = 800; // Milliseconds.

// The maximum time for a page to get reset to it's original position if the
// user releases a page mid swipe.
const int maxPageBackAnimationTime = 300; // Milliseconds.

// Offset from offscreen to the right to fully on screen.
final Animatable<Offset> _kRightMiddleTween = Tween<Offset>(
  begin: const Offset(0.0, 1.0),
  end: Offset.zero,
);

// Offset from fully on screen to 1/3 offscreen to the left.
final Animatable<Color> _kMiddleLeftTween = ColorTween(
  begin: Colors.transparent,
  end: Colors.black,
);

// TODO: implement gesture recognizer for full screen swipe

/// A modal route that replaces the entire screen with an iOS transition.
///
/// The page slides in from the right and exits in reverse. The page also shifts
/// to the left in parallax when another page enters to cover it.
///
/// The page slides in from the bottom and exits in reverse with no parallax
/// effect for fullscreen dialogs.
///
/// By default, when a modal route is replaced by another, the previous route
/// remains in memory. To free all the resources when this is not necessary, set
/// [maintainState] to false.
///
/// The type `T` specifies the return type of the route which can be supplied as
/// the route is popped from the stack via [Navigator.pop] when an optional
/// `result` can be provided.
///
/// See also:
///
///  * [MaterialPageRoute], for an adaptive [PageRoute] that uses a
///    platform-appropriate transition.
///  * [CupertinoPageScaffold], for applications that have one page with a fixed
///    navigation bar on top.
///  * [CupertinoTabScaffold], for applications that have a tab bar at the
///    bottom with multiple pages.
class PanelPageRoute<T> extends PageRoute<T> {
  /// Creates a page route for use in an iOS designed app.
  ///
  /// The [builder], [maintainState], and [fullscreenDialog] arguments must not
  /// be null.
  PanelPageRoute({
    @required this.builder,
    this.isPopup = false,
    this.handleBuilder,
    RouteSettings settings,
    this.maintainState = true,
    bool fullscreenDialog = false,
    int scrollViewCount = 1,
    int defaultScrollView = 0,
  }) : assert(builder != null),
        assert(maintainState != null),
        assert(fullscreenDialog != null),
        assert(opaque),
        scrollController = DelegatingScrollController(scrollViewCount, defaultScrollView: defaultScrollView),
        super(settings: settings, fullscreenDialog: fullscreenDialog);

  /// Builds the primary contents of the route.
  final PanelWidgetBuilder builder;

  final bool isPopup;

  final WidgetBuilder handleBuilder;

  final ScrollController scrollController;

  @override
  final bool maintainState;

  @override
  // A relatively rigorous eyeball estimation.
  Duration get transitionDuration => const Duration(milliseconds: 400);

  @override
  Color get barrierColor => null;

  @override
  String get barrierLabel => null;

  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) {
    return previousRoute is PanelPageRoute;
  }

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) {
    // Don't perform outgoing animation if the next route is a fullscreen dialog.
    return nextRoute is PanelPageRoute && !nextRoute.fullscreenDialog;
  }

  /// True if a swipe from the top is currently underway for [route].
  ///
  /// This just check the route's [NavigatorState.userGestureInProgress].
  ///
  /// See also:
  ///
  ///  * [popGestureEnabled], which returns true if a user-triggered pop gesture
  ///    would be allowed.
  static bool isDismissGestureInProgress(PageRoute<dynamic> route) {
    return route.navigator.userGestureInProgress;
  }

  /// True if a swipe from the top is currently underway for this route.
  ///
  /// See also:
  ///
  ///  * [isPopGestureInProgress], which returns true if a Cupertino pop gesture
  ///    is currently underway for specific route.
  ///  * [popGestureEnabled], which returns true if a user-triggered pop gesture
  ///    would be allowed.
  bool get dismissGestureInProgress => isDismissGestureInProgress(this);

  /// Whether a dismiss gesture can be started by the user.
  ///
  /// Returns true if the user can edge-swipe to a previous route.
  ///
  /// Returns false once [isPopGestureInProgress] is true, but
  /// [isPopGestureInProgress] can only become true if [popGestureEnabled] was
  /// true first.
  ///
  /// This should only be used between frames, not during build.
  bool get dismissGestureEnabled => _isDismissGestureEnabled(this);

  static bool _isDismissGestureEnabled<T>(PageRoute<T> route) {
    // We can close with swipe only popup
    if (route is PanelPageRoute && !(route as PanelPageRoute).isPopup)
      return false;
    // If there's nothing to go back to, then obviously we don't support
    // the back gesture.
    if (route.isFirst)
      return false;
    // If the route wouldn't actually pop if we popped it, then the gesture
    // would be really confusing (or would skip internal routes), so disallow it.
    if (route.willHandlePopInternally)
      return false;
    // Fullscreen dialogs aren't dismissible by back swipe.
    if (route.fullscreenDialog)
      return false;
    // If we're in an animation already, we cannot be manually swiped.
    if (route.animation.status != AnimationStatus.completed)
      return false;
    // If we're being popped into, we also cannot be swiped until the pop above
    // it completes. This translates to our secondary animation being
    // dismissed.
    if (route.secondaryAnimation.status != AnimationStatus.dismissed)
      return false;
    // If we're in a gesture already, we cannot start another.
    if (isDismissGestureInProgress(route))
      return false;

    // Looks like a back gesture would be welcome!
    return true;
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final Widget child = isPopup
        ? AnnotatedRegion<SystemUiOverlayStyle>(
            value: SystemUiOverlayStyle(
              statusBarBrightness: Brightness.dark,
            ),
            child: SafeArea(
              bottom: false,
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                child: Stack(
                  children: [
                    builder(context, scrollController),
                    if (handleBuilder != null)
                      Positioned(
                        left: 0,
                        top: 0,
                        right: 0,
                        child: handleBuilder(context),
                      ),
                  ],
                ),
              ),
            ),
          )
        : builder(context, scrollController);

    final Widget result = Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      child: child,
    );
    assert(() {
      if (child == null) {
        throw FlutterError.fromParts(<DiagnosticsNode>[
          ErrorSummary('The builder for route "${settings.name}" returned null.'),
          ErrorDescription('Route builders must never return null.'),
        ]);
      }
      return true;
    }());
    return result;
  }

  // Called by _CupertinoBackGestureDetector when a pop ("back") drag start
  // gesture is detected. The returned controller handles all of the subsequent
  // drag events.
  static _PanelDismissGestureController<T> _startDismissGesture<T>(PageRoute<T> route) {
    assert(_isDismissGestureEnabled(route));

    return _PanelDismissGestureController<T>(
      navigator: route.navigator,
      controller: route.controller, // protected access
    );
  }

  /// Returns a [CupertinoFullscreenDialogTransition] if [route] is a full
  /// screen dialog, otherwise a [PanelPageTransition] is returned.
  ///
  /// Used by [PanelPageRoute.buildTransitions].
  ///
  /// This method can be applied to any [PageRoute], not just
  /// [PanelPageRoute].
  static Widget buildPageTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
      ScrollController scrollController,
      ) {

    if (route.fullscreenDialog) {
      return CupertinoFullscreenDialogTransition(
        primaryRouteAnimation: animation,
        secondaryRouteAnimation: animation,
        linearTransition: true,
        child: child,
      );
    } else {
      return PanelPageTransition(
        primaryRouteAnimation: animation,
        secondaryRouteAnimation: secondaryAnimation,
        // Check if the route has an animation that's currently participating
        // in a back swipe gesture.
        //
        // In the middle of a back gesture drag, let the transition be linear to
        // match finger motions.
        linearTransition: isDismissGestureInProgress(route),
        child: _PanelDismissGestureDetector<T>(
          isDismissGesture: (event) => _isDismissGesture<T>(route, event, scrollController),
          isOverscrollAllowed: (event) => _isDismissOnOverscrollAllowed(route, event, scrollController),
          onStartDismissGesture: () => _startDismissGesture<T>(route),
          child: child,
          scrollController: scrollController,
        ),
      );
    }
  }

  static DismissGesture _isDismissGesture<T>(PageRoute<T> route, PointerDownEvent event, ScrollController scrollController) {
    if (!_isDismissGestureEnabled(route)) {
      return null;
    }

    if (event.position.dy <= dismissGestureHeight) {
      return DismissGesture.handle;
    }

    try {
      if (scrollController.offset <= 0) {
        return DismissGesture.overscroll;
      }
    } catch (e) {
      print("[PanelPageRoute] _isSwipeToDismissAllowedForMovement() error: ${e.toString()}");
    }

    return null;
  }

  static bool _isDismissOnOverscrollAllowed<T>(PageRoute<T> route, PointerMoveEvent event, ScrollController scrollController) {
    try {
      if (event.delta.dy > 0 && scrollController.offset <= 0) {
        return true;
      }
    } catch (e) {
      print("[PanelPageRoute] _isSwipeToDismissAllowedForMovement() error: ${e.toString()}");
    }

    return false;
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    return buildPageTransitions<T>(this, context, animation, secondaryAnimation, child, scrollController);
  }

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';
}

class PanelPageTransition extends StatelessWidget {
  /// Creates an iOS-style page transition.
  ///
  ///  * `primaryRouteAnimation` is a linear route animation from 0.0 to 1.0
  ///    when this screen is being pushed.
  ///  * `secondaryRouteAnimation` is a linear route animation from 0.0 to 1.0
  ///    when another screen is being pushed on top of this one.
  ///  * `linearTransition` is whether to perform primary transition linearly.
  ///    Used to precisely track back gesture drags.
  PanelPageTransition({
    Key key,
    @required Animation<double> primaryRouteAnimation,
    @required Animation<double> secondaryRouteAnimation,
    @required this.child,
    @required bool linearTransition,
  }) : assert(linearTransition != null),
        _primaryPositionAnimation =
          (linearTransition
              ? primaryRouteAnimation
              : CurvedAnimation(
                  parent: primaryRouteAnimation,
                  curve: Curves.linearToEaseOut,
                  reverseCurve: Curves.easeInToLinear,
                )
          ).drive(_kRightMiddleTween),
        _secondaryPositionAnimation =
          (linearTransition
              ? secondaryRouteAnimation
              : CurvedAnimation(
                  parent: secondaryRouteAnimation,
                  curve: Curves.linearToEaseOut,
                  reverseCurve: Curves.easeInToLinear,
                )
          ).drive(_kMiddleLeftTween),
        super(key: key);

  // When this page is coming in to cover another page.
  final Animation<Offset> _primaryPositionAnimation;
  // When this page is becoming covered by another page.
  final Animation<Color> _secondaryPositionAnimation;

  /// The widget below this widget in the tree.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasDirectionality(context));
    final TextDirection textDirection = Directionality.of(context);
    return ColorFiltered(
      colorFilter: ColorFilter.mode(_secondaryPositionAnimation.value, BlendMode.srcOver),
      child: SlideTransition(
        position: _primaryPositionAnimation,
        textDirection: textDirection,
        child: child,
      ),
    );
  }
}

/// This is the widget side of [_PanelDismissGestureController].
///
/// This widget provides a gesture recognizer which, when it determines the
/// route can be closed with a back gesture, creates the controller and
/// feeds it the input from the gesture recognizer.
///
/// The gesture data is converted from absolute coordinates to logical
/// coordinates by this widget.
///
/// The type `T` specifies the return type of the route with which this gesture
/// detector is associated.
class _PanelDismissGestureDetector<T> extends StatefulWidget {
  const _PanelDismissGestureDetector({
    Key key,
    @required this.isDismissGesture,
    @required this.isOverscrollAllowed,
    @required this.onStartDismissGesture,
    @required this.child,
    this.scrollController,
  }) : assert(isDismissGesture != null),
        assert(isOverscrollAllowed != null),
        assert(onStartDismissGesture != null),
        assert(child != null),
        super(key: key);

  final Widget child;

  final DismissGesture Function(PointerDownEvent) isDismissGesture;
  final bool Function(PointerMoveEvent) isOverscrollAllowed;

  final ValueGetter<_PanelDismissGestureController<T>> onStartDismissGesture;

  final ScrollController scrollController;

  @override
  _PanelDismissOnTopGestureDetectorState<T> createState() => _PanelDismissOnTopGestureDetectorState<T>(scrollController);
}

class _PanelDismissOnTopGestureDetectorState<T> extends State<_PanelDismissGestureDetector<T>> {
  _PanelDismissGestureController<T> _dismissGestureController;

  VerticalDragGestureRecognizer _recognizer;

  final ScrollController scrollController;

  DismissGesture _dismissGesture;

  _PanelDismissOnTopGestureDetectorState(this.scrollController);

  @override
  void initState() {
    super.initState();
    _recognizer = VerticalDragGestureRecognizer(debugOwner: this)
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    assert(mounted);
    assert(_dismissGestureController == null);
    _dismissGestureController = widget.onStartDismissGesture();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    assert(mounted);
    assert(_dismissGestureController != null);
    _dismissGestureController.dragUpdate(_convertToLogical(details.primaryDelta / context.size.height));
  }

  void _handleDragEnd(DragEndDetails details) {
    assert(mounted);
    assert(_dismissGestureController != null);
    _dismissGestureController.dragEnd(_convertToLogical(details.velocity.pixelsPerSecond.dx / context.size.height));
    _dismissGestureController = null;
    _dismissGesture = null;
  }

  void _handleDragCancel() {
    assert(mounted);
    // This can be called even if start is not called, paired with the "down" event
    // that we don't consider here.
    _dismissGestureController?.dragEnd(0.0);
    _dismissGestureController = null;
    _dismissGesture = null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _dismissGesture = widget.isDismissGesture(event);
    if (_dismissGesture != null) {
      _recognizer.addPointer(event);
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_dismissGesture == DismissGesture.overscroll && !widget.isOverscrollAllowed(event)) {
      _recognizer.rejectGesture(event.pointer);
      _dismissGesture = null;
    }
  }

  double _convertToLogical(double value) {
    switch (Directionality.of(context)) {
      case TextDirection.rtl:
        return -value;
      case TextDirection.ltr:
        return value;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasDirectionality(context));
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        widget.child,
        Listener(
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          behavior: HitTestBehavior.translucent,
        ),
      ],
    );
  }
}

/// This is created by a [PanelPageRoute] in response from a gesture caught
/// by a [_PanelDismissGestureDetector] widget, which then also feeds it input
/// from the gesture. It controls the animation controller owned by the route,
/// based on the input provided by the gesture detector.
///
/// This class works entirely in logical coordinates (0.0 is new page dismissed,
/// 1.0 is new page on top).
///
/// The type `T` specifies the return type of the route with which this gesture
/// detector controller is associated.
class _PanelDismissGestureController<T> {
  /// Creates a controller for an iOS-style back gesture.
  ///
  /// The [navigator] and [controller] arguments must not be null.
  _PanelDismissGestureController({
    @required this.navigator,
    @required this.controller,
  }) : assert(navigator != null),
        assert(controller != null) {
    navigator.didStartUserGesture();
  }

  final AnimationController controller;
  final NavigatorState navigator;

  /// The drag gesture has changed by [fractionalDelta]. The total range of the
  /// drag should be 0.0 to 1.0.
  void dragUpdate(double delta) {
    controller.value -= delta;
  }

  /// The drag gesture has ended with a vertical motion of
  /// [fractionalVelocity] as a fraction of screen heights per second.
  void dragEnd(double velocity) {
    // Fling in the appropriate direction.
    // AnimationController.fling is guaranteed to
    // take at least one frame.
    //
    // This curve has been determined through rigorously eyeballing native iOS
    // animations.
    const Curve animationCurve = Curves.fastLinearToSlowEaseIn;
    bool animateForward;

    // If the user releases the page before mid screen with sufficient velocity,
    // or after mid screen, we should animate the page out. Otherwise, the page
    // should be animated back in.
    if (velocity.abs() >= minFlingVelocity) {
      animateForward = velocity <= 0;
    } else {
      animateForward = controller.value > 0.5;
    }

    if (animateForward) {
      // The closer the panel is to dismissing, the shorter the animation is.
      // We want to cap the animation time, but we want to use a linear curve
      // to determine it.
      final int droppedPageForwardAnimationTime = min(
        lerpDouble(maxDroppedSwipePageForwardAnimationTime, 0, controller.value).floor(),
        maxPageBackAnimationTime,
      );
      controller.animateTo(1.0, duration: Duration(milliseconds: droppedPageForwardAnimationTime), curve: animationCurve);
    } else {
      // This route is destined to pop at this point. Reuse navigator's pop.
      navigator.pop();

      // The popping may have finished inline if already at the target destination.
      if (controller.isAnimating) {
        // Otherwise, use a custom popping animation duration and curve.
        final int droppedPageBackAnimationTime = lerpDouble(0, maxDroppedSwipePageForwardAnimationTime, controller.value).floor();
        controller.animateBack(0.0, duration: Duration(milliseconds: droppedPageBackAnimationTime), curve: animationCurve);
      }
    }

    if (controller.isAnimating) {
      // Keep the userGestureInProgress in true state so we don't change the
      // curve of the page transition mid-flight since CupertinoPageTransition
      // depends on userGestureInProgress.
      AnimationStatusListener animationStatusCallback;
      animationStatusCallback = (AnimationStatus status) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(animationStatusCallback);
      };
      controller.addStatusListener(animationStatusCallback);
    } else {
      navigator.didStopUserGesture();
    }
  }
}

enum DismissGesture { handle, overscroll }

class DelegatingScrollController implements ScrollController {
  final List<ScrollController> _delegates;
  final List<VoidCallback> _listeners = [];

  ScrollController _currentDelegate;

  DelegatingScrollController(int scrollViewCount, {int defaultScrollView = 0})
      : _delegates = [for (int i = 0; i < scrollViewCount; i++) ScrollController()] {
    _currentDelegate = _delegates[defaultScrollView];
  }

  void delegateTo(int i) {
    _listeners.forEach((listener) => _currentDelegate.removeListener(listener));
    this._currentDelegate = _delegates[i];
    _listeners.forEach((listener) => _currentDelegate.addListener(listener));
  }

  @override
  void debugFillDescription(List<String> description) {
    _currentDelegate.debugFillDescription(description);
  }

  @override
  String toString() {
    return _currentDelegate.toString();
  }

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics, ScrollContext context, ScrollPosition oldPosition) {
    return _currentDelegate.createScrollPosition(physics, context, oldPosition);
  }

  @override
  void dispose() {
    _currentDelegate.dispose();
  }

  @override
  void detach(ScrollPosition position) {
    _currentDelegate.detach(position);
  }

  @override
  void attach(ScrollPosition position) {
    _currentDelegate.attach(position);
  }

  @override
  void jumpTo(double value) {
    _currentDelegate.jumpTo(value);
  }

  @override
  Future<Function> animateTo(double offset, {@required Duration duration, @required Curve curve}) {
    return _currentDelegate.animateTo(offset, duration: duration, curve: curve);
  }

  @override
  double get offset {
    return _currentDelegate.offset;
  }

  @override
  ScrollPosition get position {
    return _currentDelegate.position;
  }

  @override
  bool get hasClients {
    return _currentDelegate.hasClients;
  }

  @override
  Iterable<ScrollPosition> get positions {
    return _currentDelegate.positions;
  }

  @override
  double get initialScrollOffset {
    return _currentDelegate.initialScrollOffset;
  }

  @override
  void addListener(listener) {
    _listeners.add(listener);
    _currentDelegate.addListener(listener);
  }

  @override
  String get debugLabel => _currentDelegate.debugLabel;

  @override
  bool get hasListeners => _currentDelegate.hasListeners;

  @override
  bool get keepScrollOffset => _currentDelegate.keepScrollOffset;

  @override
  void notifyListeners() {
    _currentDelegate.notifyListeners();
  }

  @override
  void removeListener(listener) {
    _listeners.remove(listener);
    _currentDelegate.removeListener(listener);
  }

  ScrollController delegate(int i) => _delegates[i];
}