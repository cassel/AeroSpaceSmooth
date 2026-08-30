import AppKit

struct LayoutFrameTarget: Equatable {
    let window: Window
    let topLeft: CGPoint?
    let size: CGSize?

    static func == (lhs: LayoutFrameTarget, rhs: LayoutFrameTarget) -> Bool {
        lhs.window.windowId == rhs.window.windowId &&
            lhs.topLeft == rhs.topLeft &&
            lhs.size == rhs.size
    }
}

@MainActor
final class LayoutTransaction {
    private(set) var targets: [UInt32: LayoutFrameTarget] = [:]

    func setFrame(_ window: Window, _ topLeft: CGPoint?, _ size: CGSize?) {
        targets[window.windowId] = LayoutFrameTarget(window: window, topLeft: topLeft, size: size)
    }
}

private struct AnimatedLayoutFrame {
    let target: LayoutFrameTarget
    let start: Rect
    let end: Rect
}

@MainActor
final class LayoutAnimator {
    static let shared = LayoutAnimator()

    private var animationTask: Task<Void, Never>?
    private var activeTargets: [UInt32: LayoutFrameTarget]?
    private var generation: UInt = 0

    private init() {}

    func apply(_ transaction: LayoutTransaction, animated: Bool = true) {
        let targets = transaction.targets
        guard !targets.isEmpty else {
            generation &+= 1
            animationTask?.cancel()
            animationTask = nil
            activeTargets = nil
            return
        }

        // A light command is followed by a complete refresh. Both calculate the same
        // frames, so don't restart an animation that is already heading there.
        if animated && activeTargets == targets { return }

        generation &+= 1
        let currentGeneration = generation
        animationTask?.cancel()
        activeTargets = targets

        let durationMs = config.layoutAnimationDurationMs
        let shouldAnimate = animated &&
            !isStartup &&
            durationMs > 0 &&
            !(config.layoutAnimationRespectReduceMotion && NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)

        guard shouldAnimate else {
            applyImmediately(targets.values)
            activeTargets = nil
            animationTask = nil
            return
        }

        animationTask = Task.startUnstructured { @MainActor [weak self] in
            guard let self else { return }
            await animate(Array(targets.values), durationMs: durationMs)
            if generation == currentGeneration {
                activeTargets = nil
                animationTask = nil
            }
        }
    }

    private func animate(_ targets: [LayoutFrameTarget], durationMs: Int) async {
        var animatedFrames: [AnimatedLayoutFrame] = []

        for target in targets {
            guard !Task.isCancelled else { return }
            guard let start = try? await target.window.getAxRect(.cancellable) else {
                target.window.setAxFrame(target.topLeft, target.size)
                continue
            }

            let end = Rect(
                topLeftX: target.topLeft?.x ?? start.topLeftX,
                topLeftY: target.topLeft?.y ?? start.topLeftY,
                width: target.size?.width ?? start.width,
                height: target.size?.height ?? start.height,
            )

            guard !framesAreEffectivelyEqual(start, end) else { continue }

            // Cross-monitor and workspace transitions should not travel through other
            // desktops. They snap to their destination; only local reflows animate.
            let destinationMonitor = end.center.monitorApproximation
            guard destinationMonitor.rect.contains(start.center) else {
                target.window.setAxFrame(target.topLeft, target.size)
                continue
            }

            animatedFrames.append(AnimatedLayoutFrame(target: target, start: start, end: end))
        }

        guard !animatedFrames.isEmpty, !Task.isCancelled else { return }

        let duration = Double(durationMs) / 1000
        let startedAt = ProcessInfo.processInfo.systemUptime

        while !Task.isCancelled {
            let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
            let linearProgress = min(max(elapsed / duration, 0), 1)
            let easedProgress = easeOutCubic(linearProgress)

            for frame in animatedFrames {
                let rect = interpolate(from: frame.start, to: frame.end, progress: easedProgress)
                frame.target.window.setAxFrame(rect.topLeftCorner, rect.size)
            }

            if linearProgress >= 1 { break }
            try? await Task.sleep(for: .milliseconds(16))
        }

        guard !Task.isCancelled else { return }
        for frame in animatedFrames {
            frame.target.window.setAxFrame(frame.target.topLeft, frame.target.size)
        }
    }

    private func applyImmediately(_ targets: Dictionary<UInt32, LayoutFrameTarget>.Values) {
        for target in targets {
            target.window.setAxFrame(target.topLeft, target.size)
        }
    }
}

private func easeOutCubic(_ progress: Double) -> Double {
    1 - pow(1 - progress, 3)
}

private func interpolate(from start: Rect, to end: Rect, progress: Double) -> Rect {
    func value(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
        start + (end - start) * CGFloat(progress)
    }

    return Rect(
        topLeftX: value(start.topLeftX, end.topLeftX),
        topLeftY: value(start.topLeftY, end.topLeftY),
        width: value(start.width, end.width),
        height: value(start.height, end.height),
    )
}

private func framesAreEffectivelyEqual(_ lhs: Rect, _ rhs: Rect) -> Bool {
    abs(lhs.topLeftX - rhs.topLeftX) < 0.5 &&
        abs(lhs.topLeftY - rhs.topLeftY) < 0.5 &&
        abs(lhs.width - rhs.width) < 0.5 &&
        abs(lhs.height - rhs.height) < 0.5
}
