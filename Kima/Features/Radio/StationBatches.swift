import Foundation

/// A station's batches from GET /library/radio. One seed per station session: for the stations the server orders
/// (moods, wildcard, workout) a batch comes back with `next`, and the next fetch asks from there with the same seed,
/// so refills carry on through the server's order instead of starting a fresh one. `tz` lets the late-night station
/// read the listener's evening plays in their own time zone.
@MainActor
final class StationBatches {
    private let client: KimaAPIClient
    private let type: String
    private let value: String?
    private let seed = RadioPage.newSeed()
    private var offset: Int?

    init(client: KimaAPIClient, type: String, value: String?) {
        self.client = client
        self.type = type
        self.value = value
    }

    func next() async throws -> RadioPage {
        let page = try await client.getRadioPage(
            type: type, value: value, limit: 100, seed: seed, offset: offset, tz: TimeZone.current.identifier
        )
        if let next = page.next { offset = next }
        return page
    }
}
