import Combine
import Foundation

enum SmoothLayoutStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case fullscreen
    case columns
    case rows
    case dwindle
    case verticalPairs = "vertical-pairs"
    case grid

    var id: String { rawValue }

    var title: String {
        switch self {
            case .fullscreen: "Maximizada"
            case .columns: "Colunas"
            case .rows: "Linhas"
            case .dwindle: "Dwindle"
            case .verticalPairs: "Pares verticais"
            case .grid: "Grade"
        }
    }

    var detail: String {
        switch self {
            case .fullscreen: "Uma janela ocupa toda a area util."
            case .columns: "Janelas lado a lado com larguras iguais."
            case .rows: "Janelas empilhadas com alturas iguais."
            case .dwindle: "Janela principal grande e cauda alternando direita e baixo."
            case .verticalPairs: "Linhas empilhadas, com ate duas janelas por linha."
            case .grid: "Grade balanceada de linhas e colunas."
        }
    }

    static func available(for windowCount: Int) -> [SmoothLayoutStyle] {
        windowCount == 1
            ? [.fullscreen]
            : [.dwindle, .verticalPairs, .grid, .columns, .rows]
    }
}

struct SmoothMonitorLayoutProfile: Codable, Equatable, Identifiable, Sendable {
    static let configuredWindowCount = 10

    var monitorName: String
    var enabled: Bool
    var tileLimit: Int
    var styles: [SmoothLayoutStyle]

    var id: String { monitorName }

    func style(for windowCount: Int) -> SmoothLayoutStyle {
        let index = min(max(windowCount, 1), Self.configuredWindowCount) - 1
        return normalized.styles[index]
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
        )
    }

    init(monitorName: String, enabled: Bool, tileLimit: Int = 6, styles: [SmoothLayoutStyle]) {
        self.monitorName = monitorName
        self.enabled = enabled
        self.tileLimit = tileLimit
        self.styles = styles
    }

    private enum CodingKeys: String, CodingKey {
        case monitorName
        case enabled
        case tileLimit
        case styles
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        monitorName = try values.decode(String.self, forKey: .monitorName)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        tileLimit = try values.decodeIfPresent(Int.self, forKey: .tileLimit) ?? 6
        styles = try values.decodeIfPresent([SmoothLayoutStyle].self, forKey: .styles) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(monitorName, forKey: .monitorName)
        try values.encode(enabled, forKey: .enabled)
        try values.encode(tileLimit, forKey: .tileLimit)
        try values.encode(styles, forKey: .styles)
    }
}

@MainActor
final class SmoothLayoutSettingsStore: ObservableObject {
    static let shared = SmoothLayoutSettingsStore()

    private static let defaultsKey = "AeroSpaceSmooth.monitor-layout-profiles.v1"
    private let defaults: UserDefaults

    @Published private(set) var profiles: [String: SmoothMonitorLayoutProfile]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        profiles = defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode([String: SmoothMonitorLayoutProfile].self, from: $0) }
            ?? [:]
        profiles = profiles.mapValues(\.normalized)
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
        profile.styles[index] = style
        profiles[monitorName] = profile
        didChangeLayoutSettings()
    }

    func resetProfile(monitorName: String, isHorizontal: Bool) {
        profiles[monitorName] = .defaultProfile(monitorName: monitorName, isHorizontal: isHorizontal)
        didChangeLayoutSettings()
    }

    private func didChangeLayoutSettings() {
        persist()
        invalidateSmoothWorkspaceLayoutSnapshots()
        scheduleCancellableCompleteRefreshSession(.menuBarButton)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    func replaceProfilesForTests(_ profiles: [String: SmoothMonitorLayoutProfile]) {
        self.profiles = profiles.mapValues(\.normalized)
        invalidateSmoothWorkspaceLayoutSnapshots()
    }
}
