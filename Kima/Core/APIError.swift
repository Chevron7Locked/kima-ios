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
        case .network:            return "couldn't reach the server. check the address and your connection."
        case .http(let status, _): return "the server returned an error (\(status))."
        case .decoding:           return "the server sent a response the app can't read. the server may need an update."
        case .unauthorized:       return "your session has expired. please sign in again."
        case .requires2FA:        return "enter your two-factor code."
        }
    }
}
