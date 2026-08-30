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
    SwiftUI.Window("AeroSpaceSmooth Settings", id: smoothLayoutSettingsWindowId) {
        SmoothLayoutSettingsView()
            .frame(minWidth: 1040, minHeight: 680)
    }
    .defaultSize(width: 1180, height: 820)
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

private enum SmoothSettingsSection: String, CaseIterable, Identifiable {
    case layouts
    case general
    case workspaces
    case applications
    case automation
    case shortcuts
    case configFile

    var id: String { rawValue }

    var title: String {
        switch self {
            case .layouts: "Layouts"
            case .general: "General"
            case .workspaces: "Workspaces"
            case .applications: "Applications"
            case .automation: "Automation"
            case .shortcuts: "Shortcuts"
            case .configFile: "TOML File"
        }
    }

    var systemImage: String {
        switch self {
            case .layouts: "rectangle.3.group"
            case .general: "switch.2"
            case .workspaces: "square.grid.3x3"
            case .applications: "app.badge"
            case .automation: "bolt.horizontal.circle"
            case .shortcuts: "keyboard"
            case .configFile: "doc.text"
        }
    }
}

@MainActor
private struct SmoothLayoutSettingsView: View {
    @StateObject private var configSettings = VisualConfigSettingsStore()
    @State private var selection: SmoothSettingsSection = .layouts

    var body: some View {
        HSplitView {
            List(SmoothSettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .padding(.vertical, 5)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 190, idealWidth: 210, maxWidth: 240)

            VStack(spacing: 0) {
                selectedPage
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                settingsFooter
            }
        }
        .navigationTitle("AeroSpaceSmooth")
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch selection {
            case .layouts:
                MonitorLayoutsSettingsPane()
            case .general:
                generalPage
            case .workspaces:
                workspacesPage
            case .applications:
                applicationsPage
            case .automation:
                automationPage
            case .shortcuts:
                shortcutsPage
            case .configFile:
                configFilePage
        }
    }

    private var generalPage: some View {
        SettingsPage(
            title: "General",
            subtitle: "Startup, window-tree behavior and AeroSpace defaults.",
        ) {
            SettingsCard(
                "Application",
                systemImage: "gearshape.2",
                help: "Configuration version controls the TOML schema. Start at login launches AeroSpace automatically. Auto reload watches the TOML file and reloads external edits.",
            ) {
                Picker("Configuration version", selection: $configSettings.draft.configVersion) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                }
                Toggle("Start at login", isOn: $configSettings.draft.startAtLogin)
                Text("Startup on this Mac is managed by a LaunchAgent. Keep this off to prevent duplicate instances.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Automatically reload the configuration file", isOn: $configSettings.draft.autoReloadConfig)
            }

            SettingsCard(
                "Window Tree",
                systemImage: "point.3.connected.trianglepath.dotted",
                help: "Flatten removes redundant nested containers. Opposite-orientation normalization alternates split directions. Root layout and orientation define new workspaces; accordion padding controls the visible edge of stacked accordion windows.",
            ) {
                Toggle("Automatically flatten containers", isOn: $configSettings.draft.flattenContainers)
                Toggle(
                    "Normalize nested containers with opposite orientations",
                    isOn: $configSettings.draft.normalizeOppositeOrientation,
                )
                Picker("Default root layout", selection: $configSettings.draft.defaultRootLayout) {
                    Text("Tiles").tag("tiles")
                    Text("Accordion").tag("accordion")
                }
                Picker("Default root orientation", selection: $configSettings.draft.defaultRootOrientation) {
                    Text("Automatic").tag("auto")
                    Text("Horizontal").tag("horizontal")
                    Text("Vertical").tag("vertical")
                }
                Stepper(
                    "Accordion padding: \(configSettings.draft.accordionPadding) px",
                    value: $configSettings.draft.accordionPadding,
                    in: 0 ... 1000,
                )
            }

            SettingsCard(
                "Animations",
                systemImage: "waveform.path",
                help: "Duration controls how long a coordinated window reflow takes. Reduce Motion follows the macOS Accessibility preference. A duration of 0 disables layout animations.",
            ) {
                Stepper(
                    "Duration: \(configSettings.draft.layoutAnimationDurationMs) ms",
                    value: $configSettings.draft.layoutAnimationDurationMs,
                    in: 0 ... 1000,
                    step: 10,
                )
                Toggle(
                    "Respect the macOS Reduce Motion setting",
                    isOn: $configSettings.draft.layoutAnimationRespectsReduceMotion,
                )
                Text("Use 0 ms to disable animations. The current default is 160 ms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var workspacesPage: some View {
        SettingsPage(
            title: "Workspaces",
            subtitle: "Define persistent workspaces, monitor assignments and gaps.",
        ) {
            SettingsCard(
                "Persistent Workspaces",
                systemImage: "square.grid.3x3",
                help: "Persistent workspaces exist even when they contain no windows, which keeps navigation and monitor assignments stable.",
            ) {
                StringListEditor(
                    items: $configSettings.draft.persistentWorkspaces,
                    placeholder: "Workspace name",
                    addTitle: "Add Workspace",
                )
            }

            SettingsCard(
                "Workspace Monitor Assignment",
                systemImage: "display.2",
                help: "Pins each workspace to one or more preferred monitors. Monitor names are evaluated in order, and the first connected match is used.",
            ) {
                WorkspaceAssignmentsEditor(assignments: $configSettings.draft.workspaceAssignments)
            }

            SettingsCard(
                "Gaps",
                systemImage: "rectangle.inset.filled",
                help: "Inner gaps add space between tiled windows. Outer gaps reserve space between the tiling area and each screen edge.",
            ) {
                GapsEditor(gaps: $configSettings.draft.gaps)
            }
        }
    }

    private var applicationsPage: some View {
        SettingsPage(
            title: "Applications",
            subtitle: "Rules that run when a new application window is detected.",
        ) {
            SettingsCard(
                "Window Detection Rules",
                systemImage: "arrowshape.turn.up.right.circle",
                help: "Each rule tests window properties such as bundle identifier or title, then runs one or more AeroSpace commands for matching windows.",
            ) {
                WindowRulesEditor(rules: $configSettings.draft.windowRules)
            }
        }
    }

    private var automationPage: some View {
        SettingsPage(
            title: "Automation",
            subtitle: "Environment variables and commands triggered by AeroSpace events.",
        ) {
            SettingsCard(
                "Execution Environment",
                systemImage: "terminal",
                help: "Inherited variables come from the AeroSpace process. Custom variables are added or overridden for commands executed by AeroSpace.",
            ) {
                Toggle(
                    "Inherit environment variables",
                    isOn: $configSettings.draft.inheritEnvironmentVariables,
                )
                KeyValueEditor(
                    pairs: $configSettings.draft.environmentVariables,
                    keyPlaceholder: "VARIABLE",
                    valuePlaceholder: "value",
                    addTitle: "Add Variable",
                )
            }

            SettingsCard(
                "After Login",
                systemImage: "person.crop.circle.badge.checkmark",
                help: "Legacy commands run after macOS login. Current AeroSpace versions keep this list empty; prefer After Startup for normal initialization.",
            ) {
                Text("This option is retained for compatibility; current versions expect this list to be empty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StringListEditor(
                    items: $configSettings.draft.afterLoginCommands,
                    placeholder: "Command",
                    addTitle: "Add Command",
                )
            }

            SettingsCard(
                "After Startup",
                systemImage: "play.circle",
                help: "Commands in this list run once after AeroSpace has started and loaded its configuration.",
            ) {
                StringListEditor(
                    items: $configSettings.draft.afterStartupCommands,
                    placeholder: "Command",
                    addTitle: "Add Command",
                )
            }

            SettingsCard(
                "Focused Monitor Changed",
                systemImage: "arrow.left.arrow.right",
                help: "Runs after focus crosses to a different monitor. Use it for status bars or monitor-specific automation, not for workspace reassignment.",
            ) {
                StringListEditor(
                    items: $configSettings.draft.onFocusedMonitorChanged,
                    placeholder: "Command",
                    addTitle: "Add Command",
                )
            }

            SettingsCard(
                "Focus Changed",
                systemImage: "scope",
                help: "Runs whenever the focused window or workspace changes. Keep these commands fast because the event may occur frequently.",
            ) {
                StringListEditor(
                    items: $configSettings.draft.onFocusChanged,
                    placeholder: "Command",
                    addTitle: "Add Command",
                )
            }
        }
    }

    private var shortcutsPage: some View {
        SettingsPage(
            title: "Shortcuts",
            subtitle: "All key bindings from the main and service modes.",
        ) {
            SettingsCard(
                "Main Mode",
                systemImage: "keyboard",
                help: "Main-mode bindings are the shortcuts available during normal use. A binding can run one command or a command chain.",
            ) {
                HotkeyBindingsEditor(bindings: $configSettings.draft.mainBindings)
            }
            SettingsCard(
                "Service Mode",
                systemImage: "wrench.and.screwdriver",
                help: "Service-mode bindings are available only after entering that mode and are typically used for maintenance or recovery commands.",
            ) {
                HotkeyBindingsEditor(bindings: $configSettings.draft.serviceBindings)
            }
        }
    }

    private var configFilePage: some View {
        SettingsPage(
            title: "TOML File",
            subtitle: configSettings.configPath,
        ) {
            HStack {
                Button("Open in Editor") { configSettings.openConfigFile() }
                Button("Reload from Disk") { configSettings.load() }
                Spacer()
            }

            SettingsCard(
                "Comment-Preserving Preview",
                systemImage: "doc.text.magnifyingglass",
                help: "Shows the exact TOML that will be saved. Existing comments and unrelated keys are preserved when visual settings are updated.",
            ) {
                ScrollView([.horizontal, .vertical]) {
                    Text(configSettings.previewText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(minHeight: 480)
                .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var settingsFooter: some View {
        HStack(spacing: 12) {
            statusLabel
            Spacer()
            if selection == .layouts {
                Text("Layout changes are applied immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Discard") { configSettings.discardChanges() }
                    .disabled(!configSettings.hasChanges)
                Button("Save & Apply") {
                    Task.startUnstructured { await configSettings.save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!configSettings.hasChanges || configSettings.status == .saving)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch configSettings.status {
            case .ready:
                if configSettings.hasChanges {
                    Label("Unsaved changes", systemImage: "circle.fill")
                        .foregroundStyle(.orange)
                }
            case .saving:
                ProgressView().controlSize(.small)
                Text("Validating and saving…")
            case .saved(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.largeTitle.bold())
                    Text(subtitle).foregroundStyle(.secondary)
                }
                content
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    let help: String
    @ViewBuilder let content: Content

    init(_ title: String, systemImage: String, help: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
        } label: {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                SettingInfoButton(title: title, message: help)
            }
            .font(.headline)
        }
    }
}

private struct SettingInfoButton: View {
    let title: String
    let message: String
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .font(.body)
        .help("About \(title)")
        .accessibilityLabel("About \(title)")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 320, alignment: .leading)
        }
    }
}

private struct StringListEditor: View {
    @Binding var items: [String]
    let placeholder: String
    let addTitle: String

    var body: some View {
        VStack(spacing: 8) {
            ForEach(items.indices, id: \.self) { index in
                HStack {
                    TextField(placeholder, text: $items[index])
                        .textFieldStyle(.roundedBorder)
                    RemoveRowButton { items.remove(at: index) }
                }
            }
            AddRowButton(addTitle) { items.append("") }
        }
    }
}

private struct KeyValueEditor: View {
    @Binding var pairs: [VisualConfigPair]
    let keyPlaceholder: String
    let valuePlaceholder: String
    let addTitle: String

    var body: some View {
        VStack(spacing: 8) {
            ForEach($pairs) { $pair in
                HStack {
                    TextField(keyPlaceholder, text: $pair.key).frame(width: 180)
                    TextField(valuePlaceholder, text: $pair.value)
                    RemoveRowButton { pairs.removeAll { $0.id == pair.id } }
                }
            }
            AddRowButton(addTitle) { pairs.append(VisualConfigPair(key: "", value: "")) }
        }
    }
}

private struct WorkspaceAssignmentsEditor: View {
    @Binding var assignments: [VisualWorkspaceAssignment]

    var body: some View {
        VStack(spacing: 8) {
            ForEach($assignments) { $assignment in
                HStack {
                    TextField("Workspace", text: $assignment.workspace).frame(width: 110)
                    TextField(
                        "Monitors separated by commas",
                        text: Binding(
                            get: { assignment.monitors.joined(separator: ", ") },
                            set: {
                                assignment.monitors = $0.split(separator: ",")
                                    .map { $0.trimmingCharacters(in: .whitespaces) }
                                    .filter { !$0.isEmpty }
                            },
                        ),
                    )
                    RemoveRowButton { assignments.removeAll { $0.id == assignment.id } }
                }
            }
            AddRowButton("Add Assignment") {
                assignments.append(VisualWorkspaceAssignment(workspace: "", monitors: ["main"]))
            }
        }
    }
}

private struct WindowRulesEditor: View {
    @Binding var rules: [VisualWindowRule]

    var body: some View {
        VStack(spacing: 12) {
            ForEach($rules) { $rule in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Condition").frame(width: 70, alignment: .leading)
                        TextField("test %{app-bundle-id} = …", text: $rule.condition)
                        RemoveRowButton { rules.removeAll { $0.id == rule.id } }
                    }
                    CommandListEditor(commands: $rule.commands)
                }
                .padding(10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
            }
            AddRowButton("Add Rule") {
                rules.append(VisualWindowRule(condition: "", commands: [""]))
            }
        }
    }
}

private struct HotkeyBindingsEditor: View {
    @Binding var bindings: [VisualHotkeyBinding]

    var body: some View {
        VStack(spacing: 10) {
            ForEach($bindings) { $binding in
                HStack(alignment: .top, spacing: 10) {
                    TextField("alt-…", text: $binding.shortcut)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 180)
                    CommandListEditor(commands: $binding.commands)
                    RemoveRowButton { bindings.removeAll { $0.id == binding.id } }
                }
                .padding(.vertical, 2)
            }
            AddRowButton("Add Shortcut") {
                bindings.append(VisualHotkeyBinding(shortcut: "", commands: [""]))
            }
        }
    }
}

private struct CommandListEditor: View {
    @Binding var commands: [String]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(commands.indices, id: \.self) { index in
                HStack {
                    TextField("Command", text: $commands[index])
                        .font(.system(.body, design: .monospaced))
                    if commands.count > 1 {
                        RemoveRowButton { commands.remove(at: index) }
                    }
                }
            }
            Button {
                commands.append("")
            } label: {
                Label("Chain Command", systemImage: "arrow.right")
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct GapsEditor: View {
    @Binding var gaps: VisualConfigGaps

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 10) {
            GridRow {
                gapStepper("Inner horizontal", value: $gaps.innerHorizontal)
                gapStepper("Inner vertical", value: $gaps.innerVertical)
            }
            GridRow {
                gapStepper("Outer left", value: $gaps.outerLeft)
                gapStepper("Outer right", value: $gaps.outerRight)
            }
            GridRow {
                gapStepper("Outer top", value: $gaps.outerTop)
                gapStepper("Outer bottom", value: $gaps.outerBottom)
            }
        }
    }

    private func gapStepper(_ title: String, value: Binding<Int>) -> some View {
        Stepper("\(title): \(value.wrappedValue) px", value: value, in: 0 ... 200)
            .frame(minWidth: 260, alignment: .leading)
    }
}

private struct AddRowButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "plus.circle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RemoveRowButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Remove")
    }
}

@MainActor
private struct MonitorLayoutsSettingsPane: View {
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
                    Text("No monitors found")
                        .font(.headline)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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
                        Text("Choose how this monitor arranges from 1 to 10 windows.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset to Defaults") {
                        settings.resetProfile(monitorName: monitor.name, isHorizontal: monitor.isHorizontal)
                    }
                }

                HStack {
                    Toggle(
                        "Automatic layout on this monitor",
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
                    SettingInfoButton(
                        title: "Automatic layout",
                        message: "When enabled, AeroSpaceSmooth selects the layout configured for the current number of tiled windows on this monitor. Disable it to use standard AeroSpace behavior.",
                    )
                }

                HStack {
                    Text("Window limit per workspace")
                    SettingInfoButton(
                        title: "Window limit per workspace",
                        message: "When a workspace exceeds this number of tiled windows, overflow windows move to another workspace assigned to the same monitor.",
                    )
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
                    .disabled(!profile.enabled)
                }

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
                Text("\(count) \(count == 1 ? "window" : "windows")")
                    .font(.headline)
                SettingInfoButton(
                    title: "\(count)-window layout",
                    message: style.detail + " This selection applies only to this monitor when exactly \(count) tiled \(count == 1 ? "window is" : "windows are") present.",
                )
                Spacer()
                Picker(
                    "Style",
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
        .opacity(enabled ? 1 : 0.7)
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

                if style == .manual {
                    VStack(spacing: 6) {
                        Image(systemName: "hand.draw")
                            .font(.title2)
                        Text("Manual layout")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
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
        }
        .accessibilityLabel("Preview of \(style.title) with \(windowCount) windows")
    }
}

enum SmoothLayoutPreviewGeometry {
    static func frames(style requestedStyle: SmoothLayoutStyle, count: Int, monitorIsHorizontal: Bool) -> [CGRect] {
        guard count > 0 else { return [] }
        let style: SmoothLayoutStyle = count == 1
            ? requestedStyle == .manual ? .manual : .fullscreen
            : requestedStyle == .fullscreen ? .columns : requestedStyle
        let full = CGRect(x: 0, y: 0, width: 1, height: 1)

        switch style {
            case .manual:
                return []
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
