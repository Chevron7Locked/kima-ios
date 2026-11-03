import UIKit

// MARK: - KimaAppDelegate
// Vends scene configurations. A plist-only reference to the CarPlay scene delegate gets dead-stripped, so the scene
// never connects (tapping the app on the CarPlay dashboard opens nothing). Mapping the CarPlay role to
// `KimaCarPlaySceneDelegate` here keeps the class linked. The phone window scene is left to SwiftUI.
final class KimaAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            let config = UISceneConfiguration(
                name: "KimaCarPlay",
                sessionRole: connectingSceneSession.role
            )
            config.delegateClass = KimaCarPlaySceneDelegate.self
            return config
        }
        // Phone / iPad window scene — SwiftUI manages it; no custom delegate.
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }
}
