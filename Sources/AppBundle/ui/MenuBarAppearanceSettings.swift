import Combine
import Foundation

enum MenuBarPresentation: String, CaseIterable, Identifiable, Equatable, Hashable {
    case iconOnly
    case focusedWorkspace
    case allDisplays

    var id: String { rawValue }

    var title: String {
        switch self {
            case .iconOnly: "Icon Only"
            case .focusedWorkspace: "Current Workspace"
            case .allDisplays: "All Displays"
        }
    }

    var explanation: String {
        switch self {
            case .iconOnly: "Shows only the AeroSpaceSmooth icon for the most compact menu bar."
            case .focusedWorkspace: "Shows the same icon followed by the focused workspace."
            case .allDisplays: "Shows the same icon followed by the active workspace on each display."
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
        presentation = defaults.string(forKey: Keys.presentation)
            .flatMap(MenuBarPresentation.init(rawValue:))
            ?? .focusedWorkspace
    }

    func setPresentation(_ presentation: MenuBarPresentation) {
        self.presentation = presentation
        defaults.set(presentation.rawValue, forKey: Keys.presentation)
    }

    private enum Keys {
        static let presentation = "menuBarPresentation"
    }
}
