import SwiftUI

let smoothLayoutSettingsWindowId = "aerospace-smooth-layout-settings"

private struct SmoothMonitorSummary: Identifiable, Hashable {
    let screenId: Int
    let name: String
    let width: CGFloat
    let height: CGFloat

    var id: String { "\(screenId):\(name)" }
    var isHorizontal: Bool { width >= height }
    var orientationTitle: String { isHorizontal ? "Horizontal" : "Vertical" }
}

@MainActor
public func smoothLayoutSettingsWindow() -> some Scene {
    SwiftUI.Window("Layouts por monitor", id: smoothLayoutSettingsWindowId) {
        SmoothLayoutSettingsView()
            .frame(minWidth: 860, minHeight: 620)
    }
    .defaultSize(width: 960, height: 760)
}

@MainActor
struct OpenSmoothLayoutSettingsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: smoothLayoutSettingsWindowId)
        } label: {
            Label("Settings…", systemImage: "gearshape")
        }
        .keyboardShortcut("L", modifiers: [.command, .shift])
    }
}

@MainActor
private struct SmoothLayoutSettingsView: View {
    @ObservedObject private var settings = SmoothLayoutSettingsStore.shared
    @State private var selectedMonitorId: String?

    private var monitors: [SmoothMonitorSummary] {
        sortedMonitorInfos.map {
            SmoothMonitorSummary(
                screenId: $0.monitorAppKitNsScreenScreensId,
                name: $0.name,
                width: $0.width,
                height: $0.height,
            )
        }
    }

    private var selectedMonitor: SmoothMonitorSummary? {
        monitors.first { $0.id == selectedMonitorId } ?? monitors.first
    }

    var body: some View {
        HSplitView {
            monitorSidebar
                .frame(minWidth: 220, idealWidth: 240, maxWidth: 280)

            if let monitor = selectedMonitor {
                monitorEditor(monitor)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "display.trianglebadge.exclamationmark")
                        .font(.largeTitle)
                    Text("Nenhum monitor encontrado")
                        .font(.headline)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("AeroSpaceSmooth")
        .onAppear {
            for monitor in sortedMonitorInfos {
                _ = settings.profile(for: monitor)
            }
            if selectedMonitorId == nil {
                selectedMonitorId = monitors.first?.id
            }
        }
    }

    private var monitorSidebar: some View {
        List(monitors, selection: $selectedMonitorId) { monitor in
            VStack(alignment: .leading, spacing: 4) {
                Label(monitor.name, systemImage: monitor.isHorizontal ? "display" : "rectangle.portrait")
                    .font(.headline)
                Text("\(monitor.orientationTitle) · \(Int(monitor.width))×\(Int(monitor.height))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .tag(monitor.id)
        }
    }

    private func monitorEditor(_ monitor: SmoothMonitorSummary) -> some View {
        let profile = settings.profile(named: monitor.name, isHorizontal: monitor.isHorizontal).normalized
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(monitor.name)
                            .font(.largeTitle.bold())
                        Text("Escolha como este monitor organiza de 1 a 10 janelas.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restaurar padrão") {
                        settings.resetProfile(monitorName: monitor.name, isHorizontal: monitor.isHorizontal)
                    }
                }

                Toggle(
                    "Organização automática neste monitor",
                    isOn: Binding(
                        get: { profile.enabled },
                        set: {
                            settings.setEnabled(
                                $0,
                                monitorName: monitor.name,
                                isHorizontal: monitor.isHorizontal,
                            )
                        },
                    ),
                )
                .toggleStyle(.switch)

                HStack {
                    Text("Limite de janelas por workspace")
                    Spacer()
                    Stepper(
                        "\(profile.tileLimit)",
                        value: Binding(
                            get: { profile.tileLimit },
                            set: {
                                settings.setTileLimit(
                                    $0,
                                    monitorName: monitor.name,
                                    isHorizontal: monitor.isHorizontal,
                                )
                            },
                        ),
                        in: 1 ... SmoothMonitorLayoutProfile.configuredWindowCount,
                    )
                    .frame(width: 110)
                }
                .disabled(!profile.enabled)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300), spacing: 14)],
                    alignment: .leading,
                    spacing: 14,
                ) {
                    ForEach(1 ... SmoothMonitorLayoutProfile.configuredWindowCount, id: \.self) { count in
                        layoutCard(
                            monitor: monitor,
                            count: count,
                            style: profile.style(for: count),
                            enabled: profile.enabled,
                        )
                    }
                }
            }
            .padding(24)
        }
    }

    private func layoutCard(
        monitor: SmoothMonitorSummary,
        count: Int,
        style: SmoothLayoutStyle,
        enabled: Bool,
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(count) \(count == 1 ? "janela" : "janelas")")
                    .font(.headline)
                Spacer()
                Picker(
                    "Estilo",
                    selection: Binding(
                        get: { style },
                        set: {
                            settings.setStyle(
                                $0,
                                windowCount: count,
                                monitorName: monitor.name,
                                isHorizontal: monitor.isHorizontal,
                            )
                        },
                    ),
                ) {
                    ForEach(SmoothLayoutStyle.available(for: count)) { candidate in
                        Text(candidate.title).tag(candidate)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            SmoothLayoutPreview(
                style: style,
                windowCount: count,
                monitorIsHorizontal: monitor.isHorizontal,
            )
            .frame(height: monitor.isHorizontal ? 105 : 150)

            Text(style.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(enabled ? 1 : 0.45)
        .disabled(!enabled)
    }
}

private struct SmoothLayoutPreview: View {
    let style: SmoothLayoutStyle
    let windowCount: Int
    let monitorIsHorizontal: Bool

    var body: some View {
        GeometryReader { geometry in
            let inset = CGFloat(5)
            let canvas = CGRect(
                x: inset,
                y: inset,
                width: geometry.size.width - inset * 2,
                height: geometry.size.height - inset * 2,
            )
            let frames = SmoothLayoutPreviewGeometry.frames(
                style: style,
                count: windowCount,
                monitorIsHorizontal: monitorIsHorizontal,
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.72))

                ForEach(Array(frames.enumerated()), id: \.offset) { index, frame in
                    let rect = CGRect(
                        x: canvas.minX + frame.minX * canvas.width,
                        y: canvas.minY + frame.minY * canvas.height,
                        width: frame.width * canvas.width,
                        height: frame.height * canvas.height,
                    ).insetBy(dx: 2, dy: 2)

                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: index == 0
                                    ? [Color.cyan, Color.green]
                                    : [Color.blue.opacity(0.75), Color.purple.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing,
                            ),
                        )
                        .overlay {
                            Text("\(index + 1)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        }
                        .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                        .offset(x: rect.minX, y: rect.minY)
                }
            }
        }
        .accessibilityLabel("Prévia de \(style.title) com \(windowCount) janelas")
    }
}

enum SmoothLayoutPreviewGeometry {
    static func frames(style requestedStyle: SmoothLayoutStyle, count: Int, monitorIsHorizontal: Bool) -> [CGRect] {
        guard count > 0 else { return [] }
        let style: SmoothLayoutStyle = count == 1
            ? .fullscreen
            : requestedStyle == .fullscreen ? .columns : requestedStyle
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)

        switch style {
            case .fullscreen:
                return [full]
            case .columns:
                return (0 ..< count).map {
                    CGRect(x: CGFloat($0) / CGFloat(count), y: 0, width: 1 / CGFloat(count), height: 1)
                }
            case .rows:
                return (0 ..< count).map {
                    CGRect(x: 0, y: CGFloat($0) / CGFloat(count), width: 1, height: 1 / CGFloat(count))
                }
            case .dwindle:
                var result: [CGRect] = []
                appendDwindleFrames(count: count, depth: 0, region: full, result: &result)
                return result
            case .verticalPairs:
                return rowFrames(count: count, columnsPerRow: 2)
            case .grid:
                let aspectRatio = monitorIsHorizontal ? 16.0 / 9.0 : 9.0 / 16.0
                let columns = min(count, max(1, Int(ceil(sqrt(Double(count) * aspectRatio)))))
                return rowFrames(count: count, columnsPerRow: columns)
        }
    }

    private static func appendDwindleFrames(count: Int, depth: Int, region: CGRect, result: inout [CGRect]) {
        if count == 1 {
            result.append(region)
            return
        }

        if depth.isMultiple(of: 2) {
            result.append(CGRect(x: region.minX, y: region.minY, width: region.width / 2, height: region.height))
            appendDwindleFrames(
                count: count - 1,
                depth: depth + 1,
                region: CGRect(x: region.midX, y: region.minY, width: region.width / 2, height: region.height),
                result: &result,
            )
        } else {
            result.append(CGRect(x: region.minX, y: region.minY, width: region.width, height: region.height / 2))
            appendDwindleFrames(
                count: count - 1,
                depth: depth + 1,
                region: CGRect(x: region.minX, y: region.midY, width: region.width, height: region.height / 2),
                result: &result,
            )
        }
    }

    private static func rowFrames(count: Int, columnsPerRow: Int) -> [CGRect] {
        let rowCount = Int(ceil(Double(count) / Double(columnsPerRow)))
        var result: [CGRect] = []
        var remaining = count

        for row in 0 ..< rowCount {
            let columnsInThisRow = min(columnsPerRow, remaining)
            for column in 0 ..< columnsInThisRow {
                result.append(
                    CGRect(
                        x: CGFloat(column) / CGFloat(columnsInThisRow),
                        y: CGFloat(row) / CGFloat(rowCount),
                        width: 1 / CGFloat(columnsInThisRow),
                        height: 1 / CGFloat(rowCount),
                    ),
                )
            }
            remaining -= columnsInThisRow
        }
        return result
    }
}
