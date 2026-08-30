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
            case .general: "Geral"
            case .workspaces: "Workspaces"
            case .applications: "Aplicativos"
            case .automation: "Automação"
            case .shortcuts: "Atalhos"
            case .configFile: "Arquivo TOML"
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
            title: "Geral",
            subtitle: "Inicialização, comportamento da árvore e opções padrão do AeroSpace.",
        ) {
            SettingsCard("Aplicativo", systemImage: "gearshape.2") {
                Picker("Versão da configuração", selection: $configSettings.draft.configVersion) {
                    Text("1").tag(1)
                    Text("2").tag(2)
                }
                Toggle("Iniciar automaticamente no login", isOn: $configSettings.draft.startAtLogin)
                Text("Neste Mac o startup principal é controlado pelo LaunchAgent. Mantenha esta opção desligada para evitar duas instâncias.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Recarregar o arquivo automaticamente", isOn: $configSettings.draft.autoReloadConfig)
            }

            SettingsCard("Árvore de janelas", systemImage: "point.3.connected.trianglepath.dotted") {
                Toggle("Achatar containers automaticamente", isOn: $configSettings.draft.flattenContainers)
                Toggle(
                    "Normalizar containers aninhados com orientação oposta",
                    isOn: $configSettings.draft.normalizeOppositeOrientation,
                )
                Picker("Layout raiz padrão", selection: $configSettings.draft.defaultRootLayout) {
                    Text("Tiles").tag("tiles")
                    Text("Accordion").tag("accordion")
                }
                Picker("Orientação raiz padrão", selection: $configSettings.draft.defaultRootOrientation) {
                    Text("Automática").tag("auto")
                    Text("Horizontal").tag("horizontal")
                    Text("Vertical").tag("vertical")
                }
                Stepper(
                    "Padding do accordion: \(configSettings.draft.accordionPadding) px",
                    value: $configSettings.draft.accordionPadding,
                    in: 0 ... 1000,
                )
            }

            SettingsCard("Animações", systemImage: "waveform.path") {
                Stepper(
                    "Duração: \(configSettings.draft.layoutAnimationDurationMs) ms",
                    value: $configSettings.draft.layoutAnimationDurationMs,
                    in: 0 ... 1000,
                    step: 10,
                )
                Toggle(
                    "Respeitar Reduzir Movimento do macOS",
                    isOn: $configSettings.draft.layoutAnimationRespectsReduceMotion,
                )
                Text("Use 0 ms para desativar a animação. O valor atual padrão é 160 ms.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var workspacesPage: some View {
        SettingsPage(
            title: "Workspaces",
            subtitle: "Defina os espaços persistentes, o monitor de cada um e os gaps.",
        ) {
            SettingsCard("Workspaces persistentes", systemImage: "square.grid.3x3") {
                StringListEditor(
                    items: $configSettings.draft.persistentWorkspaces,
                    placeholder: "Nome do workspace",
                    addTitle: "Adicionar workspace",
                )
            }

            SettingsCard("Monitor por workspace", systemImage: "display.2") {
                WorkspaceAssignmentsEditor(assignments: $configSettings.draft.workspaceAssignments)
            }

            SettingsCard("Gaps", systemImage: "rectangle.inset.filled") {
                GapsEditor(gaps: $configSettings.draft.gaps)
            }
        }
    }

    private var applicationsPage: some View {
        SettingsPage(
            title: "Aplicativos",
            subtitle: "Regras executadas quando uma nova janela é detectada.",
        ) {
            SettingsCard("on-window-detected", systemImage: "arrowshape.turn.up.right.circle") {
                WindowRulesEditor(rules: $configSettings.draft.windowRules)
            }
        }
    }

    private var automationPage: some View {
        SettingsPage(
            title: "Automação",
            subtitle: "Ambiente e comandos executados pelos eventos do AeroSpace.",
        ) {
            SettingsCard("Ambiente de execução", systemImage: "terminal") {
                Toggle(
                    "Herdar variáveis do ambiente",
                    isOn: $configSettings.draft.inheritEnvironmentVariables,
                )
                KeyValueEditor(
                    pairs: $configSettings.draft.environmentVariables,
                    keyPlaceholder: "VARIÁVEL",
                    valuePlaceholder: "valor",
                    addTitle: "Adicionar variável",
                )
            }

            SettingsCard("Depois do login", systemImage: "person.crop.circle.badge.checkmark") {
                Text("Opção mantida para compatibilidade; versões atuais esperam esta lista vazia.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                StringListEditor(
                    items: $configSettings.draft.afterLoginCommands,
                    placeholder: "Comando",
                    addTitle: "Adicionar comando",
                )
            }

            SettingsCard("Depois de iniciar", systemImage: "play.circle") {
                StringListEditor(
                    items: $configSettings.draft.afterStartupCommands,
                    placeholder: "Comando",
                    addTitle: "Adicionar comando",
                )
            }

            SettingsCard("Ao trocar o monitor focado", systemImage: "arrow.left.arrow.right") {
                StringListEditor(
                    items: $configSettings.draft.onFocusedMonitorChanged,
                    placeholder: "Comando",
                    addTitle: "Adicionar comando",
                )
            }

            SettingsCard("Ao trocar o foco", systemImage: "scope") {
                StringListEditor(
                    items: $configSettings.draft.onFocusChanged,
                    placeholder: "Comando",
                    addTitle: "Adicionar comando",
                )
            }
        }
    }

    private var shortcutsPage: some View {
        SettingsPage(
            title: "Atalhos",
            subtitle: "Todos os bindings dos modos main e service.",
        ) {
            SettingsCard("Modo principal", systemImage: "keyboard") {
                HotkeyBindingsEditor(bindings: $configSettings.draft.mainBindings)
            }
            SettingsCard("Modo de manutenção", systemImage: "wrench.and.screwdriver") {
                HotkeyBindingsEditor(bindings: $configSettings.draft.serviceBindings)
            }
        }
    }

    private var configFilePage: some View {
        SettingsPage(
            title: "Arquivo TOML",
            subtitle: configSettings.configPath,
        ) {
            HStack {
                Button("Abrir no editor") { configSettings.openConfigFile() }
                Button("Ler novamente") { configSettings.load() }
                Spacer()
            }

            SettingsCard("Prévia preservando comentários", systemImage: "doc.text.magnifyingglass") {
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
                Text("Alterações de layout são aplicadas imediatamente.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Descartar") { configSettings.discardChanges() }
                    .disabled(!configSettings.hasChanges)
                Button("Salvar e aplicar") {
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
                    Label("Alterações não salvas", systemImage: "circle.fill")
                        .foregroundStyle(.orange)
                }
            case .saving:
                ProgressView().controlSize(.small)
                Text("Validando e salvando…")
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
    @ViewBuilder let content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
        } label: {
            Label(title, systemImage: systemImage).font(.headline)
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
                        "Monitores separados por vírgula",
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
            AddRowButton("Adicionar atribuição") {
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
                        Text("Condição").frame(width: 70, alignment: .leading)
                        TextField("test %{app-bundle-id} = …", text: $rule.condition)
                        RemoveRowButton { rules.removeAll { $0.id == rule.id } }
                    }
                    CommandListEditor(commands: $rule.commands)
                }
                .padding(10)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
            }
            AddRowButton("Adicionar regra") {
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
            AddRowButton("Adicionar atalho") {
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
                    TextField("Comando", text: $commands[index])
                        .font(.system(.body, design: .monospaced))
                    if commands.count > 1 {
                        RemoveRowButton { commands.remove(at: index) }
                    }
                }
            }
            Button {
                commands.append("")
            } label: {
                Label("Encadear comando", systemImage: "arrow.right")
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
                gapStepper("Interno horizontal", value: $gaps.innerHorizontal)
                gapStepper("Interno vertical", value: $gaps.innerVertical)
            }
            GridRow {
                gapStepper("Externo esquerdo", value: $gaps.outerLeft)
                gapStepper("Externo direito", value: $gaps.outerRight)
            }
            GridRow {
                gapStepper("Externo superior", value: $gaps.outerTop)
                gapStepper("Externo inferior", value: $gaps.outerBottom)
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
        .help("Remover")
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
                    Text("Nenhum monitor encontrado")
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
