import Common
import SwiftUI

@MainActor
struct MenuBarLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var viewModel: TrayMenuModel
    @ObservedObject private var appearance = MenuBarAppearanceSettings.shared

    var body: some View {
        if #available(macOS 14, *), let cgImage = renderedMenuBarImage {
            Image(cgImage, scale: 2, label: Text(accessibilityText))
        } else {
            menuBarContent
        }
    }

    @available(macOS 14, *)
    private var renderedMenuBarImage: CGImage? {
        let renderer = ImageRenderer(content: menuBarContent)
        renderer.scale = 2
        return renderer.cgImage
    }

    private var menuBarContent: some View {
        HStack(spacing: 4) {
            presentationContent
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(renderColor)
        .opacity(viewModel.isEnabled ? 1 : 0.55)
        .accessibilityLabel(accessibilityText)
    }

    private var renderColor: Color {
        colorScheme == .dark ? .white : .black
    }

    @ViewBuilder
    private var presentationContent: some View {
        switch appearance.presentation {
            case .iconOnly:
                Image(systemName: "rectangle.3.group")
                    .symbolRenderingMode(.monochrome)
                    .imageScale(.medium)
            case .focusedWorkspace:
                if let focused = viewModel.workspaces.first(where: \.isFocused) {
                    Text(focused.name).lineLimit(1)
                } else {
                    Text("—")
                }
            case .activeWorkspaces:
                if viewModel.activeWorkspaceNames.isEmpty {
                    Text("—")
                } else {
                    Text(viewModel.activeWorkspaceNames.joined(separator: " · "))
                        .lineLimit(1)
                }
            case .i3Grouped:
                let visible = viewModel.workspaces.filter(\.isVisible)
                let hiddenOccupied = viewModel.workspaces.filter { !$0.isEffectivelyEmpty && !$0.isVisible }
                if visible.isEmpty, hiddenOccupied.isEmpty {
                    Text("—")
                } else {
                    ForEach(visible, id: \.name) { workspace in
                        workspaceChip(workspace)
                    }
                    if !visible.isEmpty, !hiddenOccupied.isEmpty {
                        Text("|")
                            .foregroundStyle(renderColor.opacity(0.35))
                    }
                    ForEach(hiddenOccupied, id: \.name) { workspace in
                        workspaceChip(workspace, isDimmed: true)
                    }
                }
            case .i3Ordered:
                let shown = viewModel.workspaces.filter { !$0.isEffectivelyEmpty || $0.isVisible }
                if shown.isEmpty {
                    Text("—")
                } else {
                    ForEach(shown, id: \.name) { workspace in
                        workspaceChip(workspace, isDimmed: !workspace.isVisible)
                    }
                }
        }
    }

    private func workspaceChip(_ workspace: WorkspaceViewModel, isDimmed: Bool = false) -> some View {
        HStack(spacing: 2) {
            Text(workspace.name)
                .lineLimit(1)
            if workspace.hasFullscreenWindows {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 7, weight: .semibold))
            }
        }
        .font(.system(size: 12, weight: workspace.isFocused ? .bold : .semibold, design: .rounded))
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background {
            if workspace.isFocused {
                Capsule().fill(renderColor.opacity(0.16))
            }
        }
        .opacity(isDimmed ? 0.5 : 1)
    }

    private var accessibilityText: String {
        switch (viewModel.axPermissionStatus, viewModel.isEnabled) {
            case (.granted, true): viewModel.trayText.isEmpty ? aeroSpaceAppName : viewModel.trayText
            case (.granted, false): "\(aeroSpaceAppName), paused"
            case (_, _): "\(aeroSpaceAppName), accessibility permission required"
        }
    }
}
