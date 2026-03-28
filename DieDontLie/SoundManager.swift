import AVFoundation

final class SoundManager {

    private var player: AVAudioPlayer?

    init() {
        configureAudioSession()
    }

    /// Play a loud buzzer alert (low-throw ruling).
    func playFoulAlert() {
        // Try bundled audio file first, fall back to system sound
        if let url = Bundle.main.url(forResource: "foul", withExtension: "mp3") ??
                     Bundle.main.url(forResource: "foul", withExtension: "wav") {
            playFile(url: url)
        } else {
            playSystemBuzzer()
        }
    }

    /// Play a short pass chime (valid throw).
    func playPassSound() {
        if let url = Bundle.main.url(forResource: "pass", withExtension: "mp3") ??
                     Bundle.main.url(forResource: "pass", withExtension: "wav") {
            playFile(url: url)
        }
        // Silent on pass if no file — alert only matters for fouls
    }

    // MARK: - Private

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[SoundManager] Audio session setup failed: \(error)")
        }
    }

    private func playFile(url: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.volume = 1.0
            player?.play()
        } catch {
            print("[SoundManager] Failed to play \(url.lastPathComponent): \(error)")
            playSystemBuzzer()
        }
    }

    private func playSystemBuzzer() {
        // System sound 1005 is a short buzz/alert — works without an audio asset
        AudioServicesPlaySystemSound(1005)
        // Play it twice for emphasis
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            AudioServicesPlaySystemSound(1005)
        }
    }
}

// AudioServicesPlaySystemSound is in AudioToolbox
import AudioToolbox
