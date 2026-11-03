import AVKit
import SwiftUI

// MARK: - AirPlayRoutePicker
// UIViewRepresentable wrapping AVRoutePickerView with Kima tokens; `prioritizesVideoDevices = false` lists audio
// receivers first. Sized like PlayerSecondaryButton (22 pt icon, 48 pt tall); the 44 pt width gives a valid tap
// target since the UIKit button fills its bounds.

// MARK: - RoutePickerRepresentable (UIKit bridge)

/// Minimal UIViewRepresentable for AVRoutePickerView. All tap handling is owned by AVKit.
private struct RoutePickerRepresentable: UIViewRepresentable {
    /// The player's "on" colour (the track colour) while audio goes to another device.
    let onColour: Color

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        picker.tintColor = UIColor(KimaColor.textMuted)
        picker.activeTintColor = UIColor(onColour)
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.activeTintColor = UIColor(onColour)
    }
}

// MARK: - AirPlayRoutePicker (SwiftUI)

/// Secondary-control-style AirPlay button: system route-picker icon above "AIRPLAY" label.
/// Drop-in peer of PlayerSecondaryButton inside the musicSecondaryCluster HStack.
struct AirPlayRoutePicker: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: KimaSpacing.xs) {
            RoutePickerRepresentable(onColour: env.accent.color)
                .frame(width: 44, height: 22)

            Text("AirPlay")
                .font(KimaType.metaStrong)
                .tracking(0.1)
                .foregroundStyle(KimaColor.textMuted)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .accessibilityLabel("audio output (AirPlay, Bluetooth)")
    }
}
