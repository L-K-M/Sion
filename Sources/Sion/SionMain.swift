import AppKit
import SionKit

@main
@MainActor
private enum SionApplication {
  static func main() {
    let application = NSApplication.shared
    let delegate = SionApplicationDelegate()

    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()
  }
}
