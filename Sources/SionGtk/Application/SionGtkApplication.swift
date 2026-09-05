import CGtk
import CSionGtkShim
import Foundation

/// Bootstraps the GTK application: one process, one `AdwApplication`.
public enum SionGtkApplication {
  public static func run(arguments: [String]) -> Int32 {
    let application = adw_application_new("ch.lkmc.Sion", G_APPLICATION_HANDLES_OPEN)
    defer { g_object_unref(application) }
    guard let application else { return 1 }

    MainActor.assumeIsolated {
      Signals.connect(application.gobject, "startup") {
        DispatchMainQueueBridge.install()
      }
      Signals.connect(application.gobject, "activate") {
        let window = adw_application_window_new(application.cast())
        gtk_window_set_title(window?.cast(), "Sion")
        gtk_window_set_default_size(window?.cast(), 1_100, 760)
        let label = gtk_label_new("Sion for Linux")
        adw_application_window_set_content(window?.cast(), label)
        gtk_window_present(window?.cast())
      }
    }

    var cArguments = arguments.map { strdup($0) }
    defer {
      for argument in cArguments {
        free(argument)
      }
    }
    return g_application_run(application.cast(), Int32(cArguments.count), &cArguments)
  }
}
