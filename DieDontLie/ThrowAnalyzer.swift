import Foundation
import CoreGraphics
import Combine

/// Tracks throw lifecycle and determines pass/fail against a calibrated height threshold.
///
/// Coordinate convention (matches DieTracker):
///   Y = 0.0  → top of screen
///   Y = 1.0  → bottom of screen
/// So "higher" in the real world == smaller Y value.
///
/// `calibrationY` is the normalized Y of the minimum-height line.
/// A throw PASSES if the die's peak Y <= calibrationY (die went above the line).
final class ThrowAnalyzer: ObservableObject {

    // MARK: - Public state

    enum ThrowResult {
        case pass
        case fail
    }

    @Published private(set) var lastResult: ThrowResult?
    @Published private(set) var isTracking = false

    /// Normalized Y of the calibration line. Set by user tap.
    /// nil means not yet calibrated.
    var calibrationY: CGFloat? = nil

    // MARK: - State machine

    private enum State {
        case idle
        case inFlight(peakY: CGFloat, lastSeenY: CGFloat, missedFrames: Int)
    }

    private var state: State = .idle

    /// Frames without a detection before we consider the throw over
    private let maxMissedFrames = 8
    /// Die must move upward by at least this much (in normalized units) to count as a throw
    private let minLiftThreshold: CGFloat = 0.04

    // MARK: - Processing

    /// Call this on every frame, whether a detection occurred or not.
    func process(detection: DieTracker.DetectionResult?) {
        switch state {
        case .idle:
            guard let det = detection else { return }
            // Start tracking — we'll evaluate direction on subsequent frames
            state = .inFlight(peakY: det.normalizedCenter.y,
                              lastSeenY: det.normalizedCenter.y,
                              missedFrames: 0)
            DispatchQueue.main.async { self.isTracking = true }

        case .inFlight(var peakY, let lastSeenY, var missedFrames):
            if let det = detection {
                let y = det.normalizedCenter.y
                // Lower Y = higher on screen = higher in real world
                if y < peakY { peakY = y }
                missedFrames = 0
                state = .inFlight(peakY: peakY, lastSeenY: y, missedFrames: 0)
            } else {
                missedFrames += 1
                state = .inFlight(peakY: peakY, lastSeenY: lastSeenY, missedFrames: missedFrames)

                if missedFrames >= maxMissedFrames {
                    concludeThrow(peakY: peakY, lastSeenY: lastSeenY)
                }
            }
        }
    }

    // MARK: - Private

    private func concludeThrow(peakY: CGFloat, lastSeenY: CGFloat) {
        state = .idle
        DispatchQueue.main.async { self.isTracking = false }

        // Need calibration to judge
        guard let calY = calibrationY else { return }

        // Ignore micro-movements (die sitting still on table)
        // Peak must be meaningfully above the starting region
        // We approximate: the die started near bottom (lastSeenY close to 1.0)
        // and traveled up (peakY significantly less than lastSeenY)
        guard (lastSeenY - peakY) >= minLiftThreshold else { return }

        let passed = peakY <= calY  // peak went above (or to) the threshold line
        let result: ThrowResult = passed ? .pass : .fail

        DispatchQueue.main.async {
            self.lastResult = result
        }
    }

    func reset() {
        state = .idle
        DispatchQueue.main.async {
            self.lastResult = nil
            self.isTracking = false
        }
    }
}
