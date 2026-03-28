import SwiftUI

struct SettingsView: View {

    @ObservedObject var viewModel: GameViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Die Color")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                            ForEach(DieColorOption.allCases) { option in
                                ColorSwatch(
                                    option: option,
                                    isSelected: viewModel.selectedColor == option
                                ) {
                                    viewModel.selectedColor = option
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Detection")
                }

                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Height Threshold")
                            Text(viewModel.calibrationY.map {
                                String(format: "Set at %.0f%% from top", $0 * 100)
                            } ?? "Not set")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        Spacer()
                        if viewModel.calibrationY != nil {
                            Button("Clear", role: .destructive) {
                                viewModel.clearCalibration()
                            }
                        }
                    }

                    Text("Tap anywhere on the camera view to set the minimum height line. Throws whose peak stays below this line trigger the foul alert.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Calibration")
                }

                Section {
                    LabeledContent("Detection", value: "HSV color blob tracking")
                    LabeledContent("Analysis", value: "Real-time, per-frame")
                    LabeledContent("Camera must be", value: "Stationary during play")
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct ColorSwatch: View {
    let option: DieColorOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Circle()
                    .fill(option.swiftUIColor)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 3)
                    )
                Text(option.displayName)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}
