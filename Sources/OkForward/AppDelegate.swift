import AppKit
import OkForwardCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let manager = ProxyManager()
    private var statusItem: NSStatusItem?
    private var windowController: RulesWindowController?
    private var observerID: UUID?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        observerID = manager.addObserver { [weak self] in
            self?.refreshMenu()
        }
        manager.startAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager.stopAll()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.title = ""
        item.button?.image = StatusIcon.image()
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "OkForward"
        statusItem = item
        refreshMenu()
    }

    private func refreshMenu() {
        let menu = NSMenu()

        let status = NSMenuItem(title: menuTitle(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if manager.rules.isEmpty {
            let empty = NSMenuItem(title: "No rules configured", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for rule in manager.rules {
                let title = "\(rule.enabled ? "On" : "Off")  \(rule.displayName)  \(manager.state(for: rule).label)"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Rules...", action: #selector(openRulesWindow), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Restart Proxies", action: #selector(restartProxies), keyEquivalent: "r"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit OkForward", action: #selector(quit), keyEquivalent: "q"))

        menu.items.forEach { $0.target = self }
        statusItem?.menu = menu
    }

    private func menuTitle() -> String {
        let enabled = manager.rules.filter(\.enabled)
        let ready = enabled.filter { manager.state(for: $0) == .ready }.count

        if enabled.isEmpty {
            return "OkForward"
        }

        return "OkForward: \(ready)/\(enabled.count) ready"
    }

    @objc private func openRulesWindow() {
        if windowController == nil {
            windowController = RulesWindowController(manager: manager)
        }
        windowController?.show()
    }

    @objc private func restartProxies() {
        manager.restartAll()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
