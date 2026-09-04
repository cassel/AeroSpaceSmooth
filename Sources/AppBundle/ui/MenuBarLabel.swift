import Common
import SwiftUI

@MainActor
struct MenuBarLabel: View {
    @EnvironmentObject var viewModel: TrayMenuModel
    @ObservedObject private var appearance = MenuBarAppearanceSettings.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "rectangle.3.group")
                .symbolRenderingMode(.monochrome)
                .imageScale(.medium)
            if let detailText {
                Text(detailText)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .opacity(viewModel.isEnabled ? 1 : 0.55)
        .accessibilityLabel(accessibilityText)
    }

    private var detailText: String? {
        switch appearance.presentation {
            case .iconOnly:
                nil
            case .focusedWorkspace:
                viewModel.workspaces.first(where: \.isFocused)?.name
            case .allDisplays:
                viewModel.activeWorkspaceNames.joined(separator: " · ")
        }
    }

    private var accessibilityText: String {
        switch (viewModel.axPermissionStatus, viewModel.isEnabled) {
            case (.granted, true): viewModel.trayText.isEmpty ? aeroSpaceAppName : viewModel.trayText
            case (.granted, false): "\(aeroSpaceAppName), paused"
            case (_, _): "\(aeroSpaceAppName), accessibility permission required"
        }
    }
}
