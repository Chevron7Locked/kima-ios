import SwiftUI
import AVFoundation
import VisionKit

/// Live camera view that reads QR codes. `onCode` gets each code's text and returns true once it has
/// accepted one, which stops the scan. Handles a device with no scanner (the simulator) and a denied camera.
struct QRScannerView: View {
    let onCode: (String) -> Bool

    private enum Access { case checking, ready, denied, unavailable, failed, unsupported }
    @State private var access = Access.checking

    var body: some View {
        switch access {
        case .checking:
            Color.clear.task { await resolveAccess() }
        case .ready:
            ScannerRepresentable(onCode: onCode, onFailure: { access = .failed })
        case .denied:
            VStack(spacing: KimaSpacing.md) {
                Text("camera access is off.")
                    .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
                Button("open settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(KimaType.captionStrong).foregroundStyle(KimaColor.textPrimary)
                .frame(minHeight: KimaLayout.minTouchTarget)
            }
        case .unavailable:
            Text("the camera isn't available right now.")
                .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
                .multilineTextAlignment(.center)
        case .failed:
            Text("couldn't start the camera.")
                .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
                .multilineTextAlignment(.center)
        case .unsupported:
            Text("this device can't scan codes. type the code instead.")
                .font(KimaType.body).foregroundStyle(KimaColor.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private func resolveAccess() async {
        guard DataScannerViewController.isSupported else { access = .unsupported; return }
        var status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            status = AVCaptureDevice.authorizationStatus(for: .video)
        }
        if status == .authorized {
            access = DataScannerViewController.isAvailable ? .ready : .unavailable   // e.g. a Screen Time restriction
        } else {
            access = .denied
        }
    }
}

private struct ScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Bool
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode, onFailure: onFailure) }

    func makeUIViewController(context: Context) -> ScannerHost {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: false,
            isGuidanceEnabled: false,
            isHighlightingEnabled: false
        )
        scanner.delegate = context.coordinator
        return ScannerHost(scanner: scanner, onFailure: onFailure)
    }

    func updateUIViewController(_ host: ScannerHost, context: Context) {
        context.coordinator.onCode = onCode
        context.coordinator.onFailure = onFailure
        host.onFailure = onFailure
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Bool
        var onFailure: () -> Void
        init(onCode: @escaping (String) -> Bool, onFailure: @escaping () -> Void) {
            self.onCode = onCode
            self.onFailure = onFailure
        }

        func dataScanner(_ scanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onFailure()
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for case let .barcode(code) in items {
                guard let payload = code.payloadStringValue else { continue }
                if onCode(payload) { scanner.stopScanning(); return }
            }
        }
    }
}

/// Pins the scanner to its edges so a rotation (iPad) resizes it, and ties scanning to the view's
/// time on screen.
private final class ScannerHost: UIViewController {
    private let scanner: DataScannerViewController
    var onFailure: () -> Void

    init(scanner: DataScannerViewController, onFailure: @escaping () -> Void) {
        self.scanner = scanner
        self.onFailure = onFailure
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        addChild(scanner)
        scanner.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scanner.view)
        NSLayoutConstraint.activate([
            scanner.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scanner.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scanner.view.topAnchor.constraint(equalTo: view.topAnchor),
            scanner.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        scanner.didMove(toParent: self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        do { try scanner.startScanning() } catch { onFailure() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanner.stopScanning()
    }
}
