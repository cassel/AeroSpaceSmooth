import Combine
import Foundation

enum MenuBarPresentation: String, CaseIterable, Identifiable, Equatable, Hashable {
    case iconOnly
    case focusedWorkspace
    case activeWorkspaces = "allDisplays"
    case i3Grouped
    case i3Ordered

    var id: String { rawValue }

    var title: String {
        switch self {
            case .iconOnly: "Icon Only"
            case .focusedWorkspace: "Current Workspace"
            case .activeWorkspaces: "Active Workspaces"
            case .i3Grouped: "i3 Grouped"
            case .i3Ordered: "i3 Ordered"
        }
    }

    var explanation: String {
        switch self {
            case .iconOnly: "Shows only the AeroSpaceSmooth icon for the most compact menu bar."
            case .focusedWorkspace: "Shows the same icon followed by the focused workspace."
            case .activeWorkspaces: "Lists the active workspace from each display beside the icon."
            case .i3Grouped: "Groups visible workspaces first, followed by occupied workspaces that are currently hidden."
            case .i3Ordered: "Shows visible and occupied workspaces together in their configured order."
        }
    }
}

@MainActor
final class MenuBarAppearanceSettings: ObservableObject {
    static let shared = MenuBarAppearanceSettings()

    @Published private(set) var presentation: MenuBarPresentation
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.string(forKey: Keys.presentation).flatMap(MenuBarPresentation.init(rawValue:)) {
            presentation = stored
        } else {
            presentation = switch defaults.string(forKey: Keys.legacyDisplayStyle) {
                case "i3": .i3Grouped
                case "i3Ordered": .i3Ordered
                default: .focusedWorkspace
            }
        }
    }

    func setPresentation(_ presentation: MenuBarPresentation) {
        self.presentation = presentation
        defaults.set(presentation.rawValue, forKey: Keys.presentation)
    }

    private enum Keys {
        static let presentation = "menuBarPresentation"
        static let legacyDisplayStyle = "displayStyle"
    }
}
