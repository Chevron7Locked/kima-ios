import SwiftUI
import UIKit

/// The system share sheet for one URL (copy, messages, mail…).
struct KimaShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension View {
    /// Shows the system share sheet for `url` while it is non-nil; closing the sheet sets it back to nil.
    func kimaShareSheet(url: Binding<URL?>) -> some View {
        sheet(isPresented: Binding(get: { url.wrappedValue != nil }, set: { if !$0 { url.wrappedValue = nil } })) {
            if let shared = url.wrappedValue {
                KimaShareSheet(url: shared)
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
    }
}
