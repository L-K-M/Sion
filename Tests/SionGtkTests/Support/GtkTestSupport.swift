import CGtk
import XCTest

@testable import SionGtk

/// Initialises GTK once for widget tests and skips them when no display is
/// reachable, so `swift test` passes on a headless machine while CI runs the
/// same tests under `xvfb-run`.
enum GtkTestSupport {
  nonisolated(unsafe) private static var initialized: Bool?

  /// Throws `XCTSkip` when GTK cannot open a display.
  static func requireDisplay() throws {
    if initialized == nil {
      initialized = gtk_init_check() != 0
      if initialized == true {
        adw_init()
        MainActor.assumeIsolated { DispatchMainQueueBridge.install() }
      }
    }
    guard initialized == true else {
      throw XCTSkip("GTK could not open a display; run under xvfb-run.")
    }
  }

  /// Lets pending layout, draw, and idle sources run.
  static func drainMainLoop() {
    while g_main_context_pending(nil) != 0 {
      g_main_context_iteration(nil, 0)
    }
  }
}
