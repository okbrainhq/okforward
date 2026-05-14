import AppKit
import OkForwardCore

if CommandLine.arguments.contains("--smoke-test") {
    exit(ProxySmokeTest.run() ? EXIT_SUCCESS : EXIT_FAILURE)
}

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
