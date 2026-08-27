import AppKit
import SionKit

let application = NSApplication.shared
let delegate = SionApplicationDelegate()

application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
