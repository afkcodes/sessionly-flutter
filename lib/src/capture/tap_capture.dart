/// Tap capture (docs/05). [SessionlyRoot] wraps your app with a single
/// top-level translucent [Listener]. On pointer-up it does O(1) work — record
/// the position and a timestamp, then schedule one post-frame callback. The
/// element-walk that resolves the tapped widget's *identity* runs post-frame,
/// bounded to [kTapWalkBudget] elements, never during hit-testing.
///
/// Identity is derived from stable attributes only — widget runtime type, key,
/// and an explicit `Semantics` label — never text content or input values
/// (docs/05 PII).
library;

import 'package:flutter/widgets.dart';
import 'package:sessionly_flutter/src/capture/runtime.dart';
import 'package:sessionly_flutter/src/protocol/vocabulary.dart';

/// Max ancestor elements the identity walk examines (docs/05: "≤ 25 elements").
const int kTapWalkBudget = 25;

/// Safety cap on the hit-path descent to the tapped leaf.
const int _kMaxDescent = 512;

/// Max down→up displacement (logical px) still counted as a tap; past it the
/// gesture is a drag/scroll, not a tap. Matches Flutter's `kTouchSlop` (18).
const double _kTapSlopPx = 18;

/// The stable identity of a tapped widget. Carries no user content.
class TapTarget {
  /// Creates a resolved target.
  const TapTarget({
    required this.widgetType,
    required this.interactive,
    this.keyString,
    this.semanticsLabel,
  });

  /// The identity widget's runtime type, e.g. `ElevatedButton`.
  final String widgetType;

  /// Whether the walk found an interactive widget (button/gesture handler).
  final bool interactive;

  /// The identity widget's `key.toString()`, when it has one.
  final String? keyString;

  /// An explicit `Semantics.label` found along the hit path, when present.
  final String? semanticsLabel;

  /// A compact, content-free identity string for frustration windows.
  String get identity =>
      [widgetType, keyString, semanticsLabel].whereType<String>().join('/');

  /// The event props form (nulls omitted).
  Map<String, Object?> toProps() => {
    'widget_type': widgetType,
    if (keyString != null) 'key': keyString,
    if (semanticsLabel != null) 'semantics_label': semanticsLabel,
  };
}

/// Wrap your app in this at the install point: `SessionlyRoot(child: MyApp())`.
class SessionlyRoot extends StatefulWidget {
  /// Wraps [child]; [runtime]/[nowMs] override the ambient runtime and clock in
  /// tests.
  const SessionlyRoot({
    required this.child,
    this.runtime,
    this.nowMs,
    super.key,
  });

  /// The app subtree to instrument.
  final Widget child;

  /// Test-only explicit runtime; app code leaves this null.
  final CaptureRuntime? runtime;

  /// Test-only clock seam; app code leaves this null (wall clock).
  final int Function()? nowMs;

  @override
  State<SessionlyRoot> createState() => _SessionlyRootState();
}

class _SessionlyRootState extends State<SessionlyRoot> {
  final GlobalKey _childKey = GlobalKey();
  Offset? _pending;
  int _pendingAtMs = 0;
  bool _scheduled = false;

  // Pointer-down positions (per pointer id), so a drag/scroll — pointer moved
  // past the slop between down and up — is NOT recorded as a tap. Every scroll
  // ends in a pointer-up; counting those as taps floods `tap` and (via
  // non-interactive targets) `dead_tap` on scrollable screens. Bounded: entries
  // are removed on up/cancel.
  final Map<int, Offset> _downPositions = <int, Offset>{};

  CaptureRuntime? get _runtime => widget.runtime ?? CaptureRuntime.current;

  int _now() {
    final clock = widget.nowMs;
    return clock != null ? clock() : DateTime.now().millisecondsSinceEpoch;
  }

  void _onPointerDown(PointerDownEvent event) {
    _downPositions[event.pointer] = event.position;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _downPositions.remove(event.pointer);
  }

  // Hot path (docs/05 budget < 0.5 ms): reject drags, then stash the point + the
  // tap time and arm one post-frame callback. The TIMESTAMP is taken here, on
  // pointer-up: the identity walk runs post-frame, a frame or more after the
  // tap and after any navigation it triggered, so stamping ts there would
  // order a tap after the screen_view it caused.
  void _onPointerUp(PointerUpEvent event) {
    final down = _downPositions.remove(event.pointer);
    // Moved past the slop → a drag/scroll, not a tap. A missing down is an anomaly
    // (down consumed elsewhere) — record rather than silently drop a real tap.
    if (down != null && (event.position - down).distance > _kTapSlopPx) return;
    _pending = event.position;
    _pendingAtMs = _now();
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback(_resolvePending);
  }

  void _resolvePending(Duration _) {
    _scheduled = false;
    final position = _pending;
    final atMs = _pendingAtMs;
    _pending = null;
    final runtime = _runtime;
    if (position == null || runtime == null) return;
    try {
      // Start below our own KeyedSubtree wrapper so its GlobalKey never leaks
      // into a tapped widget's identity.
      final wrapper = _childKey.currentContext as Element?;
      Element? root;
      wrapper?.visitChildElements((child) => root ??= child);
      if (root == null) return;
      final target = resolveTapTarget(root!, position);
      if (target == null) return;
      // Normalized tap position (heatmaps): fraction 0..1 of the screen.
      // Resolved post-frame — no cost to the synchronous pointer-up hot path.
      final coords = _normalizedPoint(position);
      final props = target.toProps();
      if (coords != null) {
        props['x'] = coords.$1;
        props['y'] = coords.$2;
      }
      runtime.sink.emit(
        type: EventType.auto,
        name: 'tap',
        props: props,
        screen: runtime.tracker.current,
        tsMs: atMs,
      );
      runtime.frustration?.onTap(
        targetId: target.identity,
        interactive: target.interactive,
        x: coords?.$1,
        y: coords?.$2,
      );
    } on Object {
      // Analytics must never break the frame (Rule 0.3).
    }
  }

  /// Normalizes a global [position] to a (x, y) fraction of the root's extent,
  /// rounded to 4 decimals and clamped to [0, 1]. Returns null if the root has
  /// no measurable size. Pure arithmetic — no allocation beyond the record.
  (double, double)? _normalizedPoint(Offset position) {
    final ro = context.findRenderObject();
    if (ro is! RenderBox || !ro.hasSize) return null;
    final size = ro.size;
    if (size.width <= 0 || size.height <= 0) return null;
    final local = ro.globalToLocal(position);
    return (
      _round4((local.dx / size.width).clamp(0.0, 1.0)),
      _round4((local.dy / size.height).clamp(0.0, 1.0)),
    );
  }

  static double _round4(double v) => (v * 10000).roundToDouble() / 10000;

  // Scroll hot path (docs/05): O(1) fraction update, no layout read (metrics are
  // already computed), no allocation. Returns false so notifications keep
  // bubbling to the app's own listeners.
  bool _onScroll(ScrollNotification notification) {
    try {
      final tracker = _runtime?.scrollDepth;
      if (tracker == null) return false;
      final metrics = notification.metrics;
      final extent = metrics.maxScrollExtent;
      if (extent > 0) tracker.record(metrics.pixels / extent);
    } on Object {
      // Never break scrolling over analytics (Rule 0.3).
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: KeyedSubtree(key: _childKey, child: widget.child),
      ),
    );
  }
}

/// Resolves the stable identity of the widget tapped at [position].
///
/// It descends the render hit-path from [root] to the tapped leaf (cheap: one
/// geometrically-hit child per level), then walks up at most [budget]
/// ancestors preferring, in order, a user-keyed interactive widget, the
/// nearest interactive widget, and the nearest user-keyed widget — so a keyed
/// button/gesture wins over the framework internals between it and the leaf.
/// Pure and side-effect-free, so it is directly unit-testable.
TapTarget? resolveTapTarget(
  Element root,
  Offset position, {
  int budget = kTapWalkBudget,
}) {
  final leaf = _descendToLeaf(root, position);
  if (leaf == null) return null;
  final walk = _IdentityWalk()..inspect(leaf);
  var steps = 0;
  leaf.visitAncestorElements((element) {
    walk.inspect(element);
    steps++;
    return steps < budget;
  });
  final identity =
      walk.keyedInteractive ?? walk.interactive ?? walk.keyed ?? leaf;
  return TapTarget(
    widgetType: identity.widget.runtimeType.toString(),
    interactive: walk.interactive != null,
    keyString: _userKey(identity.widget.key)?.toString(),
    semanticsLabel: walk.semanticsLabel,
  );
}

/// Follows the geometrically-hit child down to the tapped leaf element.
Element? _descendToLeaf(Element root, Offset position) {
  var node = root;
  for (var depth = 0; depth < _kMaxDescent; depth++) {
    Element? hit;
    Element? passthrough;
    node.visitChildElements((child) {
      final ro = child.renderObject;
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) {
        // A wrapper whose own render object isn't a positioned box (inherited
        // widgets, slivers, views): descend through it so we don't stop short.
        passthrough ??= child;
        return;
      }
      final local = ro.globalToLocal(position);
      if (local.dx >= 0 &&
          local.dy >= 0 &&
          local.dx < ro.size.width &&
          local.dy < ro.size.height) {
        hit = child; // last (topmost in paint order) hit wins
      }
    });
    final next = hit ?? passthrough;
    if (next == null) return node;
    node = next;
  }
  return node;
}

/// Accumulates identity candidates as the walk climbs ancestors.
class _IdentityWalk {
  Element? keyedInteractive;
  Element? interactive;
  Element? keyed;
  String? semanticsLabel;

  void inspect(Element element) {
    final widget = element.widget;
    final isInteractive = _isInteractive(widget);
    final userKey = _userKey(widget.key);
    if (isInteractive) {
      interactive ??= element;
      if (userKey != null) keyedInteractive ??= element;
    }
    if (userKey != null) keyed ??= element;
    // Explicit developer Semantics only — never a widget's text-derived label.
    if (widget is Semantics) {
      final label = widget.properties.label;
      if (label != null && label.isNotEmpty) semanticsLabel ??= label;
    }
  }
}

/// A developer-assigned key (not a framework [GlobalKey]) usable as identity.
Key? _userKey(Key? key) => (key == null || key is GlobalKey) ? null : key;

const Set<String> _interactiveTypeMarkers = {
  'Button',
  'InkWell',
  'InkResponse',
  'Switch',
  'Checkbox',
  'Radio',
  'Slider',
  'TextField',
  'TextFormField',
  'EditableText',
  'Chip',
  'Tab',
  'Dismissible',
  'PopupMenu',
};

bool _isInteractive(Widget widget) {
  if (widget is GestureDetector) {
    return widget.onTap != null ||
        widget.onTapUp != null ||
        widget.onTapDown != null;
  }
  final name = widget.runtimeType.toString();
  return _interactiveTypeMarkers.any(name.contains);
}
