import SwiftUI

@MainActor
struct SmoothCustomLayoutEditorView: View {
    let monitorName: String
    let monitorWidth: CGFloat
    let monitorHeight: CGFloat
    let previousLayout: SmoothCustomLayoutBlueprint?
    let onSave: (SmoothCustomLayoutBlueprint) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: SmoothCustomLayoutBlueprint
    @State private var selectedSlot = 0
    @State private var hybridStart: Int
    @State private var primaryAxis: SmoothSplitAxis
    @State private var undoStack: [SmoothCustomLayoutBlueprint] = []
    @State private var redoStack: [SmoothCustomLayoutBlueprint] = []
    @State private var interactiveEditStart: SmoothCustomLayoutBlueprint?

    private var monitorIsHorizontal: Bool { monitorWidth >= monitorHeight }

    init(
        monitorName: String,
        monitorWidth: CGFloat,
        monitorHeight: CGFloat,
        layout: SmoothCustomLayoutBlueprint,
        previousLayout: SmoothCustomLayoutBlueprint?,
        onSave: @escaping (SmoothCustomLayoutBlueprint) -> Void,
    ) {
        self.monitorName = monitorName
        self.monitorWidth = max(monitorWidth, 1)
        self.monitorHeight = max(monitorHeight, 1)
        self.previousLayout = previousLayout
        self.onSave = onSave
        _draft = State(initialValue: layout)
        _hybridStart = State(initialValue: min(max(3, layout.windowCount), 4))
        _primaryAxis = State(initialValue: monitorWidth >= monitorHeight ? .horizontal : .vertical)
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider()
            HStack(spacing: 0) {
                canvas
                    .padding(24)
                Divider()
                controls
                    .frame(width: 330)
            }
            Divider()
            editorFooter
        }
        .frame(minWidth: 980, minHeight: 680)
    }

    private var editorHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Custom Layout")
                    .font(.title2.bold())
                Text("\(monitorName) · \(draft.windowCount) \(draft.windowCount == 1 ? "window" : "windows")")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .disabled(undoStack.isEmpty)
            Button {
                redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .disabled(redoStack.isEmpty)
        }
        .padding(18)
    }

    private var canvas: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Drag a glowing divider to resize. Select a tile for exact controls.")
                .font(.callout)
                .foregroundStyle(.secondary)
            SmoothMonitorPreviewFrame(
                monitorName: monitorName,
                monitorWidth: monitorWidth,
                monitorHeight: monitorHeight,
            ) {
                SmoothCustomLayoutCanvas(
                    layout: $draft,
                    selectedSlot: $selectedSlot,
                    onResizeBegan: beginInteractiveEdit,
                    onResizeEnded: endInteractiveEdit,
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Label(
                "Accurate \(Int(monitorWidth)) × \(Int(monitorHeight)) aspect ratio. Real windows move only after Save Layout.",
                systemImage: "checkmark.shield",
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                controlSection("Starting Point", help: "Replace the draft with a preset, or copy the previous window count and split one of its tiles for the new window.") {
                    Menu("Apply Preset") {
                        Button("Dwindle") { applyPreset(.dwindle) }
                        Button("Columns") { applyPreset(.columns) }
                        Button("Rows") { applyPreset(.rows) }
                        Button("Vertical Pairs") { applyPreset(.verticalPairs) }
                        Button("Grid") { applyPreset(.grid) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let previousLayout {
                        Button("Continue from \(previousLayout.windowCount) Windows") {
                            continueFromPrevious(previousLayout)
                        }
                        .disabled(!previousLayout.isValid)
                    }
                }

                if draft.windowCount >= 3 {
                    controlSection("Hybrid Dwindle", help: "Keeps the earlier panes in a straight primary split and starts an alternating Dwindle inside the final pane at the selected window number.") {
                        Picker("Primary direction", selection: $primaryAxis) {
                            Text("Side by Side").tag(SmoothSplitAxis.horizontal)
                            Text("Stacked").tag(SmoothSplitAxis.vertical)
                        }
                        Stepper(
                            "Dwindle starts at window \(hybridStart)",
                            value: $hybridStart,
                            in: 3 ... draft.windowCount,
                        )
                        Button("Build Hybrid Dwindle") {
                            commit {
                                $0 = .hybridDwindle(
                                    windowCount: draft.windowCount,
                                    startsAt: hybridStart,
                                    primaryAxis: primaryAxis,
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if draft.windowCount > 1 {
                    selectedTileControls
                }
            }
            .padding(18)
        }
    }

    private var selectedTileControls: some View {
        controlSection("Selected Tile \(selectedSlot + 1)", help: "Drag a divider in the monitor preview for direct resizing. These controls provide exact sizing and change the split directly surrounding the selected tile.") {
            if let frame = draft.frames[selectedSlot] {
                HStack(spacing: 8) {
                    Label(
                        "\(Int((frame.width * monitorWidth).rounded())) × \(Int((frame.height * monitorHeight).rounded()))",
                        systemImage: "rectangle.dashed",
                    )
                    Spacer()
                    Text("\(Int((frame.width * 100).rounded()))% × \(Int((frame.height * 100).rounded()))%")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack {
                Button("Move Earlier") {
                    commit { $0.swapSlots(selectedSlot, selectedSlot - 1) }
                }
                .disabled(selectedSlot == 0)
                Button("Move Later") {
                    commit { $0.swapSlots(selectedSlot, selectedSlot + 1) }
                }
                .disabled(selectedSlot == draft.windowCount - 1)
            }

            Picker(
                "Parent split",
                selection: Binding(
                    get: { draft.root.parentSplit(of: selectedSlot)?.axis ?? primaryAxis },
                    set: { axis in commit { $0.setParentAxis(axis, of: selectedSlot) } },
                ),
            ) {
                Text("Horizontal").tag(SmoothSplitAxis.horizontal)
                Text("Vertical").tag(SmoothSplitAxis.vertical)
            }

            let ratio = draft.root.parentSplit(of: selectedSlot)?.ratio ?? 0.5
            Text("First pane: \(Int((ratio * 100).rounded()))%")
                .font(.caption)
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { draft.root.parentSplit(of: selectedSlot)?.ratio ?? 0.5 },
                    set: { ratio in draft.setParentRatio(ratio, of: selectedSlot) },
                ),
                in: 0.10 ... 0.90,
                step: 0.01,
                onEditingChanged: { editing in
                    if editing {
                        beginInteractiveEdit()
                    } else {
                        endInteractiveEdit()
                    }
                },
            )

            HStack {
                Button("Balance") {
                    commit { $0.setParentRatio(0.5, of: selectedSlot) }
                }
                Button("Reverse Split") {
                    commit { $0.reverseParent(of: selectedSlot) }
                }
            }
        }
    }

    private var editorFooter: some View {
        HStack {
            if !draft.isValid {
                Label("This layout is invalid and cannot be saved.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save Layout") {
                onSave(draft)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(!draft.isValid)
        }
        .padding(18)
    }

    private func controlSection<Content: View>(
        _ title: String,
        help: String,
        @ViewBuilder content: () -> Content,
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(title).font(.headline)
                SettingInfoButton(title: title, message: help)
            }
            content()
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private func applyPreset(_ style: SmoothLayoutStyle) {
        commit {
            $0 = .preset(
                style: style,
                windowCount: draft.windowCount,
                monitorIsHorizontal: monitorIsHorizontal,
            )
        }
    }

    private func continueFromPrevious(_ previous: SmoothCustomLayoutBlueprint) {
        let splitSlot = min(selectedSlot, previous.windowCount - 1)
        guard let continued = SmoothCustomLayoutBlueprint.continuing(
            previous,
            splitSlot: splitSlot,
            axis: primaryAxis.opposite,
        ) else { return }
        commit { $0 = continued }
        selectedSlot = previous.windowCount
    }

    private func commit(_ mutation: (inout SmoothCustomLayoutBlueprint) -> Void) {
        let before = draft
        mutation(&draft)
        guard draft != before else { return }
        undoStack.append(before)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack = []
    }

    private func beginInteractiveEdit() {
        if interactiveEditStart == nil {
            interactiveEditStart = draft
        }
    }

    private func endInteractiveEdit() {
        guard let before = interactiveEditStart else { return }
        interactiveEditStart = nil
        guard before != draft else { return }
        undoStack.append(before)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack = []
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(draft)
        draft = previous
        selectedSlot = min(selectedSlot, draft.windowCount - 1)
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(draft)
        draft = next
        selectedSlot = min(selectedSlot, draft.windowCount - 1)
    }
}

struct SmoothMonitorPreviewFrame<Content: View>: View {
    let monitorName: String
    let monitorWidth: CGFloat
    let monitorHeight: CGFloat
    let content: Content

    init(
        monitorName: String,
        monitorWidth: CGFloat,
        monitorHeight: CGFloat,
        @ViewBuilder content: () -> Content,
    ) {
        self.monitorName = monitorName
        self.monitorWidth = max(monitorWidth, 1)
        self.monitorHeight = max(monitorHeight, 1)
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let size = fittedSize(in: geometry.size)
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color(nsColor: .windowFrameTextColor).opacity(0.82))
                    .shadow(color: .black.opacity(0.24), radius: 10, y: 5)

                content
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(7)
            }
            .overlay(alignment: .topTrailing) {
                Text("\(Int(monitorWidth)) × \(Int(monitorHeight))")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(11)
                    .allowsHitTesting(false)
            }
            .accessibilityLabel("\(monitorName), \(Int(monitorWidth)) by \(Int(monitorHeight))")
            .frame(width: size.width, height: size.height)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }

    private func fittedSize(in available: CGSize) -> CGSize {
        let width = max(available.width, 1)
        let height = max(available.height, 1)
        let ratio = monitorWidth / monitorHeight
        if width / height > ratio {
            return CGSize(width: height * ratio, height: height)
        }
        return CGSize(width: width, height: width / ratio)
    }
}

private struct SmoothCustomLayoutCanvas: View {
    @Binding var layout: SmoothCustomLayoutBlueprint
    @Binding var selectedSlot: Int
    let onResizeBegan: () -> Void
    let onResizeEnded: () -> Void

    @State private var hoveredSplitId: String?
    @State private var activeSplitId: String?

    var body: some View {
        GeometryReader { geometry in
            let inset = CGFloat(7)
            let canvas = CGRect(
                x: inset,
                y: inset,
                width: max(geometry.size.width - inset * 2, 1),
                height: max(geometry.size.height - inset * 2, 1),
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.black.opacity(0.82))

                ForEach(layout.frames.keys.sorted(), id: \.self) { slot in
                    if let frame = layout.frames[slot] {
                        let rect = CGRect(
                            x: canvas.minX + frame.minX * canvas.width,
                            y: canvas.minY + frame.minY * canvas.height,
                            width: frame.width * canvas.width,
                            height: frame.height * canvas.height,
                        ).insetBy(dx: 3, dy: 3)

                        Button {
                            selectedSlot = slot
                        } label: {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: slot == selectedSlot
                                            ? [Color.cyan, Color.green]
                                            : [Color.blue.opacity(0.8), Color.purple.opacity(0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing,
                                    ),
                                )
                                .overlay {
                                    Text("\(slot + 1)")
                                        .font(.title3.bold())
                                        .foregroundStyle(.white)
                                }
                                .overlay {
                                    if slot == selectedSlot {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(.white, lineWidth: 3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                        .offset(x: rect.minX, y: rect.minY)
                        .accessibilityLabel("Window slot \(slot + 1)")
                    }
                }

                ForEach(layout.splits) { split in
                    splitHandle(split, canvas: canvas)
                }

                if layout.windowCount == 1 {
                    Text("Full display area")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            .coordinateSpace(name: "customLayoutCanvas")
        }
    }

    @ViewBuilder
    private func splitHandle(_ split: SmoothCustomLayoutSplit, canvas: CGRect) -> some View {
        let boundary = CGPoint(
            x: canvas.minX + (split.region.minX + (split.axis == .horizontal ? split.region.width * split.ratio : 0)) * canvas.width,
            y: canvas.minY + (split.region.minY + (split.axis == .vertical ? split.region.height * split.ratio : 0)) * canvas.height,
        )
        let isEmphasized = hoveredSplitId == split.id || activeSplitId == split.id
        let handleWidth = split.axis == .horizontal ? CGFloat(24) : split.region.width * canvas.width
        let handleHeight = split.axis == .horizontal ? split.region.height * canvas.height : CGFloat(24)
        let offsetX = split.axis == .horizontal ? boundary.x - handleWidth / 2 : canvas.minX + split.region.minX * canvas.width
        let offsetY = split.axis == .horizontal ? canvas.minY + split.region.minY * canvas.height : boundary.y - handleHeight / 2

        ZStack {
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())

            Capsule()
                .fill(isEmphasized ? Color.white : Color.cyan.opacity(0.78))
                .frame(
                    width: split.axis == .horizontal ? 4 : min(42, max(handleWidth * 0.18, 18)),
                    height: split.axis == .horizontal ? min(42, max(handleHeight * 0.18, 18)) : 4,
                )
                .shadow(color: .black.opacity(0.45), radius: 2)

            Image(systemName: split.axis == .horizontal ? "arrow.left.and.right" : "arrow.up.and.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .padding(4)
                .background(Color.accentColor, in: Circle())
                .opacity(isEmphasized ? 1 : 0.86)
        }
        .frame(width: max(handleWidth, 1), height: max(handleHeight, 1))
        .offset(x: offsetX, y: offsetY)
        .onHover { hovering in
            hoveredSplitId = hovering ? split.id : (hoveredSplitId == split.id ? nil : hoveredSplitId)
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("customLayoutCanvas"))
                .onChanged { value in
                    if activeSplitId == nil {
                        activeSplitId = split.id
                        onResizeBegan()
                    }
                    let ratio: Double = switch split.axis {
                        case .horizontal:
                            Double(
                                (value.location.x - canvas.minX - split.region.minX * canvas.width)
                                    / max(split.region.width * canvas.width, 1),
                            )
                        case .vertical:
                            Double(
                                (value.location.y - canvas.minY - split.region.minY * canvas.height)
                                    / max(split.region.height * canvas.height, 1),
                            )
                    }
                    layout.setSplitRatio(ratio, at: split.path)
                }
                .onEnded { _ in
                    activeSplitId = nil
                    onResizeEnded()
                },
        )
        .help("Drag to resize the tiles on both sides")
        .accessibilityLabel(split.axis == .horizontal ? "Vertical resize divider" : "Horizontal resize divider")
        .accessibilityValue("First region \(Int((split.ratio * 100).rounded())) percent")
    }
}
