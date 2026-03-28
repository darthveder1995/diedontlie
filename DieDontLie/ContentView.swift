import SwiftUI
import AVFoundation

struct ContentView: View {

    @StateObject private var viewModel = GameViewModel()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // Camera preview fills screen
            CameraPreviewView(session: viewModel.cameraManager.captureSession)
                .ignoresSafeArea()

            // Die detection dot
            if let center = viewModel.detectedCenter {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .background(Circle().fill(Color.white.opacity(0.25)))
                    .frame(width: 24, height: 24)
                    .position(
                        x: center.x * UIScreen.main.bounds.width,
                        y: center.y * UIScreen.main.bounds.height
                    )
                    .animation(.easeOut(duration: 0.05), value: center)
            }

            // Calibration line
            if let calY = viewModel.calibrationY {
                CalibrationLineView(normalizedY: calY)
            }

            // Tap-to-calibrate hint
            if viewModel.calibrationY == nil {
                VStack {
                    Spacer()
                    Text("Tap to set minimum height line")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.bottom, 120)
                }
            }

            // Throw result banner
            if let result = viewModel.throwResult {
                ThrowResultBanner(result: result)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Top bar
            VStack {
                HStack {
                    if viewModel.calibrationY != nil {
                        Button {
                            viewModel.clearCalibration()
                        } label: {
                            Label("Recalibrate", systemImage: "scope")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    Spacer()
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                .padding()
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { location in
            viewModel.setCalibration(tapLocation: location)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(viewModel: viewModel)
        }
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }
}

// MARK: - Calibration line overlay

private struct CalibrationLineView: View {
    let normalizedY: CGFloat

    var body: some View {
        GeometryReader { geo in
            let y = normalizedY * geo.size.height
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.yellow.opacity(0.85))
                    .frame(height: 2)
                    .offset(y: y)

                Text("MIN HEIGHT")
                    .font(.caption2.bold())
                    .foregroundColor(.yellow)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                    .offset(x: 12, y: y - 18)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Throw result banner

private struct ThrowResultBanner: View {
    let result: ThrowAnalyzer.ThrowResult

    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: result == .pass ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.title)
                Text(result == .pass ? "GOOD THROW" : "TOO LOW!")
                    .font(.title2.bold())
            }
            .foregroundColor(result == .pass ? .green : .red)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.top, 60)
            Spacer()
        }
    }
}

// MARK: - UIKit camera preview wrapper

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
