import Foundation

/// Plain lowercase text for every way a vibe-map call can fail. Pure: it only looks at the error.
enum VibeErrorCopy {

    static let notAnalysed = "not analysed yet"
    static let mapPollCap = "map still building — try again later"

    /// Status code and lowercased body of an HTTP failure, or nil for any other kind of error.
    private static func http(_ error: Error) -> (status: Int, body: String)? {
        guard let api = error as? APIError, case .http(let status, let body) = api else { return nil }
        return (status, (body ?? "").lowercased())
    }

    /// Finding similar tracks (`/vibe/similar`, and the player's similar-tracks button).
    static func similar(_ error: Error) -> String {
        if let h = http(error), h.status == 404 { return notAnalysed }
        return "couldn't load similar tracks"
    }

    /// Blending tracks (`/vibe/alchemy`).
    static func alchemy(_ error: Error) -> String {
        if let h = http(error), h.status == 400 {
            if h.body.contains("similarity step") { return notAnalysed }
            if h.body.contains("cancel each other out") { return "those tracks cancel out" }
        }
        return "couldn't blend these tracks"
    }

    /// Charting a path between two tracks (`/vibe/path`).
    static func path(_ error: Error) -> String {
        if let h = http(error), h.status == 400 {
            if h.body.contains("similarity step") { return notAnalysed }
            if h.body.contains("too similar") { return "too similar for a path" }
        }
        return "couldn't find a path"
    }

    /// Loading the map itself (`/vibe/map`).
    static func mapLoad(_ error: Error) -> String {
        if let api = error as? APIError, case .network = api { return "can't reach the server" }
        if error is URLError { return "can't reach the server" }
        return "map didn't load"
    }
}
