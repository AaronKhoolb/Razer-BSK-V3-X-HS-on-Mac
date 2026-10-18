import SwiftUI
import AppKit
import UniformTypeIdentifiers

// The five section panes that populate MainView's detail column.
// One AppSection → one pane. Split out of MainView.swift so the root file
// stays focused on layout / sidebar / profile picking.

struct SensitivityPane: View {
    @Binding var dpi: DPIConfig
    var body: some View {
        Card(title: "Sensitivity Stages") {
            DPIStagesList(dpi: $dpi)
            HStack(spacing: 8) {
                Button(action: addStage) {
                    Label("Add Stage", systemImage: "plus")
                        .font(.system(size: 12))
                }
                .disabled(dpi.stages.count >= 5)
                Spacer()
                Text("\(dpi.stages.count) of 5")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.top, 4)
            Divider().opacity(0.4)
            Toggle(isOn: Binding(
                get: { dpi.xyIndependent },
                set: { newVal in
                    dpi.xyIndependent = newVal
                    if !newVal {
                        // Collapsing back to synced X=Y: mirror X onto Y
                        // so the mouse doesn't retain a hidden Y drift
                        // the UI can't show.
                        for i in dpi.stages.indices { dpi.stages[i].y = dpi.stages[i].x }
                    }
                }
            )) {
                Text("Enable X-Y Sensitivity")
                    .font(.system(size: 13))
            }
            .toggleStyle(.switch)
        }
    }
    private func addStage() {
        guard dpi.stages.count < 5 else { return }
        let last = dpi.stages.last.map { max($0.x, $0.y) } ?? 1600
        dpi.stages.append(DPIStageValue(x: last, y: last))
    }
}

struct ReportingPane: View {
    @Binding var hz: Int
    var body: some View {
        Card {
            // Native segmented picker — on macOS 26 this already
            // renders with Liquid Glass (glass-pill background, glass
            // thumb sliding to the selected option). Let it span the
            // Card's full content width so the glass is legible.
            Picker("", selection: $hz) {
                Text("125 Hz").tag(125)
                Text("500 Hz").tag(500)
                Text("1000 Hz").tag(1000)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Higher rates reduce click and movement latency, at the cost of slightly higher battery use.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Text("Bluetooth is capped at ~125 Hz on macOS. Connect via the 2.4 GHz dongle for 500 or 1000 Hz.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }
}

struct ScrollPane: View {
    @Binding var draft: AppSettings
    var body: some View {
        AccessibilityGate()
        // Master on/off — System Settings-style row: label + switch,
        // description underneath. No hero, no "Works over Bluetooth"
        // pill (that state's already surfaced by the sidebar).
        Card {
            Toggle(isOn: $draft.scroll.enabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Enhanced scrolling")
                        .font(.system(size: 13, weight: .medium))
                    Text("Reverses and smooths the wheel. Trackpad untouched.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
        }
        Group {
            Card(title: "Direction") {
                Toggle("Reverse vertical scroll", isOn: $draft.scroll.reverseVertical)
                    .toggleStyle(.switch)
                Toggle("Reverse horizontal scroll", isOn: $draft.scroll.reverseHorizontal)
                    .toggleStyle(.switch)
                Text("Pairs with macOS's Natural scrolling — wheel goes Windows-style, trackpad stays natural.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 2)
            }
            Card(title: "Speed") {
                HStack(spacing: 16) {
                    Text(String(format: "%.2f×", draft.scroll.speed))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .frame(width: 68, alignment: .leading)
                    Slider(value: $draft.scroll.speed, in: 0.25...3.0,
                           onEditingChanged: SliderCommitCoordinator.editingChanged)
                }
                HStack {
                    Text("0.25×").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Text("3.00×").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Text("Pixels per wheel notch. 1× ≈ macOS default.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 2)
            }
            Card(title: "Smoothing") {
                Toggle(isOn: $draft.scroll.smoothingEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Interpolate between ticks").font(.system(size: 13, weight: .medium))
                        Text("Turns each notch into a short glide. Off keeps raw steps.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.toggleStyle(.switch)
                HStack(spacing: 16) {
                    Text(String(format: "%d%%", Int((draft.scroll.smoothness * 100).rounded())))
                        .font(.system(size: 14, weight: .semibold))
                        .monospacedDigit()
                        .frame(width: 68, alignment: .leading)
                    Slider(value: $draft.scroll.smoothness, in: 0...1,
                           onEditingChanged: SliderCommitCoordinator.editingChanged)
                        .disabled(!draft.scroll.smoothingEnabled)
                }
                HStack {
                    Text("Snappy (0%)").font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Glide (100%)").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Text("Higher = longer glide, up to ~400 ms. Snappier feels closer to a raw wheel.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 2)
            }
        }
        // Uniform dim when the master is off — beats per-Toggle .disabled
        // (some things dim, others don't) and gives the pane a single
        // "feature paused" affordance.
        .disabled(!draft.scroll.enabled)
        .opacity(draft.scroll.enabled ? 1.0 : 0.5)
    }
}

struct PowerPane: View {
    @EnvironmentObject var status: Status
    @Binding var draft: AppSettings
    /// Below this the bar turns red AND surfaces a warning glyph — never
    /// rely on color alone (WCAG). Aligns with macOS's own "low battery"
    /// threshold in Battery preferences.
    private let batteryWarnPct = 20
    var body: some View {
        Card(title: "Battery level") {
            // Native ProgressView — matches System Settings' battery
            // presentation. Tint flips red under the warn threshold so
            // the bar itself carries the "low" signal; no separate
            // icon overlay needed.
            HStack(spacing: 20) {
                ProgressView(value: Double(status.battery ?? 0), total: 100)
                    .progressViewStyle(.linear)
                    .tint(fill)
                    .frame(maxWidth: 260)
                Text(status.battery.map { "\($0)%" } ?? "—")
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(status.awake ? .primary : .secondary)
                Spacer()
            }
            Text(status.connection == .bluetooth
                 ? "1× AA. macOS refreshes the reading every ~30 s."
                 : "1× AA. Smoothed over 30 min to hide AA voltage recovery.")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 4)
        }
        Card(title: "Idle sleep") {
            // Over BT the idle-timer write reaches the mouse through the
            // Razer vendor protocol which isn't exposed on that transport
            // — surface the reason inline so users don't wonder why the
            // slider isn't landing.
            if status.connection == .bluetooth {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Requires the HyperSpeed dongle.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.bottom, 4)
            }
            // What the mouse currently reports — pulled fresh from hardware
            // on connect (see DeviceController.syncFromHardware).
            HStack(spacing: 6) {
                Text("Mouse is currently set to")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text(status.idleActual.map { "\($0) min" } ?? "—")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
            }.padding(.bottom, 6)
            HStack(spacing: 16) {
                Text("\(draft.idleMinutes) min")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 68, alignment: .leading)
                Slider(
                    value: Binding(get: { Double(draft.idleMinutes) },
                                   set: { draft.idleMinutes = Int($0.rounded()) }),
                    in: 1...15,
                    onEditingChanged: SliderCommitCoordinator.editingChanged
                )
                .disabled(status.connection != .dongle)
            }
            .opacity(status.connection == .dongle ? 1.0 : 0.6)
            HStack {
                Text("1 min").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("15 min").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            // Read-back verification. If the mouse silently ignored our idle
            // write, tell the user rather than let them keep guessing.
            if let actual = status.idleActual, actual != draft.idleMinutes {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.system(size: 11))
                    Text("Mouse reports \(actual) min — firmware may ignore custom idle time.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.top, 6)
            }
            Text("How long without input before the radio sleeps. Shorter = better battery, slower wake.")
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 4)
        }
        // Low-battery behaviour card. Matches Synapse's "battery low"
        // section — one shared threshold, two toggles for what triggers
        // (notification, LED auto-dim). Kept in Power pane so all battery-
        // related knobs sit under one section header. Threshold spans the
        // full 1–100 range so users who want a notification on every 1%
        // drop can park the slider at 100 and let the per-drop cadence in
        // checkLowBatteryEvent do the rest.
        Card(title: "Low battery") {
            HStack(spacing: 16) {
                Text("\(draft.lowBattery.threshold)%")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .frame(width: 68, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { Double(draft.lowBattery.threshold) },
                        set: { draft.lowBattery.threshold = Int($0.rounded()) }
                    ),
                    in: 1...100,
                    onEditingChanged: SliderCommitCoordinator.editingChanged
                )
            }
            HStack {
                Text("1%").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Text("100%").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Divider().opacity(0.4).padding(.vertical, 2)
            Toggle(isOn: $draft.lowBattery.alertEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show HUD at threshold").font(.system(size: 13, weight: .medium))
                    Text("Pops a battery HUD in the top-right when the reading crosses the threshold, then again on every further drop.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.toggleStyle(.switch)
            Toggle(isOn: $draft.lowBattery.dimLEDEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dim LED at threshold").font(.system(size: 13, weight: .medium))
                    Text("Cut LED brightness in half to extend AA life. Doesn't touch flash.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.toggleStyle(.switch)
        }
    }
    private var fill: Color {
        guard let p = status.battery else { return .secondary.opacity(0.3) }
        return p < batteryWarnPct ? .red : .green
    }
}

struct DevicePane: View {
    @EnvironmentObject var status: Status
    @EnvironmentObject var controller: DeviceController
    @ObservedObject private var loginItem = LoginItem.shared
    @Binding var draft: AppSettings
    /// Persistent toggle for `Log.debug(...)` output. Bound to the
    /// same UserDefaults key `Log` reads on every debug call, so
    /// flipping this takes effect immediately — no relaunch. Env var
    /// `BSKV3XHS_DEBUG` (if set) overrides this at process start;
    /// see `Log.debugOverriddenByEnv`.
    @AppStorage(Log.debugPrefKey) private var debugLoggingEnabled = false
    @AppStorage(MenuBarPreference.visibleKey) private var menuBarVisible = true
    @AppStorage(MenuBarPreference.batteryKey) private var menuBarBatteryPercentage = true

    private var connectionLabel: String {
        switch status.connection {
        case .none:      return "Offline"
        case .bluetooth: return "Bluetooth"
        case .dongle:    return "HyperSpeed dongle (2.4 GHz)"
        }
    }
    /// Firmware / serial row value. Over BT the vendor protocol isn't
    /// reachable so we show an explicit "Dongle only" label instead of a
    /// bare em-dash — it makes the pane feel intentional rather than broken.
    private func vendorReadValue(_ raw: String?) -> String {
        if let s = raw { return s }
        return status.connection == .bluetooth ? "Dongle only" : "—"
    }

    var body: some View {
        Card(title: "Hardware") {
            InfoRow("Product", "Razer Basilisk V3 X HyperSpeed")
            InfoRow("USB VID / PID", "0x1532 / 0x00B9", mono: true)
            InfoRow("Firmware",
                    vendorReadValue(status.firmware.map { "v\($0)" }),
                    mono: status.firmware != nil)
            InfoRow("Serial",
                    vendorReadValue(status.serial),
                    mono: status.serial != nil)
            InfoRow("Connection", connectionLabel)
        }
        Card(title: "Preferences") {
            Toggle("Show in menu bar", isOn: $menuBarVisible)
                .font(.system(size: 13, weight: .medium))
                .toggleStyle(.switch)
            Text("When hidden, open BSK V3 X HS again from Finder or Spotlight to access this panel.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Show battery percentage", isOn: $menuBarBatteryPercentage)
                .font(.system(size: 13, weight: .medium))
                .toggleStyle(.switch)
                .disabled(!menuBarVisible)
            Divider().opacity(0.4).padding(.vertical, 4)
            Toggle(isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at login").font(.system(size: 13, weight: .medium))
                    Text("Start automatically at login.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            if let err = loginItem.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.system(size: 11))
                    Text(err).font(.system(size: 11)).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }.padding(.top, 4)
            }
            Divider().opacity(0.4).padding(.vertical, 4)
            // Language picker. Each label stays in its own language so
            // users can find their choice even when the current UI is in
            // a language they don't read.
            HStack(spacing: 10) {
                Text("Language").font(.system(size: 13, weight: .medium))
                Spacer()
                Picker("", selection: Binding(
                    get: { LanguagePreference.current },
                    set: { newValue in
                        guard newValue != LanguagePreference.current else { return }
                        LanguagePreference.set(newValue)
                        promptLanguageRestart()
                    }
                )) {
                    ForEach(LanguagePreference.Choice.allCases) { c in
                        Text(LocalizedStringKey(c.label)).tag(c)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }
            Text("Applies after the app restarts.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        Card(title: "Utilities") {
            // Debug logging toggle. Sits above the utility buttons so
            // users investigating an issue see it before hitting "Show
            // log" — the flow is "enable debug → reproduce → show log
            // → send to me". Grey when the env var override is in
            // effect (flipping wouldn't do anything then).
            Toggle(isOn: $debugLoggingEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Debug logging")
                        .font(.system(size: 13, weight: .medium))
                    Text("Records every button press, scroll tick, and Bluetooth state change to the log. Only enable while investigating a specific issue — the log grows fast.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .disabled(Log.debugOverriddenByEnv)
            if Log.debugOverriddenByEnv {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Text("Overridden by the BSKV3XHS_DEBUG environment variable this session.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Divider().opacity(0.4).padding(.vertical, 2)

            // Two-column grid so every utility button ends up the same
            // size, aligned on the same baselines, regardless of label
            // length. Previous nested HStack layout had the buttons wrap
            // asymmetrically at narrower widths and let a short label
            // ("Show log") sit next to a wide one ("Copy device info")
            // with a jagged right edge.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                Button {
                    Task { await controller.refresh() }
                } label: {
                    Label("Refresh from mouse", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(status.connection == .none)
                .help({
                    switch status.connection {
                    case .dongle:    return LocalizedStringKey("Re-read onboard settings")
                    case .bluetooth: return LocalizedStringKey("Re-read battery")
                    case .none:      return LocalizedStringKey("Mouse not connected")
                    }
                }())

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([SettingsStore.shared.fileURL])
                } label: {
                    Label("Show settings.json", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button { exportActiveProfile() } label: {
                    Label("Export profile", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button { importProfile() } label: {
                    Label("Import profile", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    let info = [
                        "Product: Razer Basilisk V3 X HyperSpeed",
                        "VID/PID: 0x1532 / 0x00B9",
                        "Firmware: \(status.firmware.map { "v\($0)" } ?? "—")",
                        "Serial: \(status.serial ?? "—")",
                        "Connection: \(connectionLabel)",
                        "Battery: \(status.battery.map { "\($0)%" } ?? "—")",
                    ].joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(info, forType: .string)
                } label: {
                    Label("Copy device info", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([Log.fileURL])
                } label: {
                    Label("Show log", systemImage: "text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    Log.clear()
                } label: {
                    Label("Clear log", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .help("Wipe /tmp/bskv3xhs.log so the next repro starts fresh.")
            }
            Divider().padding(.vertical, 4)
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Import / Export

    /// Ask whether to relaunch now so the new language kicks in. Users
    /// who dismiss the prompt still see the change on the next natural
    /// launch (LanguagePreference.applyEarly picks it up on `main()`).
    private func promptLanguageRestart() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Restart to change language")
        alert.informativeText = String(localized: "The new language takes effect after the app relaunches.")
        alert.addButton(withTitle: String(localized: "Relaunch now"))
        alert.addButton(withTitle: String(localized: "Later"))
        alert.alertStyle = .informational
        if alert.runModal() == .alertFirstButtonReturn {
            LanguagePreference.relaunch()
        }
    }

    /// Open NSSavePanel to write the active profile as JSON. Default file
    /// name uses the profile name so users can recognize their export
    /// later without opening the file.
    private func exportActiveProfile() {
        let store = SettingsStore.shared
        let active = store.file.profiles.first(where: { $0.id == store.file.activeID })
        let panel = NSSavePanel()
        panel.title = String(localized: "Export profile")
        panel.nameFieldStringValue = ((active?.name ?? "profile") + ".bskprofile.json")
        panel.allowedContentTypes = [.json]
        // Sheet from the current key window if one is up; NSSavePanel
        // otherwise appears at screen-centre which reads as detached.
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try store.exportActive()
            try data.write(to: url, options: [.atomic])
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "Export failed")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    /// Open NSOpenPanel, read the picked file, decode + add as a new
    /// profile via SettingsStore.importProfile. Errors surface as an
    /// NSAlert — user-driven action, so a modal is appropriate.
    private func importProfile() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import profile")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            try SettingsStore.shared.importProfile(from: data)
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "Import failed")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}

struct ButtonsPane: View {
    @Binding var draft: AppSettings
    @ObservedObject private var buttonMap = ButtonMap.shared
    @State private var selected: MouseButton? = nil
    @State private var editingHotspots: Bool = false
    // Working copy of the diagram positions while editing — commits back to
    // `draft` only when the user clicks Done, so we don't fire auto-apply /
    // hit the mouse for every drag frame.
    @State private var editHotspots: [String: NormalizedPoint] = [:]
    @State private var editCallouts: [String: NormalizedPoint] = [:]

    private var mappingActions: [MouseButton: ButtonAction] {
        var out: [MouseButton: ButtonAction] = [:]
        for b in MouseButton.allCases {
            out[b] = draft.buttons.action(for: b)
        }
        return out
    }

    /// Snap all left-flank labels to a common x, and all right-flank labels
    /// to a common x — averaging whatever the user has already dragged. Y
    /// positions are preserved so vertical order stays.
    private func alignLabelColumns() {
        // Operates on the in-flight editing copy so the change lands only if
        // the user then clicks Done.
        let leftSide: Set<MouseButton> = [.leftClick, .scrollClick, .mouseButton5, .mouseButton4]
        let rightSide: Set<MouseButton> = [.rightClick, .scrollUp, .scrollDown, .dpiCycle]

        func averageX(_ buttons: Set<MouseButton>, fallback: Double) -> Double {
            let xs = buttons.compactMap { editCallouts[$0.rawValue]?.x }
            guard !xs.isEmpty else { return fallback }
            return xs.reduce(0, +) / Double(xs.count)
        }

        let leftX = averageX(leftSide, fallback: -0.24)
        let rightX = averageX(rightSide, fallback: 1.24)

        for btn in MouseButton.allCases {
            if let existing = editCallouts[btn.rawValue] {
                let newX = leftSide.contains(btn) ? leftX : rightX
                editCallouts[btn.rawValue] = NormalizedPoint(x: newX, y: existing.y)
            }
        }
    }

    var body: some View {
        AccessibilityGate()

        // Header controls sit in their own Card so the diagram's
        // extreme-top callout (rightClick, normalized y = -0.05) can't
        // spill into the header row visually — two distinct Cards give
        // a hard visual break that a single VStack inside one Card
        // could not.
        Card {
            HStack {
                Text(LocalizedStringKey(editingHotspots ? "Drag to reposition callouts" : "Buttons"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if editingHotspots {
                    Button("Align labels") { alignLabelColumns() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .font(.system(size: 11, weight: .medium))
                    Button("Reset all") {
                        editHotspots.removeAll()
                        editCallouts.removeAll()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                }
                Button {
                    if editingHotspots {
                        // Done: commit working copy to draft (this is the
                        // only place we fire auto-apply for the diagram).
                        draft.hotspotOverrides = editHotspots
                        draft.calloutOverrides = editCallouts
                        editingHotspots = false
                    } else {
                        // Enter edit: seed working copy from current draft.
                        editHotspots = draft.hotspotOverrides
                        editCallouts = draft.calloutOverrides
                        editingHotspots = true
                    }
                } label: {
                    Label(editingHotspots ? "Done" : "Edit hotspots",
                          systemImage: editingHotspots ? "checkmark.circle.fill" : "pencil.tip.crop.circle")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(editingHotspots ? Color.accentColor : .secondary)
                .help(editingHotspots
                      ? LocalizedStringKey("Click Done to save positions.")
                      : LocalizedStringKey("Fine-tune where callouts point at the mouse image."))
            }
        }

        Card {
            MouseDiagram(
                selection: $selected,
                actions: mappingActions,
                hotspots: editingHotspots ? editHotspots : draft.hotspotOverrides,
                callouts: editingHotspots ? editCallouts : draft.calloutOverrides,
                editing: editingHotspots,
                onMoveHotspot: { btn, p in editHotspots[btn.rawValue] = p },
                onMoveCallout: { btn, p in editCallouts[btn.rawValue] = p }
            )
            // Cap the diagram so it doesn't balloon vertically inside a
            // wider window. MouseDiagram internally reserves callout
            // headroom (see `calloutHeadroom` there), so this frame is
            // the outer bound; the actual image lands smaller than the
            // max so extreme-top callouts stay inside these bounds.
            .frame(minHeight: 360, maxHeight: 420)
        }
        .sheet(item: $selected) { btn in
            RemapPicker(button: btn, draft: $draft) { selected = nil }
        }
    }
}

/// Shared Accessibility-permission prompt. Both `ScrollPane` and
/// `ButtonsPane` rely on the same CGEventTap, so both need to surface the
/// missing-permission state — otherwise a user who only cares about
/// scroll reversal sees the toggle turn on but nothing happens, with no
/// explanation of why.
private struct AccessibilityGate: View {
    @ObservedObject private var buttonMap = ButtonMap.shared
    var body: some View {
        if !buttonMap.accessibilityTrusted {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundStyle(.orange)
                            .font(.system(size: 15))
                        Text("Accessibility permission required")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text("Button remap and scroll enhancements need permission to inject events on your behalf.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Button {
                        buttonMap.requestTrust()
                    } label: {
                        Text("Grant Accessibility")
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 12).padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    Text("After granting, click Recheck below.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Button("Recheck") {
                        buttonMap.refreshTrust()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .font(.system(size: 12))
                }
            }
        }
    }
}
