import SwiftUI

@MainActor
struct SmoothCustomLayoutEditorView: View {
    let monitorName: String
    let monitorIsHorizontal: Bool
    let previousLayout: SmoothCustomLayoutBlueprint?
    let onSave: (SmoothCustomLayoutBlueprint) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: SmoothCustomLayoutBlueprint
    @State private var selectedSlot = 0
    @State private var hybridStart: Int
    @State private var primaryAxis: SmoothSplitAxis
    @State private var undoStack: [SmoothCustomLayoutBlueprint] = []
    @State private var redoStack: [SmoothCustomLayoutBlueprint] = []

    init(
        monitorName: String,
        monitorIsHorizontal: Bool,
        layout: SmoothCustomLayoutBlueprint,
        previousLayout: SmoothCustomLayoutBlueprint?,
        onSave: @escaping (SmoothCustomLayoutBlueprint) -> Void,
    ) {
        self.monitorName = monitorName
        self.monitorIsHorizontal = monitorIsHorizontal
        self.previousLayout = previousLayout
        self.onSave = onSave
        _draft = State(initialValue: layout)
        _hybridStart = State(initialValue: min(max(3, layout.windowCount), 4))
        _primaryAxis = State(initialValue: monitorIsHorizontal ? .horizontal : .vertical)
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
                    .frame(width: 310)
            }
            Divider()
            editorFooter
        }
        .frame(minWidth: 900, minHeight: 620)
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
            Text("Select a numbered tile, then edit its parent split.")
                .font(.callout)
                .foregroundStyle(.secondary)
            SmoothCustomLayoutCanvas(layout: draft, selectedSlot: $selectedSlot)
                .aspectRatio(monitorIsHorizontal ? 16 / 9 : 9 / 16, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Label(
                "The preview is isolated. Real windows move only after Save Layout.",
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
        controlSection("Selected Tile \(selectedSlot + 1)", help: "Move changes which logical window occupies this region. Direction, ratio and reverse edit the split directly surrounding the selected tile.") {
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
                    set: { ratio in commit { $0.setParentRatio(ratio, of: selectedSlot) } },
                ),
                in: 0.10 ... 0.90,
                step: 0.05,
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

private struct SmoothCustomLayoutCanvas: View {
    let layout: SmoothCustomLayoutBlueprint
    @Binding var selectedSlot: Int

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
            }
        }
    }
}
