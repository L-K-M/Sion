import CGtk
import CSionGtkShim
import Foundation

/// Holds a Swift closure for the lifetime of a GObject signal handler.
///
/// GLib owns the box: it is retained when the handler connects and released by
/// the closure-notify when the instance is finalized or the handler removed.
/// Every trampoline recovers the box from the `user_data` argument and hops
/// onto the main actor, which is the GTK main thread.
final class SignalBox<Handler> {
  let handler: Handler

  init(_ handler: Handler) {
    self.handler = handler
  }

  static func retained(_ handler: Handler) -> gpointer {
    Unmanaged.passRetained(SignalBox(handler)).toOpaque()
  }

  static func from(_ data: gpointer?) -> SignalBox<Handler> {
    Unmanaged<SignalBox<Handler>>.fromOpaque(data!).takeUnretainedValue()
  }
}

/// Releases a `SignalBox` of any handler type once GLib drops the closure.
let signalBoxRelease: GClosureNotify = { data, _ in
  guard let data else { return }
  Unmanaged<AnyObject>.fromOpaque(data).release()
}

@MainActor
enum Signals {
  /// Connects a handler whose C signature is `(instance, user_data)`.
  @discardableResult
  static func connect(
    _ instance: gpointer,
    _ signal: String,
    after: Bool = false,
    handler: @escaping @MainActor () -> Void
  ) -> gulong {
    typealias Handler = @MainActor () -> Void
    let trampoline: @convention(c) (gpointer?, gpointer?) -> Void = { _, data in
      let box = SignalBox<Handler>.from(data)
      MainActor.assumeIsolated { box.handler() }
    }
    return sion_signal_connect(
      instance, signal, unsafeBitCast(trampoline, to: GCallback.self),
      SignalBox<Handler>.retained(handler), signalBoxRelease, after ? 1 : 0)
  }

  /// Connects a handler whose C signature is `(instance, pointer, user_data)`,
  /// which covers `GVariant *`, widget, texture, and `GValue *` arguments.
  @discardableResult
  static func connect(
    _ instance: gpointer,
    _ signal: String,
    after: Bool = false,
    handler: @escaping @MainActor (gpointer?) -> Void
  ) -> gulong {
    typealias Handler = @MainActor (gpointer?) -> Void
    let trampoline: @convention(c) (gpointer?, gpointer?, gpointer?) -> Void = {
      _, argument, data in
      let box = SignalBox<Handler>.from(data)
      MainActor.assumeIsolated { box.handler(argument) }
    }
    return sion_signal_connect(
      instance, signal, unsafeBitCast(trampoline, to: GCallback.self),
      SignalBox<Handler>.retained(handler), signalBoxRelease, after ? 1 : 0)
  }

  /// `(instance, pointer, pointer, user_data)`, as in `notify` or drag signals
  /// carrying two object arguments.
  @discardableResult
  static func connect(
    _ instance: gpointer,
    _ signal: String,
    after: Bool = false,
    handler: @escaping @MainActor (gpointer?, gpointer?) -> Void
  ) -> gulong {
    typealias Handler = @MainActor (gpointer?, gpointer?) -> Void
    let trampoline: @convention(c) (gpointer?, gpointer?, gpointer?, gpointer?) -> Void = {
      _, first, second, data in
      let box = SignalBox<Handler>.from(data)
      MainActor.assumeIsolated { box.handler(first, second) }
    }
    return sion_signal_connect(
      instance, signal, unsafeBitCast(trampoline, to: GCallback.self),
      SignalBox<Handler>.retained(handler), signalBoxRelease, after ? 1 : 0)
  }

  /// `(instance, double, double, user_data)`: gesture drag begin/update/end
  /// and motion controllers.
  @discardableResult
  static func connect(
    _ instance: gpointer,
    _ signal: String,
    after: Bool = false,
    handler: @escaping @MainActor (Double, Double) -> Void
  ) -> gulong {
    typealias Handler = @MainActor (Double, Double) -> Void
    let trampoline: @convention(c) (gpointer?, Double, Double, gpointer?) -> Void = {
      _, x, y, data in
      let box = SignalBox<Handler>.from(data)
      MainActor.assumeIsolated { box.handler(x, y) }
    }
    return sion_signal_connect(
      instance, signal, unsafeBitCast(trampoline, to: GCallback.self),
      SignalBox<Handler>.retained(handler), signalBoxRelease, after ? 1 : 0)
  }

  /// `(instance, int, double, double, user_data)`: `GtkGestureClick`
  /// pressed and released.
  @discardableResult
  static func connect(
    _ instance: gpointer,
    _ signal: String,
    after: Bool = false,
    handler: @escaping @MainActor (Int32, Double, Double) -> Void
  ) -> gulong {
    typealias Handler = @MainActor (Int32, Double, Double) -> Void
    let trampoline: @convention(c) (gpointer?, gint, Double, Double, gpointer?) -> Void = {
      _, count, x, y, data in
      let box = SignalBox<Handler>.from(data)
      MainActor.assumeIsolated { box.handler(count, x, y) }
    }
    return sion_signal_connect(
      instance, signal, unsafeBitCast(trampoline, to: GCallback.self),
      SignalBox<Handler>.retained(handler), signalBoxRelease, after ? 1 : 0)
  }

  /// `(instance, int, int, user_data)`: `GtkDrawingArea::resize`.
  @discardableResult
  static func connectResize(
    _ instance: gpointer,
    handler: @escaping @MainActor (Int32, Int32) -> Void
  ) -> gulong {
    typealias Handler = @MainActor (Int32, Int32) -> Void
    let trampoline: @convention(c) (gpointer?, gint, gint, gpointer?) -> Void = {
      _, width, height, data in
      let box = SignalBox<Handler>.from(data)
      MainActor.assumeIsolated { box.handler(width, height) }
    }
    return sion_signal_connect(
      instance, "resize", unsafeBitCast(trampoline, to: GCallback.self),
      SignalBox<Handler>.retained(handler), signalBoxRelease, 0)
  }

  /// `(instance, double, double, user_data) -> gboolean`: scroll controllers.
  @discardableResult
  static func connectScroll(
    _ instance: gpointer,
    _ signal: String,
    handler: @escaping @MainActor (Double, Double) -> Bool
  ) -> gulong {
    typealias Handler = @MainActor (Double, Double) -> Bool
    let trampoline: @convention(c) (gpointer?, Double, Double, gpointer?) -> gboolean = {
      _, dx, dy, data in
      let box = SignalBox<Handler>.from(data)
      return MainActor.assumeIsolated { box.handler(dx, dy) ? 1 : 0 }
    }
    return sion_signal_connect(
      instance, signal, unsafeBitCast(trampoline, to: GCallback.self),
      SignalBox<Handler>.retained(handler), signalBoxRelease, 0)
  }

  /// `(instance, keyval, keycode, state, user_data) -> gboolean`: key
  /// controllers. Return true to stop propagation.
  @discardableResult
  static func connectKey(
    _ instance: gpointer,
    _ signal: String,
    handler: @escaping @MainActor (UInt32, UInt32, GdkModifierType) -> Bool
  ) -> gulong {
    typealias Handler = @MainActor (UInt32, UInt32, GdkModifierType) -> Bool
    let trampoline:
      @convention(c) (gpointer?, guint, guint, GdkModifierType, gpointer?) -> gboolean = {
        _, keyval, keycode, state, data in
        let box = SignalBox<Handler>.from(data)
        return MainActor.assumeIsolated { box.handler(keyval, keycode, state) ? 1 : 0 }
      }
    return sion_signal_connect(
      instance, signal, unsafeBitCast(trampoline, to: GCallback.self),
      SignalBox<Handler>.retained(handler), signalBoxRelease, 0)
  }

  /// `(instance, user_data) -> gboolean`: close requests and similar vetoes.
  /// Return true to stop the default handler.
  @discardableResult
  static func connectVeto(
    _ instance: gpointer,
    _ signal: String,
    handler: @escaping @MainActor () -> Bool
  ) -> gulong {
    typealias Handler = @MainActor () -> Bool
    let trampoline: @convention(c) (gpointer?, gpointer?) -> gboolean = { _, data in
      let box = SignalBox<Handler>.from(data)
      return MainActor.assumeIsolated { box.handler() ? 1 : 0 }
    }
    return sion_signal_connect(
      instance, signal, unsafeBitCast(trampoline, to: GCallback.self),
      SignalBox<Handler>.retained(handler), signalBoxRelease, 0)
  }

  /// `(instance, GValue *, double, double, user_data) -> gboolean`: the
  /// `GtkDropTarget` drop signal.
  @discardableResult
  static func connectDrop(
    _ instance: gpointer,
    handler: @escaping @MainActor (UnsafeMutablePointer<GValue>?, Double, Double) -> Bool
  ) -> gulong {
    typealias Handler = @MainActor (UnsafeMutablePointer<GValue>?, Double, Double) -> Bool
    let trampoline:
      @convention(c) (gpointer?, UnsafeMutablePointer<GValue>?, Double, Double, gpointer?)
        -> gboolean = { _, value, x, y, data in
          let box = SignalBox<Handler>.from(data)
          return MainActor.assumeIsolated { box.handler(value, x, y) ? 1 : 0 }
        }
    return sion_signal_connect(
      instance, "drop", unsafeBitCast(trampoline, to: GCallback.self),
      SignalBox<Handler>.retained(handler), signalBoxRelease, 0)
  }

  static func disconnect(_ instance: gpointer, _ handlerID: gulong) {
    g_signal_handler_disconnect(instance, handlerID)
  }
}

// MARK: - Main loop

@MainActor
enum MainLoop {
  /// Runs `body` once the current main-loop iteration has finished.
  static func performOnNextIteration(_ body: @escaping @MainActor () -> Void) {
    typealias Handler = @MainActor () -> Void
    let trampoline: @convention(c) (gpointer?) -> gboolean = { data in
      let box = SignalBox<Handler>.from(data)
      MainActor.assumeIsolated { box.handler() }
      return sion_source_remove()
    }
    g_idle_add_full(
      G_PRIORITY_DEFAULT_IDLE, trampoline, SignalBox<Handler>.retained(body),
      { data in
        guard let data else { return }
        Unmanaged<AnyObject>.fromOpaque(data).release()
      })
  }

  /// Runs `body` after `seconds` on the main loop.
  @discardableResult
  static func perform(after seconds: Double, _ body: @escaping @MainActor () -> Void) -> guint {
    typealias Handler = @MainActor () -> Void
    let trampoline: @convention(c) (gpointer?) -> gboolean = { data in
      let box = SignalBox<Handler>.from(data)
      MainActor.assumeIsolated { box.handler() }
      return sion_source_remove()
    }
    return g_timeout_add_full(
      G_PRIORITY_DEFAULT, guint(max(0, seconds) * 1_000), trampoline,
      SignalBox<Handler>.retained(body),
      { data in
        guard let data else { return }
        Unmanaged<AnyObject>.fromOpaque(data).release()
      })
  }

  static func cancel(_ source: guint) {
    guard source != 0 else { return }
    g_source_remove(source)
  }

  /// Drains one iteration of pending events without blocking; tests use it to
  /// let idle handlers and layout run.
  static func drainPendingEvents() {
    while g_main_context_pending(nil) != 0 {
      g_main_context_iteration(nil, 0)
    }
  }
}

// MARK: - GIO async results

@MainActor
enum GAsync {
  typealias Handler = @MainActor (UnsafeMutablePointer<GObject>?, OpaquePointer?) -> Void

  /// Packages a one-shot Swift closure as a `GAsyncReadyCallback` plus its
  /// user data. The box is released once the callback has run.
  static func callback(_ handler: @escaping Handler) -> (GAsyncReadyCallback, gpointer) {
    let trampoline: GAsyncReadyCallback = { source, result, data in
      guard let data else { return }
      let box = Unmanaged<SignalBox<Handler>>.fromOpaque(data).takeRetainedValue()
      MainActor.assumeIsolated { box.handler(source, result) }
    }
    return (trampoline, SignalBox<Handler>.retained(handler))
  }
}
