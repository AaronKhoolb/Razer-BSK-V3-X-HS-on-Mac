import AppKit
import SwiftUI

/// Thin wiring layer: instantiate the controllers, hand them their
/// dependencies, connect intents. Business logic lives in DeviceController,
/// UI logic in Tray/PanelController, this class has none of its own.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var deviceController: DeviceController!
    private var panelController:  PanelController!
    private var trayController:   TrayController!

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()

        deviceController = DeviceController()
        panelController  = PanelController(status: deviceController.status, controller: deviceController)
        trayController = TrayController(
            status: deviceController.status,
            actions: .init(
                openPanel: { [weak self] anchor in self?.panelController.toggle(anchor: anchor) }
            )
        )
        deviceController.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.toggle(anchor: nil)
        return false
    }

    // MARK: - Main menu (Cmd-Q, copy/paste in text fields, etc.)

    private func installMainMenu() {
        let root = NSMenu()

        let appItem = NSMenuItem(); root.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: String(localized: "About BSK V3 X HS"),
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Hide"),
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: String(localized: "Hide Others"),
                                    action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Quit BSK V3 X HS"),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); root.addItem(editItem)
        let edit = NSMenu(title: String(localized: "Edit"))
        edit.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: String(localized: "Select All"), action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        NSApp.mainMenu = root
    }
}
