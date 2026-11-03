import Foundation

// MARK: - SSE Ticket
// POST /api/events/ticket → { ticket }. A short-lived ticket from an authed POST, passed as ?ticket= on the
// GET /api/events stream URL so URLSession.bytes can authenticate without an Authorization header.

private struct EventTicketResponse: Decodable {
    let ticket: String
}

extension KimaAPIClient {

    /// POST /api/events/ticket — mint a short-lived SSE authentication ticket.
    ///
    /// The ticket is valid for a single connection to `GET /api/events?ticket=<value>`.
    /// Call immediately before opening the stream; do not cache or reuse across reconnects.
    func eventsTicket() async throws -> String {
        let response: EventTicketResponse = try await post(
            "/events/ticket", body: [:], authed: true
        )
        return response.ticket
    }
}
