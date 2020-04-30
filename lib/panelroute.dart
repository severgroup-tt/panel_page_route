library panelroute;

// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/animation.dart' show Curves;

const double _kBackGestureWidth = 20.0;
const double _kMinFlingVelocity = 0.3; //1.0; // Screen widths per second.

// An eyeballed value for the maximum time it takes for a page to animate forward
// if the user releases a page mid swipe.
const int _kMaxDroppedSwipePageForwardAnimationTime = 800; // Milliseconds.

// The maximum time for a page to get reset to it's original position if the
// user releases a page mid swipe.
const int _kMaxPageBackAnimationTime = 300; // Milliseconds.

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
//Tween<Offset>(
//  begin: Offset.zero,
//  end: const Offset(0.0, -1.0/3.0),
//);

// Custom decoration from no shadow to page shadow mimicking iOS page
// transitions using gradients.
final DecorationTween _kGradientShadowTween = DecorationTween(
  begin: BoxDecoration(color: Colors.transparent),
//  _PanelEdgeShadowDecoration.none, // No decoration initially.
  end: BoxDecoration(color: Colors.black),
//  const _PanelEdgeShadowDecoration(
//    edgeGradient: LinearGradient(
//       Spans 5% of the page.
//      begin: AlignmentDirectional(0.90, 0.0),
//      end: AlignmentDirectional.centerEnd,
//       Eyeballed gradient used to mimic a drop shadow on the start side only.
//      colors: <Color>[
//        Color(0x00000000),
//        Color(0x04000000),
//        Color(0x12000000),
//        Color(0x38000000),
//      ],
//      stops: <double>[0.0, 0.3, 0.6, 1.0],
//    ),
//  ),
);

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
    this.title,
    RouteSettings settings,
    this.maintainState = true,
    bool fullscreenDialog = false,
  }) : assert(builder != null),
        assert(maintainState != null),
        assert(fullscreenDialog != null),
        assert(opaque),
        super(settings: settings, fullscreenDialog: fullscreenDialog);

  /// Builds the primary contents of the route.
  final WidgetBuilder builder;

  /// A title string for this route.
  ///
  /// Used to auto-populate [CupertinoNavigationBar] and
  /// [CupertinoSliverNavigationBar]'s `middle`/`largeTitle` widgets when
  /// one is not manually supplied.
  final String title;

  ValueNotifier<String> _previousTitle;

  /// The title string of the previous [PanelPageRoute].
  ///
  /// The [ValueListenable]'s value is readable after the route is installed
  /// onto a [Navigator]. The [ValueListenable] will also notify its listeners
  /// if the value changes (such as by replacing the previous route).
  ///
  /// The [ValueListenable] itself will be null before the route is installed.
  /// Its content value will be null if the previous route has no title or
  /// is not a [PanelPageRoute].
  ///
  /// See also:
  ///
  ///  * [ValueListenableBuilder], which can be used to listen and rebuild
  ///    widgets based on a ValueListenable.
  ValueListenable<String> get previousTitle {
    assert(
    _previousTitle != null,
    'Cannot read the previousTitle for a route that has not yet been installed',
    );
    return _previousTitle;
  }

  @override
  void didChangePrevious(Route<dynamic> previousRoute) {
    final String previousTitleString = previousRoute is PanelPageRoute
        ? previousRoute.title
        : null;
    if (_previousTitle == null) {
      _previousTitle = ValueNotifier<String>(previousTitleString);
    } else {
      _previousTitle.value = previousTitleString;
    }
    super.didChangePrevious(previousRoute);
  }

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

  /// True if an iOS-style back swipe pop gesture is currently underway for [route].
  ///
  /// This just check the route's [NavigatorState.userGestureInProgress].
  ///
  /// See also:
  ///
  ///  * [popGestureEnabled], which returns true if a user-triggered pop gesture
  ///    would be allowed.
  static bool isPopGestureInProgress(PageRoute<dynamic> route) {
    return route.navigator.userGestureInProgress;
  }

  /// True if an iOS-style back swipe pop gesture is currently underway for this route.
  ///
  /// See also:
  ///
  ///  * [isPopGestureInProgress], which returns true if a Cupertino pop gesture
  ///    is currently underway for specific route.
  ///  * [popGestureEnabled], which returns true if a user-triggered pop gesture
  ///    would be allowed.
  bool get popGestureInProgress => isPopGestureInProgress(this);

  /// Whether a pop gesture can be started by the user.
  ///
  /// Returns true if the user can edge-swipe to a previous route.
  ///
  /// Returns false once [isPopGestureInProgress] is true, but
  /// [isPopGestureInProgress] can only become true if [popGestureEnabled] was
  /// true first.
  ///
  /// This should only be used between frames, not during build.
  bool get popGestureEnabled => _isPopGestureEnabled(this);

  static bool _isPopGestureEnabled<T>(PageRoute<T> route) {
    // If there's nothing to go back to, then obviously we don't support
    // the back gesture.
    if (route.isFirst)
      return false;
    // If the route wouldn't actually pop if we popped it, then the gesture
    // would be really confusing (or would skip internal routes), so disallow it.
    if (route.willHandlePopInternally)
      return false;
    // If attempts to dismiss this route might be vetoed such as in a page
    // with forms, then do not allow the user to dismiss the route with a swipe.
    if (route.hasScopedWillPopCallback)
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
    if (isPopGestureInProgress(route))
      return false;

    // Looks like a back gesture would be welcome!
    return true;
  }

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final Widget child = SafeArea(
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        child: builder(context),
      ),
    );

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
  static _PanelBackGestureController<T> _startPopGesture<T>(PageRoute<T> route) {
    assert(_isPopGestureEnabled(route));

    return _PanelBackGestureController<T>(
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
  /// [PanelPageRoute]. It's typically used to provide a Cupertino style
  /// horizontal transition for material widgets when the target platform
  /// is [TargetPlatform.iOS].
  ///
  /// See also:
  ///
  ///  * [CupertinoPageTransitionsBuilder], which uses this method to define a
  ///    [PageTransitionsBuilder] for the [PageTransitionsTheme].
  static Widget buildPageTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
      ) {
    if (route.fullscreenDialog) {
      return CupertinoFullscreenDialogTransition(
        animation: animation,
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
        linearTransition: isPopGestureInProgress(route),
        child: _PanelBackGestureDetector<T>(
          enabledCallback: () => _isPopGestureEnabled<T>(route),
          onStartPopGesture: () => _startPopGesture<T>(route),
          child: child,
        ),
      );
    }
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    return buildPageTransitions<T>(this, context, animation, secondaryAnimation, child);
  }

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';
}

/// Provides an iOS-style page transition animation.
///
/// The page slides in from the right and exits in reverse. It also shifts to the left in
/// a parallax motion when another page enters to cover it.
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
            // The curves below have been rigorously derived from plots of native
            // iOS animation frames. Specifically, a video was taken of a page
            // transition animation and the distance in each frame that the page
            // moved was measured. A best fit bezier curve was the fitted to the
            // point set, which is linearToEaseIn. Conversely, easeInToLinear is the
            // reflection over the origin of linearToEaseIn.
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
//        _primaryShadowAnimation =
//          (linearTransition
//              ? primaryRouteAnimation
//              : CurvedAnimation(
//            parent: primaryRouteAnimation,
//            curve: Curves.linearToEaseOut,
//          )
//          ).drive(_kGradientShadowTween),
        super(key: key);

  // When this page is coming in to cover another page.
  final Animation<Offset> _primaryPositionAnimation;
  // When this page is becoming covered by another page.
  final Animation<Color> _secondaryPositionAnimation;
//  final Animation<Decoration> _primaryShadowAnimation;

  /// The widget below this widget in the tree.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    assert(debugCheckHasDirectionality(context));
    final TextDirection textDirection = Directionality.of(context);
//    return SlideTransition(
//      position: _secondaryPositionAnimation,
//      textDirection: textDirection,
//      transformHitTests: false,
//      child:
      return SlideTransition(
        position: _primaryPositionAnimation,
        textDirection: textDirection,
        child:
        ColorFiltered(
          colorFilter: ColorFilter.mode(_secondaryPositionAnimation.value, BlendMode.srcOver),
          child: child,
        )
    );
  }
}

/// This is the widget side of [_PanelBackGestureController].
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
class _PanelBackGestureDetector<T> extends StatefulWidget {
  const _PanelBackGestureDetector({
    Key key,
    @required this.enabledCallback,
    @required this.onStartPopGesture,
    @required this.child,
  }) : assert(enabledCallback != null),
        assert(onStartPopGesture != null),
        assert(child != null),
        super(key: key);

  final Widget child;

  final ValueGetter<bool> enabledCallback;

  final ValueGetter<_PanelBackGestureController<T>> onStartPopGesture;

  @override
  _PanelBackGestureDetectorState<T> createState() => _PanelBackGestureDetectorState<T>();
}

class _PanelBackGestureDetectorState<T> extends State<_PanelBackGestureDetector<T>> {
  _PanelBackGestureController<T> _backGestureController;

  VerticalDragGestureRecognizer _recognizer;

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
    assert(_backGestureController == null);
    _backGestureController = widget.onStartPopGesture();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    assert(mounted);
    assert(_backGestureController != null);
    _backGestureController.dragUpdate(_convertToLogical(details.primaryDelta / context.size.height));
  }

  void _handleDragEnd(DragEndDetails details) {
    assert(mounted);
    assert(_backGestureController != null);
    _backGestureController.dragEnd(_convertToLogical(details.velocity.pixelsPerSecond.dx / context.size.height));
    _backGestureController = null;
  }

  void _handleDragCancel() {
    assert(mounted);
    // This can be called even if start is not called, paired with the "down" event
    // that we don't consider here.
    _backGestureController?.dragEnd(0.0);
    _backGestureController = null;
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.enabledCallback())
      _recognizer.addPointer(event);
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
    // For devices with notches, the drag area needs to be larger on the side
    // that has the notch.
    final double dragAreaHeight = MediaQuery.of(context).padding.top + 50;
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        widget.child,
        PositionedDirectional(
          start: 0.0,
          height: dragAreaHeight,
          top: 0.0,
          child: Listener(
            onPointerDown: _handlePointerDown,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }
}

/// A controller for an iOS-style back gesture.
///
/// This is created by a [PanelPageRoute] in response from a gesture caught
/// by a [_PanelBackGestureDetector] widget, which then also feeds it input
/// from the gesture. It controls the animation controller owned by the route,
/// based on the input provided by the gesture detector.
///
/// This class works entirely in logical coordinates (0.0 is new page dismissed,
/// 1.0 is new page on top).
///
/// The type `T` specifies the return type of the route with which this gesture
/// detector controller is associated.
class _PanelBackGestureController<T> {
  /// Creates a controller for an iOS-style back gesture.
  ///
  /// The [navigator] and [controller] arguments must not be null.
  _PanelBackGestureController({
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

  /// The drag gesture has ended with a horizontal motion of
  /// [fractionalVelocity] as a fraction of screen width per second.
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
    if (velocity.abs() >= _kMinFlingVelocity)
      animateForward = velocity <= 0;
    else
      animateForward = controller.value > 0.5;

    if (animateForward) {
      // The closer the panel is to dismissing, the shorter the animation is.
      // We want to cap the animation time, but we want to use a linear curve
      // to determine it.
      final int droppedPageForwardAnimationTime = min(
        lerpDouble(_kMaxDroppedSwipePageForwardAnimationTime, 0, controller.value).floor(),
        _kMaxPageBackAnimationTime,
      );
      controller.animateTo(1.0, duration: Duration(milliseconds: droppedPageForwardAnimationTime), curve: animationCurve);
    } else {
      // This route is destined to pop at this point. Reuse navigator's pop.
      navigator.pop();

      // The popping may have finished inline if already at the target destination.
      if (controller.isAnimating) {
        // Otherwise, use a custom popping animation duration and curve.
        final int droppedPageBackAnimationTime = lerpDouble(0, _kMaxDroppedSwipePageForwardAnimationTime, controller.value).floor();
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

// A custom [Decoration] used to paint an extra shadow on the start edge of the
// box it's decorating. It's like a [BoxDecoration] with only a gradient except
// it paints on the start side of the box instead of behind the box.
//
// The [edgeGradient] will be given a [TextDirection] when its shader is
// created, and so can be direction-sensitive; in this file we set it to a
// gradient that uses an AlignmentDirectional to position the gradient on the
// end edge of the gradient's box (which will be the edge adjacent to the start
// edge of the actual box we're supposed to paint in).
//class _PanelEdgeShadowDecoration extends Decoration {
//  const _PanelEdgeShadowDecoration({ this.edgeGradient });
//
//  // An edge shadow decoration where the shadow is null. This is used
//  // for interpolating from no shadow.
//  static const _PanelEdgeShadowDecoration none =
//  _PanelEdgeShadowDecoration();
//
//  // A gradient to draw to the left of the box being decorated.
//  // Alignments are relative to the original box translated one box
//  // width to the left.
//  final LinearGradient edgeGradient;
//
//  // Linearly interpolate between two edge shadow decorations decorations.
//  //
//  // The `t` argument represents position on the timeline, with 0.0 meaning
//  // that the interpolation has not started, returning `a` (or something
//  // equivalent to `a`), 1.0 meaning that the interpolation has finished,
//  // returning `b` (or something equivalent to `b`), and values in between
//  // meaning that the interpolation is at the relevant point on the timeline
//  // between `a` and `b`. The interpolation can be extrapolated beyond 0.0 and
//  // 1.0, so negative values and values greater than 1.0 are valid (and can
//  // easily be generated by curves such as [Curves.elasticInOut]).
//  //
//  // Values for `t` are usually obtained from an [Animation<double>], such as
//  // an [AnimationController].
//  //
//  // See also:
//  //
//  //  * [Decoration.lerp].
//  static _PanelEdgeShadowDecoration lerp(
//      _PanelEdgeShadowDecoration a,
//      _PanelEdgeShadowDecoration b,
//      double t,
//      ) {
//    assert(t != null);
//    if (a == null && b == null)
//      return null;
//    return _PanelEdgeShadowDecoration(
//      edgeGradient: LinearGradient.lerp(a?.edgeGradient, b?.edgeGradient, t),
//    );
//  }
//
//  @override
//  _PanelEdgeShadowDecoration lerpFrom(Decoration a, double t) {
//    if (a is! _PanelEdgeShadowDecoration)
//      return _PanelEdgeShadowDecoration.lerp(null, this, t);
//    return _PanelEdgeShadowDecoration.lerp(a, this, t);
//  }
//
//  @override
//  _PanelEdgeShadowDecoration lerpTo(Decoration b, double t) {
//    if (b is! _PanelEdgeShadowDecoration)
//      return _PanelEdgeShadowDecoration.lerp(this, null, t);
//    return _PanelEdgeShadowDecoration.lerp(this, b, t);
//  }
//
//  @override
//  _PanelEdgeShadowPainter createBoxPainter([ VoidCallback onChanged ]) {
//    return _PanelEdgeShadowPainter(this, onChanged);
//  }
//
//  @override
//  bool operator ==(dynamic other) {
//    if (runtimeType != other.runtimeType)
//      return false;
//    final _PanelEdgeShadowDecoration typedOther = other;
//    return edgeGradient == typedOther.edgeGradient;
//  }
//
//  @override
//  int get hashCode => edgeGradient.hashCode;
//
//  @override
//  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
//    super.debugFillProperties(properties);
//    properties.add(DiagnosticsProperty<LinearGradient>('edgeGradient', edgeGradient));
//  }
//}

/// A [BoxPainter] used to draw the page transition shadow using gradients.
//class _PanelEdgeShadowPainter extends BoxPainter {
//  _PanelEdgeShadowPainter(
//      this._decoration,
//      VoidCallback onChange,
//      ) : assert(_decoration != null),
//        super(onChange);
//
//  final _PanelEdgeShadowDecoration _decoration;
//
//  @override
//  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
//    final LinearGradient gradient = _decoration.edgeGradient;
//    if (gradient == null)
//      return;
//    // The drawable space for the gradient is a rect with the same size as
//    // its parent box one box width on the start side of the box.
//    final TextDirection textDirection = configuration.textDirection;
//    assert(textDirection != null);
//    double deltaX;
//    switch (textDirection) {
//      case TextDirection.rtl:
//        deltaX = configuration.size.width;
//        break;
//      case TextDirection.ltr:
//        deltaX = -configuration.size.width;
//        break;
//    }
//    final Rect rect = (offset & configuration.size).translate(deltaX, 0.0);
//    final Paint paint = Paint()
//      ..shader = gradient.createShader(rect, textDirection: textDirection);
//
//    canvas.drawRect(rect, paint);
//  }
//}