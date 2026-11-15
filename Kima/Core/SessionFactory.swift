import Foundation

/// How one consumer's session differs from the shared posture — today only timeouts: the API
/// client's long-timeout twin and the event stream's finite pair.
/// Cache posture is deliberately NOT per-use: every consumer shares the ephemeral no-disk-cache
/// rule because authenticated bytes must never persist unencrypted. If a consumer ever genuinely
/// needs to differ, that need gets a field here, not a hand-minted session.
struct SessionNeeds {
    /// Max gap between bytes before the request fails; nil keeps Foundation's 60s default.
    var requestTimeout: TimeInterval?
    /// Hard cap on one task's total lifetime; nil keeps Foundation's 7-day default.
    var resourceTimeout: TimeInterval?

    func apply(to config: URLSessionConfiguration) {
        if let requestTimeout { config.timeoutIntervalForRequest = requestTimeout }
        if let resourceTimeout { config.timeoutIntervalForResource = resourceTimeout }
    }
}

/// Hands out every URLSession the app uses — the API client's, the event stream's, the
/// cover-art loader's — so no consumer mints one itself. The shared posture lives in the one
/// default implementation of `makeSession`: ephemeral configuration (no persistent disk cache,
/// no persistent cookie store, so authenticated responses never land in `Library/Caches/`
/// readable without the JWT) plus the certificate trust delegate on every session. An adapter
/// expresses only its transport difference, so production and the test stub cannot drift apart —
/// unit tests run the trust layer they ship behind because there is no other posture to route
/// around. See GLOSSARY.md "Session factory" for which "session" this is.
protocol SessionFactory {
    /// Transport classes answering instead of the network; nil uses the system default set (the
    /// real network). The only difference an adapter expresses.
    var protocolClasses: [AnyClass]? { get }
}

extension SessionFactory {
    /// The one way to get the shared configuration: posture applied, `needs`' differences on top.
    func makeSession(_ needs: SessionNeeds = .init()) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        needs.apply(to: config)
        if let protocolClasses { config.protocolClasses = protocolClasses }
        return URLSession(configuration: config, delegate: ServerTrust.shared.delegate, delegateQueue: nil)
    }
}

extension SessionFactory where Self == ProductionSessionFactory {
    /// The default every consumer starts from: the adapter the shipped app runs on.
    static var production: ProductionSessionFactory { ProductionSessionFactory() }
}

/// The adapter the shipped app runs on: real network, shared posture.
struct ProductionSessionFactory: SessionFactory {
    var protocolClasses: [AnyClass]? { nil }
}
