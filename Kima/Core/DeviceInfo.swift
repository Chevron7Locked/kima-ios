import UIKit

/// The phone's OS and hardware model as a bug report states them, e.g. "iOS 26.0" and "iPhone17,1".
/// The model is the hardware identifier, never the device's name, which can hold its owner's name.
enum DeviceInfo {
    @MainActor static var system: String {
        "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    }

    static var model: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}
