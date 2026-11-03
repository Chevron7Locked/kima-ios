import SwiftUI

// MARK: - Full-screen cover-art lightbox

/// Tap a cover anywhere to open it large on a dark scrim: pinch-zoom, drag-pan, swipe-down / tap-background / ✕ to dismiss.
/// Present via `.fullScreenCover(isPresented:)` with an owned `@State` bool at the call site and dismiss through `onClose`;
/// `@Environment(\.dismiss)` does NOT reliably reset a fullScreenCover binding in this app's nested presentation host.
/// The presenter must re-inject `.appEnvironment(env, toast)` because the embedded `CoverArtImage` reads `AppEnvironment`.
struct CoverImageViewer: View {

    /// Library cover identifier (music). Ignored when `directURL` is non-nil.
    var coverId: String? = nil
    /// Pre-resolved artwork URL (long-form audiobook / podcast). Wins over `coverId`.
    var directURL: URL? = nil
    /// Server-side resize dimension — hero context, so a large value (1024) by default.
    var size: Int = 1024
    /// Optional caption title (e.g. album / track title).
    var title: String? = nil
    /// Optional caption subtitle (e.g. artist name).
    var subtitle: String? = nil
    /// Presenter flips its own `@State` bool false here — see the type doc.
    let onClose: () -> Void

    // MARK: - Interaction state

    @State private var appeared = false
    @State private var zoom: CGFloat = 1
    @State private var committedZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var committedPan: CGSize = .zero
    @State private var dismissOffset: CGFloat = 0

    private let maxZoom: CGFloat = 4
    private let dismissThreshold: CGFloat = 120

    // MARK: - Body

    var body: some View {
        ZStack {
            scrim
            artwork
            caption
            closeButton
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.28)) { appeared = true }
        }
    }

    // MARK: - Scrim (tap-background to dismiss)

    private var scrim: some View {
        KimaColor.base
            .opacity(appeared ? (0.97 - dismissProgress * 0.6) : 0)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { onClose() }
    }

    // MARK: - Artwork (zoom + pan + swipe-to-dismiss)

    private var artwork: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) - KimaSpacing.xl * 2
            CoverArtImage(
                coverId: coverId,
                directURL: directURL,
                size: size,
                cornerRadius: 16,
                accessibilityLabel: title ?? "cover art",
                heroPlaceholder: true
            )
            .frame(width: max(side, 0), height: max(side, 0))
            .shadow(color: .black.opacity(0.6), radius: 32, x: 0, y: 18)
            .scaleEffect(zoom * (appeared ? 1 : 0.92))
            .offset(x: pan.width, y: pan.height + dismissOffset)
            .opacity(appeared ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(dragGesture)
            .onTapGesture(count: 2) { toggleZoom() }
        }
    }

    // MARK: - Caption

    @ViewBuilder
    private var caption: some View {
        if title != nil || subtitle != nil {
            VStack {
                Spacer()
                VStack(spacing: KimaSpacing.xs) {
                    if let title {
                        Text(title)
                            .font(KimaType.headline)
                            .foregroundStyle(KimaColor.textPrimary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(KimaType.caption)
                            .foregroundStyle(KimaColor.textMuted)
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                    }
                }
                .shadow(color: .black.opacity(0.6), radius: 6)
                .padding(.horizontal, KimaSpacing.xl)
                .padding(.bottom, KimaSpacing.xl)
            }
            .opacity(appeared ? (1 - dismissProgress) : 0)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Close disc (top-trailing hairline glass — matches VibeMapView)

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                KimaCloseButton(label: "close", id: "cover-viewer-close", kind: .screen) { onClose() }
            }
            Spacer()
        }
        .padding(.horizontal, KimaSpacing.lg)
        .padding(.top, KimaSpacing.sm)
        .opacity(appeared ? 1 : 0)
    }

    // MARK: - Gestures

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom = min(max(committedZoom * value.magnification, 1), maxZoom)
            }
            .onEnded { _ in
                committedZoom = zoom
                if zoom <= 1 {
                    withAnimation(.spring(duration: 0.3)) {
                        pan = .zero
                        committedPan = .zero
                    }
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if zoom > 1 {
                    // Zoomed → pan the image.
                    pan = CGSize(
                        width: committedPan.width + value.translation.width,
                        height: committedPan.height + value.translation.height
                    )
                } else {
                    // Un-zoomed → track a swipe-to-dismiss (downward).
                    dismissOffset = value.translation.height
                }
            }
            .onEnded { value in
                if zoom > 1 {
                    committedPan = pan
                } else if value.translation.height > dismissThreshold {
                    onClose()
                } else {
                    withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
                        dismissOffset = 0
                    }
                }
            }
    }

    // MARK: - Helpers

    /// 0 → fully open, 1 → dragged a full dismiss distance. Drives scrim + caption fade.
    private var dismissProgress: Double {
        min(1, Double(max(0, dismissOffset)) / 300)
    }

    private func toggleZoom() {
        withAnimation(.spring(duration: 0.32, bounce: 0.15)) {
            if zoom > 1 {
                zoom = 1
                committedZoom = 1
                pan = .zero
                committedPan = .zero
            } else {
                zoom = 2.4
                committedZoom = 2.4
            }
        }
    }
}
