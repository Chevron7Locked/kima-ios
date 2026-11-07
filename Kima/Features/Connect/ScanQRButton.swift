import SwiftUI

/// Quiet text button that opens the link-a-device sheet on the scanner.
struct ScanQRButton: View {
    var body: some View {
        Button {
            DevicePairingRouter.shared.request(.scan)
        } label: {
            Label("scan qr code", systemImage: "qrcode.viewfinder")
                .font(KimaType.caption)
                .foregroundStyle(KimaColor.textSecondary)
                .frame(maxWidth: .infinity, minHeight: KimaLayout.minTouchTarget)
        }
        .accessibilityLabel("scan qr code")
        .accessibilityHint("scan the code from link a device on the kima website")
    }
}
