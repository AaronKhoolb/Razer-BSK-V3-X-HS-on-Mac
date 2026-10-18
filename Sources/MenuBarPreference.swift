import Foundation

enum MenuBarPreference {
    static let visibleKey = "bskv3xhs.menuBarVisible"
    static let batteryKey = "bskv3xhs.menuBarBatteryPercentage"

    static var isVisible: Bool {
        UserDefaults.standard.object(forKey: visibleKey) as? Bool ?? true
    }

    static var showsBatteryPercentage: Bool {
        UserDefaults.standard.object(forKey: batteryKey) as? Bool ?? true
    }
}
