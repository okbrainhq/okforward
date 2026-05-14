import AppKit

final class RulesWindowController: NSWindowController {
    private let manager: ProxyManager
    private let content: RulesViewController

    init(manager: ProxyManager) {
        self.manager = manager
        self.content = RulesViewController(manager: manager)

        let window = NSWindow(contentViewController: content)
        window.title = "OkForward"
        window.setContentSize(NSSize(width: 760, height: 420))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class RulesViewController: NSViewController {
    private let manager: ProxyManager

    private let hostPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let listenPortField = NSTextField()
    private let targetHostField = NSTextField()
    private let targetPortField = NSTextField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let toggleButton = NSButton(title: "Disable", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    private var interfaces: [NetworkInterface] = []
    private var observerID: UUID?

    init(manager: ProxyManager) {
        self.manager = manager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 420))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        buildLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reloadInterfaces()
        configureTable()
        observerID = manager.addObserver { [weak self] in
            self?.reloadTable()
        }
        reloadTable()
    }

    deinit {
        if let observerID {
            manager.removeObserver(id: observerID)
        }
    }

    private func buildLayout() {
        let hostLabel = NSTextField(labelWithString: "Bind Host")
        let listenLabel = NSTextField(labelWithString: "Forward Port")
        let targetHostLabel = NSTextField(labelWithString: "Target Host")
        let targetPortLabel = NSTextField(labelWithString: "Target Port")

        listenPortField.placeholderString = "2222"
        targetHostField.stringValue = "127.0.0.1"
        targetPortField.placeholderString = "22"

        [hostLabel, listenLabel, targetHostLabel, targetPortLabel].forEach {
            $0.font = .systemFont(ofSize: 12, weight: .semibold)
            $0.textColor = .secondaryLabelColor
        }

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshHosts))
        let addButton = NSButton(title: "Add", target: self, action: #selector(addRule))
        let restartButton = NSButton(title: "Restart", target: self, action: #selector(restartAll))

        deleteButton.target = self
        deleteButton.action = #selector(deleteSelectedRule)
        toggleButton.target = self
        toggleButton.action = #selector(toggleSelectedRule)

        let formGrid = NSGridView(views: [
            [hostLabel, listenLabel, targetHostLabel, targetPortLabel, NSView()],
            [hostPopup, listenPortField, targetHostField, targetPortField, addButton]
        ])
        formGrid.rowSpacing = 6
        formGrid.columnSpacing = 10
        formGrid.translatesAutoresizingMaskIntoConstraints = false
        formGrid.column(at: 0).width = 230
        formGrid.column(at: 1).width = 110
        formGrid.column(at: 2).width = 170
        formGrid.column(at: 3).width = 110
        formGrid.column(at: 4).width = 80

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView

        let actionStack = NSStackView(views: [toggleButton, deleteButton, restartButton, refreshButton])
        actionStack.orientation = .horizontal
        actionStack.spacing = 8
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(formGrid)
        view.addSubview(scrollView)
        view.addSubview(actionStack)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            formGrid.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            formGrid.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -18),
            formGrid.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            scrollView.topAnchor.constraint(equalTo: formGrid.bottomAnchor, constant: 18),
            scrollView.bottomAnchor.constraint(equalTo: actionStack.topAnchor, constant: -12),

            actionStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            actionStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -18),

            statusLabel.leadingAnchor.constraint(equalTo: actionStack.trailingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            statusLabel.centerYAnchor.constraint(equalTo: actionStack.centerYAnchor)
        ])
    }

    private func configureTable() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.target = self
        tableView.action = #selector(selectionDidChange)

        addColumn(id: "enabled", title: "On", width: 56)
        addColumn(id: "bind", title: "Bind Host", width: 180)
        addColumn(id: "listen", title: "Forward", width: 86)
        addColumn(id: "target", title: "Target Host", width: 170)
        addColumn(id: "targetPort", title: "Target", width: 86)
        addColumn(id: "state", title: "State", width: 160)
    }

    private func addColumn(id: String, title: String, width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        tableView.addTableColumn(column)
    }

    private func reloadInterfaces(selected: String? = nil) {
        interfaces = InterfaceProvider.availableHosts()
        let selection = selected ?? hostPopup.selectedItem?.representedObject as? String

        hostPopup.removeAllItems()
        for item in interfaces {
            hostPopup.addItem(withTitle: item.label)
            hostPopup.lastItem?.representedObject = item.address
        }

        if let selection, let index = interfaces.firstIndex(where: { $0.address == selection }) {
            hostPopup.selectItem(at: index)
        } else {
            hostPopup.selectItem(at: 0)
        }
    }

    private func reloadTable() {
        tableView.reloadData()
        selectionDidChange()
        updateStatus()
    }

    private func updateStatus() {
        let ready = manager.rules.filter { manager.state(for: $0) == .ready }.count
        let total = manager.rules.filter(\.enabled).count
        if manager.rules.isEmpty {
            statusLabel.stringValue = "No forwarding rules"
        } else {
            statusLabel.stringValue = "\(ready) of \(total) enabled rules ready"
        }
    }

    @objc private func refreshHosts() {
        reloadInterfaces()
    }

    @objc private func restartAll() {
        manager.restartAll()
    }

    @objc private func addRule() {
        guard
            let bindHost = hostPopup.selectedItem?.representedObject as? String,
            let listenPort = PortParser.parse(listenPortField.stringValue),
            let targetPort = PortParser.parse(targetPortField.stringValue)
        else {
            NSSound.beep()
            return
        }

        let targetHost = targetHostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetHost.isEmpty else {
            NSSound.beep()
            return
        }

        let rule = ProxyRule(
            bindHost: bindHost,
            listenPort: listenPort,
            targetHost: targetHost,
            targetPort: targetPort
        )

        manager.add(rule)
        listenPortField.stringValue = ""
        targetPortField.stringValue = ""
    }

    @objc private func deleteSelectedRule() {
        let row = tableView.selectedRow
        guard row >= 0, row < manager.rules.count else {
            NSSound.beep()
            return
        }

        manager.removeRule(id: manager.rules[row].id)
    }

    @objc private func toggleSelectedRule() {
        let row = tableView.selectedRow
        guard row >= 0, row < manager.rules.count else {
            NSSound.beep()
            return
        }

        let rule = manager.rules[row]
        manager.setEnabled(!rule.enabled, for: rule.id)
    }

    @objc private func selectionDidChange() {
        let row = tableView.selectedRow
        let hasSelection = row >= 0 && row < manager.rules.count
        deleteButton.isEnabled = hasSelection
        toggleButton.isEnabled = hasSelection

        if hasSelection {
            toggleButton.title = manager.rules[row].enabled ? "Disable" : "Enable"
        } else {
            toggleButton.title = "Disable"
        }
    }
}

extension RulesViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        manager.rules.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < manager.rules.count, let tableColumn else {
            return nil
        }

        let rule = manager.rules[row]
        let identifier = tableColumn.identifier.rawValue

        if identifier == "enabled" {
            let cell = NSTableCellView()
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleCheckbox(_:)))
            checkbox.state = rule.enabled ? .on : .off
            checkbox.tag = row
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(checkbox)
            NSLayoutConstraint.activate([
                checkbox.centerXAnchor.constraint(equalTo: cell.centerXAnchor),
                checkbox.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }

        let text: String
        switch identifier {
        case "bind":
            text = rule.bindHost
        case "listen":
            text = "\(rule.listenPort)"
        case "target":
            text = rule.targetHost
        case "targetPort":
            text = "\(rule.targetPort)"
        case "state":
            text = manager.state(for: rule).label
        default:
            text = ""
        }

        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: text)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    @objc private func toggleCheckbox(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0, row < manager.rules.count else {
            return
        }

        let rule = manager.rules[row]
        manager.setEnabled(sender.state == .on, for: rule.id)
    }
}
