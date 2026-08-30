import CoreGraphics
import Foundation

enum SmoothSplitAxis: String, Codable, CaseIterable, Identifiable, Sendable {
    case horizontal
    case vertical

    var id: String { rawValue }

    var opposite: SmoothSplitAxis { self == .horizontal ? .vertical : .horizontal }
}

enum SmoothCustomLayoutValidationError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case invalidWindowCount(Int)
    case invalidRatio(Double)
    case invalidSlots(expected: [Int], actual: [Int])

    var errorDescription: String? {
        switch self {
            case .unsupportedSchema(let version): "Unsupported custom layout schema version: \(version)."
            case .invalidWindowCount(let count): "Custom layouts require between 1 and 10 windows; received \(count)."
            case .invalidRatio(let ratio): "Split ratio \(ratio) is outside the supported 0.10–0.90 range."
            case .invalidSlots(let expected, let actual):
                "Custom layout slots must be \(expected); received \(actual)."
        }
    }
}

indirect enum SmoothCustomLayoutNode: Equatable, Sendable {
    case window(slot: Int)
    case split(
        axis: SmoothSplitAxis,
        ratio: Double,
        first: SmoothCustomLayoutNode,
        second: SmoothCustomLayoutNode,
    )

    var slots: [Int] {
        switch self {
            case .window(let slot): [slot]
            case .split(_, _, let first, let second): first.slots + second.slots
        }
    }

    func contains(slot: Int) -> Bool { slots.contains(slot) }

    func frames(in region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> [Int: CGRect] {
        switch self {
            case .window(let slot):
                return [slot: region]
            case .split(let axis, let ratio, let first, let second):
                let firstRegion: CGRect
                let secondRegion: CGRect
                switch axis {
                    case .horizontal:
                        firstRegion = CGRect(
                            x: region.minX,
                            y: region.minY,
                            width: region.width * ratio,
                            height: region.height,
                        )
                        secondRegion = CGRect(
                            x: firstRegion.maxX,
                            y: region.minY,
                            width: region.width - firstRegion.width,
                            height: region.height,
                        )
                    case .vertical:
                        firstRegion = CGRect(
                            x: region.minX,
                            y: region.minY,
                            width: region.width,
                            height: region.height * ratio,
                        )
                        secondRegion = CGRect(
                            x: region.minX,
                            y: firstRegion.maxY,
                            width: region.width,
                            height: region.height - firstRegion.height,
                        )
                }
                return first.frames(in: firstRegion).merging(second.frames(in: secondRegion)) { _, rhs in rhs }
        }
    }

    func parentSplit(of slot: Int) -> (axis: SmoothSplitAxis, ratio: Double)? {
        switch self {
            case .window:
                return nil
            case .split(let axis, let ratio, let first, let second):
                if first.isWindow(slot: slot) || second.isWindow(slot: slot) {
                    return (axis, ratio)
                }
                return first.contains(slot: slot) ? first.parentSplit(of: slot) : second.parentSplit(of: slot)
        }
    }

    func swappingSlots(_ lhs: Int, _ rhs: Int) -> SmoothCustomLayoutNode {
        switch self {
            case .window(let slot):
                if slot == lhs { return .window(slot: rhs) }
                if slot == rhs { return .window(slot: lhs) }
                return self
            case .split(let axis, let ratio, let first, let second):
                return .split(
                    axis: axis,
                    ratio: ratio,
                    first: first.swappingSlots(lhs, rhs),
                    second: second.swappingSlots(lhs, rhs),
                )
        }
    }

    func splittingWindow(slot: Int, newSlot: Int, axis: SmoothSplitAxis) -> SmoothCustomLayoutNode {
        switch self {
            case .window(let ownSlot) where ownSlot == slot:
                return .split(
                    axis: axis,
                    ratio: 0.5,
                    first: .window(slot: ownSlot),
                    second: .window(slot: newSlot),
                )
            case .window:
                return self
            case .split(let currentAxis, let ratio, let first, let second):
                return .split(
                    axis: currentAxis,
                    ratio: ratio,
                    first: first.splittingWindow(slot: slot, newSlot: newSlot, axis: axis),
                    second: second.splittingWindow(slot: slot, newSlot: newSlot, axis: axis),
                )
        }
    }

    func updatingParent(
        of slot: Int,
        _ transform: (SmoothSplitAxis, Double, SmoothCustomLayoutNode, SmoothCustomLayoutNode) -> SmoothCustomLayoutNode,
    ) -> SmoothCustomLayoutNode {
        switch self {
            case .window:
                return self
            case .split(let axis, let ratio, let first, let second):
                if first.isWindow(slot: slot) || second.isWindow(slot: slot) {
                    return transform(axis, ratio, first, second)
                }
                if first.contains(slot: slot) {
                    return .split(
                        axis: axis,
                        ratio: ratio,
                        first: first.updatingParent(of: slot, transform),
                        second: second,
                    )
                }
                if second.contains(slot: slot) {
                    return .split(
                        axis: axis,
                        ratio: ratio,
                        first: first,
                        second: second.updatingParent(of: slot, transform),
                    )
                }
                return self
        }
    }

    private func isWindow(slot: Int) -> Bool {
        if case .window(let ownSlot) = self { return ownSlot == slot }
        return false
    }
}

extension SmoothCustomLayoutNode: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case slot
        case axis
        case ratio
        case first
        case second
    }

    private enum Kind: String, Codable {
        case window
        case split
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        switch try values.decode(Kind.self, forKey: .kind) {
            case .window:
                self = .window(slot: try values.decode(Int.self, forKey: .slot))
            case .split:
                self = .split(
                    axis: try values.decode(SmoothSplitAxis.self, forKey: .axis),
                    ratio: try values.decode(Double.self, forKey: .ratio),
                    first: try values.decode(SmoothCustomLayoutNode.self, forKey: .first),
                    second: try values.decode(SmoothCustomLayoutNode.self, forKey: .second),
                )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
            case .window(let slot):
                try values.encode(Kind.window, forKey: .kind)
                try values.encode(slot, forKey: .slot)
            case .split(let axis, let ratio, let first, let second):
                try values.encode(Kind.split, forKey: .kind)
                try values.encode(axis, forKey: .axis)
                try values.encode(ratio, forKey: .ratio)
                try values.encode(first, forKey: .first)
                try values.encode(second, forKey: .second)
        }
    }
}

struct SmoothCustomLayoutBlueprint: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var windowCount: Int
    var root: SmoothCustomLayoutNode

    init(
        schemaVersion: Int = currentSchemaVersion,
        windowCount: Int,
        root: SmoothCustomLayoutNode,
    ) {
        self.schemaVersion = schemaVersion
        self.windowCount = windowCount
        self.root = root
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw SmoothCustomLayoutValidationError.unsupportedSchema(schemaVersion)
        }
        guard (1 ... SmoothMonitorLayoutProfile.configuredWindowCount).contains(windowCount) else {
            throw SmoothCustomLayoutValidationError.invalidWindowCount(windowCount)
        }
        try root.validateRatios()
        let expected = Array(0 ..< windowCount)
        let actual = root.slots.sorted()
        guard actual == expected else {
            throw SmoothCustomLayoutValidationError.invalidSlots(expected: expected, actual: actual)
        }
    }

    var isValid: Bool { (try? validate()) != nil }
    var frames: [Int: CGRect] { root.frames() }

    mutating func swapSlots(_ lhs: Int, _ rhs: Int) {
        guard lhs != rhs, root.contains(slot: lhs), root.contains(slot: rhs) else { return }
        root = root.swappingSlots(lhs, rhs)
    }

    mutating func setParentAxis(_ axis: SmoothSplitAxis, of slot: Int) {
        root = root.updatingParent(of: slot) { _, ratio, first, second in
            .split(axis: axis, ratio: ratio, first: first, second: second)
        }
    }

    mutating func setParentRatio(_ ratio: Double, of slot: Int) {
        let ratio = min(max(ratio, 0.10), 0.90)
        root = root.updatingParent(of: slot) { axis, _, first, second in
            .split(axis: axis, ratio: ratio, first: first, second: second)
        }
    }

    mutating func reverseParent(of slot: Int) {
        root = root.updatingParent(of: slot) { axis, ratio, first, second in
            .split(axis: axis, ratio: 1 - ratio, first: second, second: first)
        }
    }

    static func continuing(
        _ previous: SmoothCustomLayoutBlueprint,
        splitSlot: Int,
        axis: SmoothSplitAxis,
    ) -> SmoothCustomLayoutBlueprint? {
        guard previous.isValid,
              previous.windowCount < SmoothMonitorLayoutProfile.configuredWindowCount,
              previous.root.contains(slot: splitSlot)
        else { return nil }
        return SmoothCustomLayoutBlueprint(
            windowCount: previous.windowCount + 1,
            root: previous.root.splittingWindow(
                slot: splitSlot,
                newSlot: previous.windowCount,
                axis: axis,
            ),
        )
    }

    static func preset(
        style: SmoothLayoutStyle,
        windowCount: Int,
        monitorIsHorizontal: Bool,
    ) -> SmoothCustomLayoutBlueprint {
        let slots = Array(0 ..< max(windowCount, 1))
        let root: SmoothCustomLayoutNode = switch style {
            case .fullscreen:
                windowCount == 1
                    ? .window(slot: 0)
                    : linear(slots.map(SmoothCustomLayoutNode.window), axis: .horizontal)
            case .columns:
                linear(slots.map(SmoothCustomLayoutNode.window), axis: .horizontal)
            case .rows:
                linear(slots.map(SmoothCustomLayoutNode.window), axis: .vertical)
            case .dwindle, .manual:
                dwindle(slots, axis: monitorIsHorizontal ? .horizontal : .vertical)
            case .verticalPairs:
                verticalPairs(slots)
            case .grid:
                grid(slots, monitorIsHorizontal: monitorIsHorizontal)
        }
        return SmoothCustomLayoutBlueprint(windowCount: max(windowCount, 1), root: root)
    }

    static func hybridDwindle(
        windowCount: Int,
        startsAt: Int,
        primaryAxis: SmoothSplitAxis,
    ) -> SmoothCustomLayoutBlueprint {
        let count = min(max(windowCount, 1), SmoothMonitorLayoutProfile.configuredWindowCount)
        guard count >= 3 else {
            return SmoothCustomLayoutBlueprint(
                windowCount: count,
                root: linear(Array(0 ..< count).map(SmoothCustomLayoutNode.window), axis: primaryAxis),
            )
        }

        let start = min(max(startsAt, 3), count)
        let tailStart = start - 2
        let fixed = Array(0 ..< tailStart).map(SmoothCustomLayoutNode.window)
        let tail = dwindle(Array(tailStart ..< count), axis: primaryAxis.opposite)
        return SmoothCustomLayoutBlueprint(
            windowCount: count,
            root: linear(fixed + [tail], axis: primaryAxis),
        )
    }

    private static func linear(_ nodes: [SmoothCustomLayoutNode], axis: SmoothSplitAxis) -> SmoothCustomLayoutNode {
        guard let first = nodes.first else { return .window(slot: 0) }
        guard nodes.count > 1 else { return first }
        return .split(
            axis: axis,
            ratio: 1 / Double(nodes.count),
            first: first,
            second: linear(Array(nodes.dropFirst()), axis: axis),
        )
    }

    private static func dwindle(_ slots: [Int], axis: SmoothSplitAxis) -> SmoothCustomLayoutNode {
        guard let first = slots.first else { return .window(slot: 0) }
        guard slots.count > 1 else { return .window(slot: first) }
        return .split(
            axis: axis,
            ratio: 0.5,
            first: .window(slot: first),
            second: dwindle(Array(slots.dropFirst()), axis: axis.opposite),
        )
    }

    private static func verticalPairs(_ slots: [Int]) -> SmoothCustomLayoutNode {
        let rows = stride(from: 0, to: slots.count, by: 2).map { index in
            linear(Array(slots[index ..< min(index + 2, slots.count)]).map(SmoothCustomLayoutNode.window), axis: .horizontal)
        }
        return linear(rows, axis: .vertical)
    }

    private static func grid(_ slots: [Int], monitorIsHorizontal: Bool) -> SmoothCustomLayoutNode {
        let aspectRatio = monitorIsHorizontal ? 16.0 / 9.0 : 9.0 / 16.0
        let columns = min(slots.count, max(1, Int(ceil(sqrt(Double(slots.count) * aspectRatio)))))
        let rows = stride(from: 0, to: slots.count, by: columns).map { index in
            linear(Array(slots[index ..< min(index + columns, slots.count)]).map(SmoothCustomLayoutNode.window), axis: .horizontal)
        }
        return linear(rows, axis: .vertical)
    }
}

extension SmoothCustomLayoutNode {
    fileprivate func validateRatios() throws {
        switch self {
            case .window:
                return
            case .split(_, let ratio, let first, let second):
                guard (0.10 ... 0.90).contains(ratio) else {
                    throw SmoothCustomLayoutValidationError.invalidRatio(ratio)
                }
                try first.validateRatios()
                try second.validateRatios()
        }
    }
}
