import Foundation

/// Everything that can go wrong talking to a Kima server, in terms a screen can show.
enum APIError: Error, LocalizedError {
    case network(Error)            // no connection / TLS / DNS
    case http(status: Int, body: String?)
    case decoding(Error)
    case unauthorized              // 401
    case requires2FA               // login needs a TOTP / recovery code

    var errorDescription: String? {
        switch self {
        case .network(let error): return Self.networkReason(error)
        case .http(let status, _): return "the server returned an error (\(status))."
        case .decoding:           return "the server sent a response the app can't read. the server may need an update."
        case .unauthorized:       return "your session has expired. please sign in again."
        case .requires2FA:        return "enter your two-factor code."
        }
    }

    /// Why iOS refused, in plain words, for any screen. A bare "couldn't reach" made a declined
    /// permission look the same as a typo or a dead server (GitHub #1). Only reasons that read
    /// right wherever a request fails live here; ones about the typed address are the connect
    /// screens' (`connectDescription`).
    private static func networkReason(_ error: Error) -> String {
        let generic = "couldn't reach the server. check the address and your connection."
        guard let url = error as? URLError else { return generic }
        switch url.code {
        case .notConnectedToInternet:
            // A declined local network prompt arrives as -1009; only the NW path's description
            // (a private userInfo key, no public API carries it) tells it apart from being offline.
            // Shape as logged in the wild: "unsatisfied (Local network prohibited), interface: en0…"
            // (community.simon42.com/t/47931). If iOS renames it, this degrades to the offline line.
            let path = url.userInfo["_NSURLErrorNWPathKey"].map { String(describing: $0) } ?? ""
            return path.localizedCaseInsensitiveContains("local network prohibited")
                ? "iOS blocked Kima from your local network. turn it on in settings › privacy & security › local network."
                : "you're offline. check your connection."
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return "the server's certificate isn't trusted. check its https setup, or use http on your local network."
        default:
            return generic
        }
    }

    /// The connect screens' copy (address entry, device pairing): the person just typed or scanned
    /// an address, so a bad name, a closed port or a slow server is worth naming. Everything else
    /// is `errorDescription`.
    var connectDescription: String? {
        guard case .network(let error as URLError) = self else { return errorDescription }
        switch error.code {
        case .cannotFindHost, .dnsLookupFailed:
            return "couldn't find a server with that name. check the address."
        case .cannotConnectToHost:
            return "nothing answered at that address. check the port and that the server is running."
        case .timedOut:
            return "the server took too long to answer. check the address and your connection."
        default:
            return errorDescription
        }
    }
}
