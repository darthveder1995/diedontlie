import SwiftUI
import CoreVideo
import Combine

@MainActor
final class GameViewModel: ObservableObject {

    // MARK: - Published UI state

    @Published private(set) var detectedCenter: CGPoint?
    @Published private(set) var throwResult: ThrowAnalyzer.ThrowResult?
    @Published private(set) var calibrationY: CGFloat?

    // Die color config — persisted in UserDefaults
    @Published var selectedColor: DieColorOption = DieColorOption.load() {
        didSet {
            dieTracker.colorConfig = selectedColor.config
            selectedColor.save()
        }
    }

    // MARK: - Internal objects

    let cameraManager = CameraManager()
    private let dieTracker = DieTracker()
    private let throwAnalyzer = ThrowAnalyzer()
    private let soundManager = SoundManager()

    private var resultClearTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Lifecycle

    init() {
        dieTracker.colorConfig = selectedColor.config
        loadCalibration()

        throwAnalyzer.$lastResult
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] result in
                self?.handleThrowResult(result)
            }
            .store(in: &cancellables)

        cameraManager.delegate = self
    }

    func start() {
        cameraManager.requestPermissionAndStart()
    }

    func stop() {
        cameraManager.stop()
    }

    // MARK: - Calibration

    func setCalibration(tapLocation: CGPoint) {
        let screenHeight = UIScreen.main.bounds.height
        let normalizedY = tapLocation.y / screenHeight
        calibrationY = normalizedY
        throwAnalyzer.calibrationY = normalizedY
        UserDefaults.standard.set(Double(normalizedY), forKey: "calibrationY")
    }

    func clearCalibration() {
        calibrationY = nil
        throwAnalyzer.calibrationY = nil
        UserDefaults.standard.removeObject(forKey: "calibrationY")
    }

    private func loadCalibration() {
        if let stored = UserDefaults.standard.object(forKey: "calibrationY") as? Double {
            calibrationY = CGFloat(stored)
            throwAnalyzer.calibrationY = CGFloat(stored)
        }
    }

    // MARK: - Result handling

    private func handleThrowResult(_ result: ThrowAnalyzer.ThrowResult) {
        withAnimation(.spring(response: 0.3)) {
            throwResult = result
        }

        if result == .fail {
            soundManager.playFoulAlert()
        } else {
            soundManager.playPassSound()
        }

        // Auto-dismiss banner after 2.5 seconds
        resultClearTask?.cancel()
        resultClearTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation { self.throwResult = nil }
        }
    }
}

// MARK: - CameraManagerDelegate

extension GameViewModel: CameraManagerDelegate {
    nonisolated func cameraManager(
        _ manager: CameraManager,
        didOutput pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) {
        let detection = dieTracker.detect(in: pixelBuffer)
        throwAnalyzer.process(detection: detection)

        Task { @MainActor in
            self.detectedCenter = detection?.normalizedCenter
        }
    }
}

// MARK: - Die color options

enum DieColorOption: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, pink

    var id: String { rawValue }

    var displayName: String { rawValue.capitalized }

    var config: DieTracker.ColorConfig {
        switch self {
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .blue:   return .blue
        case .pink:   return .pink
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .blue:   return .blue
        case .pink:   return .pink
        }
    }

    static func load() -> DieColorOption {
        let raw = UserDefaults.standard.string(forKey: "dieColor") ?? "red"
        return DieColorOption(rawValue: raw) ?? .red
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: "dieColor")
    }
}
