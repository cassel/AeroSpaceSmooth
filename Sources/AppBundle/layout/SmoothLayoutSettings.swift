import Combine
import Foundation

enum SmoothLayoutStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case manual
    case fullscreen
    case columns
    case rows
    case dwindle
    case verticalPairs = "vertical-pairs"
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
            case .manual: "Custom"
            case .fullscreen: "Fullscreen"
            case .columns: "Columns"
            case .rows: "Rows"
            case .dwindle: "Dwindle"
            case .verticalPairs: "Vertical Pairs"
            case .grid: "Grid"
        }
    }

    var detail: String {
        switch self {
            case .manual: "Uses the visual layout saved for this monitor and window count."
            case .fullscreen: "One window fills the entire usable area."
            case .columns: "Windows appear side by side with equal widths."
            case .rows: "Windows are stacked with equal heights."
            case .dwindle: "A large primary window with a tail alternating right and down."
            case .verticalPairs: "Stacked rows containing up to two windows each."
            case .grid: "A balanced grid of rows and columns."
        }
    }

    static func available(for windowCount: Int) -> [SmoothLayoutStyle] {
        windowCount == 1
            ? [.fullscreen, .manual]
            : [.dwindle, .verticalPairs, .grid, .columns, .rows, .manual]
    }
}

struct SmoothMonitorLayoutProfile: Codable, Equatable, Identifiable, Sendable {
    static let configuredWindowCount = 10

    var monitorName: String
    var enabled: Bool
    var tileLimit: Int
    var styles: [SmoothLayoutStyle]
    var customLayouts: [String: SmoothCustomLayoutBlueprint]

    var id: String { monitorName }

    func style(for windowCount: Int) -> SmoothLayoutStyle {
        let index = min(max(windowCount, 1), Self.configuredWindowCount) - 1
        return normalized.styles[index]
    }

    func customLayout(for windowCount: Int) -> SmoothCustomLayoutBlueprint? {
        guard let layout = customLayouts[String(min(max(windowCount, 1), Self.configuredWindowCount))] else {
            return nil
        }
        return layout.windowCount == windowCount && layout.isValid ? layout : nil
    }

    var normalized: SmoothMonitorLayoutProfile {
        var result = self
        result.tileLimit = min(max(result.tileLimit, 1), Self.configuredWindowCount)
        let fallback = styles.last ?? .dwindle
        if result.styles.count < Self.configuredWindowCount {
            result.styles += Array(
                repeating: fallback,
                count: Self.configuredWindowCount - result.styles.count,
            )
        } else if result.styles.count > Self.configuredWindowCount {
            result.styles = Array(result.styles.prefix(Self.configuredWindowCount))
        }
        result.customLayouts = result.customLayouts.filter { key, layout in
            Int(key) == layout.windowCount && layout.isValid
        }
        return result
    }

    static func defaultProfile(monitorName: String, isHorizontal: Bool) -> SmoothMonitorLayoutProfile {
        SmoothMonitorLayoutProfile(
            monitorName: monitorName,
            enabled: true,
            tileLimit: monitorName == "Built-in Retina Display" ? 5 : 6,
            styles: isHorizontal
                ? [.fullscreen, .columns] + Array(repeating: .dwindle, count: configuredWindowCount - 2)
                : [.fullscreen, .rows] + Array(repeating: .verticalPairs, count: configuredWindowCount - 2),
            customLayouts: [:],
        )
    }

    init(
        monitorName: String,
        enabled: Bool,
        tileLimit: Int = 6,
        styles: [SmoothLayoutStyle],
        customLayouts: [String: SmoothCustomLayoutBlueprint] = [:],
    ) {
        self.monitorName = monitorName
        self.enabled = enabled
        self.tileLimit = tileLimit
        self.styles = styles
        self.customLayouts = customLayouts
    }

    private enum CodingKeys: String, CodingKey {
        case monitorName
        case enabled
        case tileLimit
        case styles
        case customLayouts
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        monitorName = try values.decode(String.self, forKey: .monitorName)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        tileLimit = try values.decodeIfPresent(Int.self, forKey: .tileLimit) ?? 6
        styles = try values.decodeIfPresent([SmoothLayoutStyle].self, forKey: .styles) ?? []
        customLayouts = try values.decodeIfPresent([String: SmoothCustomLayoutBlueprint].self, forKey: .customLayouts) ?? [:]
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(monitorName, forKey: .monitorName)
        try values.encode(enabled, forKey: .enabled)
        try values.encode(tileLimit, forKey: .tileLimit)
        try values.encode(styles, forKey: .styles)
        try values.encode(customLayouts, forKey: .customLayouts)
    }
}

@MainActor
final class SmoothLayoutSettingsStore: ObservableObject {
    static let shared = SmoothLayoutSettingsStore()

    private static let defaultsKey = "AeroSpaceSmooth.monitor-layout-profiles.v1"
    private static let customSelectionRepairKey = "AeroSpaceSmooth.custom-layout-selection-repair.v1"
    private let defaults: UserDefaults

    @Published private(set) var profiles: [String: SmoothMonitorLayoutProfile]
    @Published private(set) var monitorConfigurationRevision = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        profiles = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([String: SmoothMonitorLayoutProfile].self, from: $0) }
            ?? [:]
        profiles = profiles.mapValues(\.normalized)
        repairCustomLayoutSelectionsIfNeeded()
    }

    func profile(for monitor: MonitorInfo) -> SmoothMonitorLayoutProfile {
        if let profile = profiles[monitor.name] { return profile.normalized }
        let profile = SmoothMonitorLayoutProfile.defaultProfile(
            monitorName: monitor.name,
            isHorizontal: monitor.width >= monitor.height,
        )
        profiles[monitor.name] = profile
        persist()
        return profile
    }

    func profile(named monitorName: String, isHorizontal: Bool) -> SmoothMonitorLayoutProfile {
        profiles[monitorName]
            ?? SmoothMonitorLayoutProfile.defaultProfile(
                monitorName: monitorName,
                isHorizontal: isHorizontal,
            )
    }

    func setEnabled(_ enabled: Bool, monitorName: String, isHorizontal: Bool) {
        var profile = profile(named: monitorName, isHorizontal: isHorizontal)
        profile.enabled = enabled
        profiles[monitorName] = profile.normalized
        didChangeLayoutSettings()
    }

    func setTileLimit(_ tileLimit: Int, monitorName: String, isHorizontal: Bool) {
        var profile = profile(named: monitorName, isHorizontal: isHorizontal)
        profile.tileLimit = tileLimit
        profiles[monitorName] = profile.normalized
        didChangeLayoutSettings()
    }

    func setStyle(_ style: SmoothLayoutStyle, windowCount: Int, monitorName: String, isHorizontal: Bool) {
        var profile = profile(named: monitorName, isHorizontal: isHorizontal).normalized
        let index = min(max(windowCount, 1), SmoothMonitorLayoutProfile.configuredWindowCount) - 1
        let previousStyle = profile.styles[index]
        profile.styles[index] = style
        if style == .manual, profile.customLayout(for: windowCount) == nil {
            profile.customLayouts[String(windowCount)] = .preset(
                style: previousStyle == .manual ? .dwindle : previousStyle,
                windowCount: windowCount,
                monitorIsHorizontal: isHorizontal,
            )
        }
        profiles[monitorName] = profile
        didChangeLayoutSettings()
    }

    func setCustomLayout(
        _ layout: SmoothCustomLayoutBlueprint,
        windowCount: Int,
        monitorName: String,
        isHorizontal: Bool,
    ) {
        guard layout.windowCount == windowCount, layout.isValid else { return }
        var profile = profile(named: monitorName, isHorizontal: isHorizontal).normalized
        let index = min(max(windowCount, 1), SmoothMonitorLayoutProfile.configuredWindowCount) - 1
        profile.customLayouts[String(windowCount)] = layout
        profile.styles[index] = .manual
        profiles[monitorName] = profile
        didChangeLayoutSettings()
    }

    func resetProfile(monitorName: String, isHorizontal: Bool) {
        profiles[monitorName] = .defaultProfile(monitorName: monitorName, isHorizontal: isHorizontal)
        didChangeLayoutSettings()
    }

    func monitorsDidChange(_ monitors: [MonitorInfo]) {
        // NSScreen indices are temporary and can change every time a display is
        // disconnected. Profiles are keyed by the stable display name, so make
        // sure every reconnected monitor is matched before refreshing the UI.
        for monitor in monitors {
            _ = profile(for: monitor)
        }
        monitorConfigurationRevision &+= 1
        invalidateSmoothWorkspaceLayoutSnapshots()
    }

    private func didChangeLayoutSettings() {
        persist()
        // Reconciliation compares the selected style with its last snapshot,
        // so keeping that snapshot lets a transition to Manual distinguish an
        // auto-fullscreen window from a fullscreen choice made by the user.
        scheduleCancellableCompleteRefreshSession(.menuBarButton)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// Early versions of the visual editor could persist the blueprint while a
    /// stale SwiftUI Picker binding immediately restored the previous preset.
    /// Repair those profiles once, while still allowing the user to switch away
    /// from Custom later without deleting the saved design.
    private func repairCustomLayoutSelectionsIfNeeded() {
        guard !defaults.bool(forKey: Self.customSelectionRepairKey) else { return }
        for monitorName in profiles.keys {
            var profile = profiles[monitorName].orDie().normalized
            for key in profile.customLayouts.keys {
                guard let windowCount = Int(key),
                      (1 ... SmoothMonitorLayoutProfile.configuredWindowCount).contains(windowCount)
                else { continue }
                profile.styles[windowCount - 1] = .manual
            }
            profiles[monitorName] = profile
        }
        persist()
        defaults.set(true, forKey: Self.customSelectionRepairKey)
    }

    func replaceProfilesForTests(
        _ profiles: [String: SmoothMonitorLayoutProfile],
        invalidateSnapshots: Bool = true,
    ) {
        self.profiles = profiles.mapValues(\.normalized)
        if invalidateSnapshots {
            invalidateSmoothWorkspaceLayoutSnapshots()
        }
    }
}
