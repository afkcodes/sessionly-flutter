/// Sessionly SDK for Flutter — wire protocol v1 plus the capture engine.
///
/// The single source of truth for the protocol is `packages/core` (Rule 2.1);
/// this library is the Dart mirror, proven conformant by contract tests against
/// the shared golden fixtures. On top of the protocol models (P1-T6) it exposes
/// the `Sessionly` facade and the off-main-thread engine — ring buffer,
/// background isolate, disk queue, and uploader (P1-T7).
library;

export 'src/capture/capture_sink.dart';
export 'src/capture/current_screen.dart';
export 'src/capture/errors.dart' show SessionlyErrorHandlers;
export 'src/capture/frame_timing.dart' show FrameTimingCapture;
export 'src/capture/frustration.dart' show FrustrationDetectors;
export 'src/capture/http_tracker.dart'
    show SessionlyHttpClient, SessionlyHttpTracker;
export 'src/capture/input_capture.dart' show InputFocusCapture;
export 'src/capture/lifecycle.dart' show LifecycleCapture;
export 'src/capture/main_thread_watchdog.dart'
    show MainThreadWatchdog, WatchdogDetector;
export 'src/capture/navigator_observer.dart'
    show ScreenLoadTimer, SessionlyNavigatorObserver;
export 'src/capture/runtime.dart' show CaptureRuntime;
export 'src/capture/scroll_depth.dart' show ScrollDepthTracker;
export 'src/capture/tap_capture.dart'
    show SessionlyRoot, TapTarget, kTapWalkBudget, resolveTapTarget;
export 'src/config.dart';
export 'src/engine/capture_gate.dart';
export 'src/engine/capture_record.dart';
export 'src/engine/engine.dart';
export 'src/engine/engine_host.dart';
export 'src/engine/ring_buffer.dart';
export 'src/engine/telemetry.dart';
export 'src/engine/worker/backoff.dart';
export 'src/engine/worker/disk_queue.dart';
export 'src/engine/worker/identity.dart';
export 'src/engine/worker/kv_store.dart';
export 'src/engine/worker/queue_store.dart';
export 'src/engine/worker/remote_config.dart';
export 'src/engine/worker/scrubber.dart';
export 'src/engine/worker/sessionizer.dart';
export 'src/engine/worker/uploader.dart';
export 'src/platform/default_platform.dart';
export 'src/platform/sessionly_platform.dart';
export 'src/protocol/capture_props.dart'
    show httpMethods, httpStatusMax, scrollDepthBuckets, validateCaptureProps;
export 'src/protocol/ctx.dart';
export 'src/protocol/envelope.dart';
export 'src/protocol/errors.dart';
export 'src/protocol/event.dart';
export 'src/protocol/formats.dart';
export 'src/protocol/limits.dart';
export 'src/protocol/revenue_props.dart';
export 'src/protocol/uuid_v7.dart';
export 'src/protocol/vocabulary.dart';
export 'src/sessionly.dart';
