import CGtk
import Dispatch
import Foundation

@_silgen_name("_dispatch_get_main_queue_handle_4CF")
private func dispatchMainQueueHandle() -> Int32

@_silgen_name("_dispatch_main_queue_callback_4CF")
private func dispatchMainQueueCallback(_ message: UnsafeMutableRawPointer?)

/// Drains Dispatch's main queue from the GLib main loop.
///
/// GTK owns the process's main loop, so nothing would otherwise run blocks sent
/// to `DispatchQueue.main` or continuations hopping back onto the main actor.
/// libdispatch exposes the main queue's wake-up descriptor for exactly this
/// kind of foreign run loop; watching it keeps Swift concurrency and GTK on
/// one thread.
enum DispatchMainQueueBridge {
  private nonisolated(unsafe) static var isInstalled = false

  static func install() {
    guard !isInstalled else { return }
    isInstalled = true

    let handle = dispatchMainQueueHandle()
    let watcher: @convention(c) (gint, GIOCondition, gpointer?) -> gboolean = { _, _, _ in
      dispatchMainQueueCallback(nil)
      return 1
    }
    g_unix_fd_add(handle, G_IO_IN, watcher, nil)
  }
}
