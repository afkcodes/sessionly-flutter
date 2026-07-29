/// Text-input focus / abandon capture (docs/05). A single [FocusManager]
/// listener watches primary-focus changes: gaining focus on a text field that
/// carries an explicit `Semantics` label emits `auto/input_focus`; losing that
/// focus without the field being re-focused emits `auto/input_abandon` with the
/// dwell time and a `had_input` BOOLEAN.
///
/// PII (Rule 7.1 / lesson #9): the field is identified ONLY by an explicit
/// developer `Semantics.label` — fields without one are ignored. `had_input`
/// is derived from `controller.text.isNotEmpty` at abandon time as a bare
/// boolean — the entered text and even its length never leave the device.
library;

import 'package:flutter/widgets.dart';
import 'package:sessionly_flutter/src/capture/capture_sink.dart';
import 'package:sessionly_flutter/src/capture/current_screen.dart';
import 'package:sessionly_flutter/src/protocol/vocabulary.dart';

/// Max ancestor elements the identity walk examines. A Material `TextField`
/// nests the editable `Focus` (whose node becomes primary focus) roughly two
/// dozen elements below the field's own outer boundary, and the developer's
/// identifying `Semantics` wrapper sits just above that boundary — so the walk
/// must clear the field's internal structure (lesson #9: identity lives ~40
/// elements up in Material). Bounded so a stray focus never walks the whole
/// tree; this fires only on focus change, never per frame.
const int _kFieldWalkBudget = 60;

/// Watches [FocusManager] primary focus and emits input focus/abandon events.
class InputFocusCapture {
  /// Wires capture to [sink]/[tracker]. [focusManager]/[nowMs] are test seams.
  InputFocusCapture({
    required CaptureSink sink,
    required CurrentScreenTracker tracker,
    FocusManager? focusManager,
    int Function()? nowMs,
  }) : _sink = sink,
       _tracker = tracker,
       _focusManager = focusManager ?? WidgetsBinding.instance.focusManager,
       _nowMs = nowMs ?? _systemNowMs;

  static int _systemNowMs() => DateTime.now().millisecondsSinceEpoch;

  final CaptureSink _sink;
  final CurrentScreenTracker _tracker;
  final FocusManager _focusManager;
  final int Function() _nowMs;

  // The currently-tracked focused field, or null when focus is elsewhere.
  FocusNode? _node;
  String? _field;
  String? _screen;
  int _focusedAtMs = 0;
  TextEditingController? _controller;

  /// Starts listening. The change handler de-dupes on the identical node.
  void install() => _focusManager.addListener(_onFocusChange);

  /// Emits any pending abandon and stops listening.
  void dispose() {
    _flushAbandon();
    _focusManager.removeListener(_onFocusChange);
  }

  void _onFocusChange() {
    try {
      final primary = _focusManager.primaryFocus;
      if (identical(primary, _node)) return;
      // Focus moved off the tracked field → it was abandoned.
      _flushAbandon();
      _clear();
      if (primary == null) return;
      final identity = _identityOf(primary);
      if (identity == null) return; // not a labelled text field — ignore.
      _node = primary;
      _field = identity.field;
      _controller = identity.controller;
      _screen = _tracker.current;
      _focusedAtMs = _nowMs();
      _sink.emit(
        type: EventType.auto,
        name: 'input_focus',
        props: {
          'field': identity.field,
          if (_screen != null) 'screen': _screen,
        },
        screen: _screen,
      );
    } on Object {
      // Never break focus handling over analytics (Rule 0.3).
    }
  }

  void _flushAbandon() {
    final field = _field;
    if (field == null) return;
    final dwell = _nowMs() - _focusedAtMs;
    _sink.emit(
      type: EventType.auto,
      name: 'input_abandon',
      props: {
        'field': field,
        if (_screen != null) 'screen': _screen,
        'dwell_ms': dwell < 0 ? 0 : dwell,
        'had_input': _hadInput(),
      },
      screen: _screen,
    );
  }

  // Reads whether ANY text is present — a bare boolean, never the content.
  bool _hadInput() {
    try {
      return _controller?.text.isNotEmpty ?? false;
    } on Object {
      return false; // controller may be disposed with the field.
    }
  }

  void _clear() {
    _node = null;
    _field = null;
    _screen = null;
    _controller = null;
    _focusedAtMs = 0;
  }

  /// Resolves a focused node to a labelled text field: an explicit
  /// `Semantics.label` (the identity) and the `EditableText` controller, or
  /// null when the node is not a text field or carries no explicit label.
  ({String field, TextEditingController? controller})? _identityOf(
    FocusNode node,
  ) {
    final context = node.context;
    if (context == null) return null;
    final controller = _controllerNear(context);
    if (controller == null) return null; // not a text input.
    final label = _semanticsLabelNear(context);
    if (label == null) return null; // no explicit identity — PII rule.
    return (field: label, controller: controller);
  }

  // Finds the EditableText controller at/above [context] — a TextField's focus
  // node lives in an internal Focus INSIDE its EditableText, so the controller
  // is an ancestor of the focus context (bounded walk, no allocation).
  TextEditingController? _controllerNear(BuildContext context) {
    if (context.widget case final EditableText e) return e.controller;
    TextEditingController? found;
    var steps = 0;
    context.visitAncestorElements((element) {
      if (element.widget case final EditableText e) {
        found = e.controller;
        return false;
      }
      return ++steps < _kFieldWalkBudget;
    });
    return found;
  }

  // Finds the nearest explicit Semantics label at/above [context] (bounded).
  String? _semanticsLabelNear(BuildContext context) {
    String? label;
    var steps = 0;
    context.visitAncestorElements((element) {
      if (element.widget case final Semantics s) {
        final l = s.properties.label;
        if (l != null && l.isNotEmpty) {
          label = l;
          return false;
        }
      }
      return ++steps < _kFieldWalkBudget;
    });
    return label;
  }
}
