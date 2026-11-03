import MediaPlayer
import SwiftUI
import UIKit

// MARK: - KimaVolumeControl
//
// System-volume control. iOS publishes no volume setter: the only write path is MPVolumeView's own
// slider, so this shows the real MPVolumeView — Apple's documented volume control — inside the
// player's layout, styled through its public image setters (setMinimumVolumeSliderImage /
// setMaximumVolumeSliderImage / setVolumeThumbImage), never subclassed. Only the slider's value
// is touched, for mute.
//
// Apple's documentation notes the simulator cannot set volume: dragging the slider and the mute
// toggle are only exercisable on a device.
//
// While dragging, the local value leads and KVO echoes are dropped (~0.4 s after release) so they
// don't fight the finger.

struct KimaVolumeControl: View {

    @State private var volume: Float = AVAudioSession.sharedInstance().outputVolume
    /// True while a finger owns the slider (suppresses KVO echo).
    @State private var isDragging = false
    /// Volume to restore on unmute (0 → restore 50%).
    @State private var lastAudible: Float = {
        let v = AVAudioSession.sharedInstance().outputVolume
        return v > 0 ? v : 0.5
    }()

    /// Keeps the outputVolume KVO observation alive for the view's lifetime.
    @State private var volumeObservation: NSKeyValueObservation?

    var body: some View {
        HStack(spacing: KimaSpacing.sm) {
            Button(action: toggleMute) {
                Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(KimaColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(volume == 0 ? "unmute" : "mute")

            SystemVolumeSlider(value: $volume, isDragging: $isDragging)
                .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
                .accessibilityLabel("volume")
                .accessibilityValue("\(Int(volume * 100)) percent")
        }
        .onAppear(perform: startObservingSystemVolume)
        .onDisappear { volumeObservation = nil }
    }

    /// KVO on the read-only outputVolume: hardware buttons, Control Center and
    /// Siri changes keep the UI truthful while this control is on screen.
    private func startObservingSystemVolume() {
        guard volumeObservation == nil else { return }
        volumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { _, change in
            guard let v = change.newValue else { return }
            Task { @MainActor in
                guard !isDragging else { return }   // our own write echoing back
                volume = Float(v)
                if v > 0 { lastAudible = Float(v) }
            }
        }
    }

    private func toggleMute() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if volume > 0 {
            lastAudible = volume
            volume = 0
        } else {
            volume = lastAudible
        }
    }
}

// MARK: - SystemVolumeSlider

/// The system volume slider, presented by MPVolumeView itself. Its value IS the system output
/// volume: reading it tracks the hardware buttons, writing it sets the level. Styling comes from
/// MPVolumeView's public image setters, matching the web control: thin tracks, brand fill.
private struct SystemVolumeSlider: UIViewRepresentable {
    @Binding var value: Float
    @Binding var isDragging: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 200, height: 24))
        view.showsRouteButton = false      // AirPlay has its own control (AirPlayRoutePicker)
        view.showsVolumeSlider = true
        view.setMinimumVolumeSliderImage(VolumeArt.track(UIColor(KimaColor.brand)), for: .normal)
        view.setMaximumVolumeSliderImage(VolumeArt.track(UIColor(KimaColor.hairline)), for: .normal)
        view.setVolumeThumbImage(VolumeArt.thumb(UIColor(KimaColor.brand)), for: .normal)

        // The write path for mute, and the source of the value SwiftUI displays. Held weakly: it is
        // MPVolumeView's subview, created and laid out by MPVolumeView.
        if let slider = view.subviews.first(where: { $0 is UISlider }) as? UISlider {
            slider.value = value
            slider.addTarget(context.coordinator,
                             action: #selector(Coordinator.draggingChanged(_:for:)),
                             for: [.touchDown, .touchDragInside, .touchUpInside, .touchUpOutside, .touchCancel])
            context.coordinator.slider = slider
        }
        context.coordinator.volumeView = view
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        // Programmatic changes (mute toggle, KVO) into the slider — without fighting the finger.
        guard let slider = context.coordinator.slider, !context.coordinator.dragging else { return }
        if abs(slider.value - value) > 0.005 { slider.value = value }
    }

    final class Coordinator: NSObject {
        let parent: SystemVolumeSlider
        weak var slider: UISlider?
        var volumeView: MPVolumeView?
        var dragging = false
        private var releaseTimer: Timer?

        init(_ parent: SystemVolumeSlider) { self.parent = parent }

        @objc func draggingChanged(_ sender: UISlider, for event: UIControl.Event) {
            // UISlider has no `currentEvent` in the SDK — the action
            // carries its own triggering event instead.
            switch event {
            case .touchDown, .touchDragInside:
                dragging = true
                parent.isDragging = true
                releaseTimer?.invalidate()
            case .touchUpInside, .touchUpOutside, .touchCancel:
                // Keep suppressing KVO echoes briefly after release.
                releaseTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
                    self?.dragging = false
                    self?.parent.isDragging = false
                }
            default:
                break
            }
            parent.value = Float(sender.value)
        }
    }
}

// MARK: - VolumeArt

/// Track and thumb images for MPVolumeView's public styling hooks. Track images are stretched by
/// the slider, so a short rounded capsule tiles into a continuous thin track.
private enum VolumeArt {
    static func track(_ color: UIColor, thickness: CGFloat = 3) -> UIImage {
        let size = CGSize(width: 12, height: thickness)
        return UIGraphicsImageRenderer(size: size).image { _ in
            color.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size),
                         cornerRadius: thickness / 2).fill()
        }
    }

    static func thumb(_ color: UIColor, diameter: CGFloat = 14) -> UIImage {
        let size = CGSize(width: diameter, height: diameter)
        return UIGraphicsImageRenderer(size: size).image { _ in
            color.setFill()
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).fill()
        }
    }
}
