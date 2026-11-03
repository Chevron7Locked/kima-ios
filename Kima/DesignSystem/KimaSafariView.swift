import SafariServices
import SwiftUI

/// A web page in the in-app Safari view. Unlike `openURL`, it never hands the link to an installed app that
/// claims it, so the page always opens as the web page.
struct KimaSafariView: UIViewControllerRepresentable {
    let url: URL
    let onDone: () -> Void

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .close
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) { onDone() }
    }
}

extension View {
    /// Shows `url` full screen in the in-app Safari view while it is non-nil; closing it sets it back to nil and
    /// then calls `onDismiss`.
    func kimaSafari(url: Binding<URL?>, onDismiss: @escaping () -> Void = {}) -> some View {
        fullScreenCover(
            isPresented: Binding(get: { url.wrappedValue != nil }, set: { if !$0 { url.wrappedValue = nil } }),
            onDismiss: onDismiss
        ) {
            if let page = url.wrappedValue {
                KimaSafariView(url: page) { url.wrappedValue = nil }
                    .ignoresSafeArea()
            }
        }
    }
}
