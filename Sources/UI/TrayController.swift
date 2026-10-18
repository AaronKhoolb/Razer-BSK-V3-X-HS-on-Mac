import AppKit
import Combine

/// Owns the NSStatusItem — subscribes to Status changes and re-renders.
/// Delegates high-level intents (open panel, refresh) to callers so it stays
/// UI-only.
///
/// Interaction model: any click on the tray (left or right) opens the context
/// menu. The panel is reachable via the menu's "Open panel" item — never as
/// the direct click action. Matches Tailscale / Slack / most modern macOS
/// menu-bar apps.
@MainActor
final class TrayController: NSObject {
    private let status: Status
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()

    struct Actions {
        let openPanel: (NSStatusBarButton?) -> Void
    }
    private let actions: Actions

    init(status: Status, actions: Actions) {
        self.status = status
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let btn = statusItem.button {
            btn.imagePosition = .imageLeading
        }
        // Attaching the menu makes both left- and right-click open it —
        // AppKit handles the click routing for us, no target/action needed
        // on the button. The delegate rebuilds the menu right before each
        // opening so profile list / battery / idle state are always fresh.
        menu.delegate = self
        statusItem.menu = menu

        subscribeToStatus()
        render()
    }

    // MARK: - Rendering (icon + battery pill in the menu bar itself)

    private func subscribeToStatus() {
        Publishers.MergeMany(
            status.$present.map { _ in () }.eraseToAnyPublisher(),
            status.$connection.map { _ in () }.eraseToAnyPublisher(),
            status.$awake.map { _ in () }.eraseToAnyPublisher(),
            status.$battery.map { _ in () }.eraseToAnyPublisher(),
            status.$error.map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] in self?.render() }
        .store(in: &cancellables)
    }

    private func render() {
        statusItem.isVisible = MenuBarPreference.isVisible
        guard let btn = statusItem.button else { return }
        btn.image = TrayIcon.image(for: iconState())
        btn.attributedTitle = title()
        btn.toolTip = tooltip()
    }

    private func iconState() -> TrayIconState {
        switch status.connection {
        case .none: return .unplugged
        case .bluetooth, .dongle: return status.awake ? .awake : .asleep
        }
    }

    private func title() -> NSAttributedString {
        guard MenuBarPreference.showsBatteryPercentage,
              status.connection != .none, let pct = status.battery else {
            return NSAttributedString(string: "")
        }
        return NSAttributedString(string: " \(pct)%", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .regular),
            .foregroundColor: status.awake ? NSColor.labelColor : NSColor.secondaryLabelColor,
            .kern: -0.2,
        ])
    }

    private func tooltip() -> String {
        let name = "BSK V3 X HS"
        switch status.connection {
        case .none:
            return "\(name) · " + String(localized: "Disconnected")
        case .bluetooth:
            let battery = status.battery.map { " · \($0)%" } ?? ""
            let awake = status.awake
                ? String(localized: "Bluetooth")
                : String(localized: "Bluetooth · Idle")
            return "\(name) · " + awake + battery
        case .dongle:
            let battery = status.battery.map { " · \($0)%" } ?? ""
            let awake = status.awake
                ? String(localized: "Dongle")
                : String(localized: "Dongle · Idle")
            return "\(name) · " + awake + battery
        }
    }

    // MARK: - Menu

    /// Rebuild from scratch each open — the menu is small and state changes
    /// (profile switch, awake/idle, battery) need to be reflected without
    /// bookkeeping. Called by NSMenuDelegate.menuNeedsUpdate right before
    /// the menu becomes visible.
    private func rebuildMenu() {
        menu.removeAllItems()

        // Header — Tailscale-style two-line status row rendered by our own
        // NSView (see HeaderMenuRowView). Custom view so isEnabled=false's
        // AppKit dimming doesn't fade the device name to grey; the text
        // lands in its declared labelColor/secondaryLabelColor.
        let header = NSMenuItem()
        header.view = HeaderMenuRowView(nameText: "BSK V3 X HS",
                                        subText: headerSubline())
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Profile row — Tailscale-style rich item rendered by our own
        // NSView subclass (see ProfileMenuRowView) so the avatar can be
        // sized as an actual avatar rather than clamped to NSMenuItem's
        // implicit ~row-height cap. The custom view handles its hover
        // highlight and forwards clicks to the attached submenu.
        let store = SettingsStore.shared
        if !store.file.profiles.isEmpty {
            let activeName = store.file.profiles.first(where: { $0.id == store.file.activeID })?.name
                ?? store.file.profiles.first?.name
                ?? String(localized: "Profile")

            let profileItem = NSMenuItem()
            profileItem.view = ProfileMenuRowView(
                labelText: String(localized: "Profile"),
                nameText: activeName
            )

            let sub = NSMenu()
            for p in store.file.profiles {
                let item = NSMenuItem(title: p.name,
                                      action: #selector(fireSwitchProfile(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = p.id.uuidString
                if p.id == store.file.activeID { item.state = .on }
                sub.addItem(item)
            }
            profileItem.submenu = sub
            menu.addItem(profileItem)
        }

        // Open Panel — the only way to reach the control-center window now
        // that left-click no longer opens it directly.
        let open = NSMenuItem(title: String(localized: "Open Panel"),
                              action: #selector(fireOpen),
                              keyEquivalent: "")
        open.target = self
        open.image = openPanelIcon()
        menu.addItem(open)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: String(localized: "Quit"),
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    /// The second line of the header. Reflects current transport, awake/idle
    /// state, and last-known battery — mirrors the tooltip but formatted for
    /// the taller menu row.
    private func headerSubline() -> String {
        switch status.connection {
        case .none:
            return String(localized: "Disconnected")
        case .bluetooth, .dongle:
            let transport = status.connection == .dongle
                ? String(localized: "Dongle")
                : String(localized: "Bluetooth")
            var parts = [transport]
            if !status.awake { parts.append(String(localized: "Idle")) }
            if let pct = status.battery { parts.append("\(pct)%") }
            return parts.joined(separator: " · ")
        }
    }

    /// SF Symbol for the "Open Panel" row. Uses `macwindow` — a Mac window
    /// outline — because the action literally opens a window; the earlier
    /// `slider.horizontal.3` glyph read as a settings-preset thing rather
    /// than a "open the app UI" affordance. Sized to fit a normal single-
    /// line menu item so it stays visually subordinate to the Profile row.
    private func openPanelIcon() -> NSImage? {
        let base = NSImage(systemSymbolName: "macwindow",
                           accessibilityDescription: nil)
        let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let scaled = base?.withSymbolConfiguration(cfg)
        scaled?.isTemplate = true
        return scaled
    }

    // MARK: - Menu actions

    @objc private func fireOpen() { actions.openPanel(statusItem.button) }

    @objc private func fireSwitchProfile(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String,
              let id = UUID(uuidString: s) else { return }
        SettingsStore.shared.setActive(id)
    }
}

extension TrayController: NSMenuDelegate {
    /// Called by AppKit on the main thread right before the menu opens.
    /// Rebuild synchronously so the freshly-built items are what the user
    /// sees — dispatching to a Task would race the menu opening.
    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            self.rebuildMenu()
        }
    }
}
