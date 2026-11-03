import Foundation

// MARK: - What's-new (release window) domain models
//
// The release window contract (/api/whats-new), distinct from the Release Radar model in KimaAPIClient+Releases.swift.
// Lenient decoding: one malformed item decodes with fallbacks so it can't blank the whole window.

enum WhatsNewItemKind: String, Codable, Sendable {
    case note, action, choice
}

/// One release in the window queue: a version, a name, one sentence, the maintainer's note, and items.
struct WhatsNewRelease: Identifiable, Sendable {
    let version: String
    let title: String
    let summary: String
    let date: String
    /// The maintainer's own words, which the window opens on. Absent on the releases the server
    /// synthesises (a retired mood mix waiting for an answer), where the window runs narrow.
    let note: WhatsNewNote?
    let items: [WhatsNewItem]

    var id: String { version }

    /// "1.11" — how the window names the release in its list heading.
    var shortVersion: String { version.split(separator: ".").prefix(2).joined(separator: ".") }
}

/// The note that heads a release: who it's from, and its body. Blank lines separate paragraphs.
struct WhatsNewNote: Sendable {
    let from: String
    let body: String
}

/// A `note` informs, an `action` offers something to run, a `choice` asks and defaults to off. The three
/// server shapes are flattened into one struct with optional fields; `kind` says which are meaningful.
/// Server-internal `requires`/`defaultValue` are not consumed client-side, since the server already filtered
/// items to the user (pendingReleases) and dismissing records defaults there.
struct WhatsNewItem: Identifiable, Sendable {
    let kind: WhatsNewItemKind
    let key: String
    let title: String
    /// One line in the window's list; the item's own page carries `body`.
    let summary: String
    let body: String

    // action
    let cta: String?
    /// What the window runs itself, behind a confirm — "wipeEnrichment" today. `runsFromWindow`
    /// is derived from this field's value: the server sends the action here, not a boolean flag.
    let run: String?
    var runsFromWindow: Bool { run == "wipeEnrichment" }
    let confirmTitle: String?
    let confirmMessage: String?
    let confirmLabel: String?
    /// What closing without acting means for this item; said in the footer.
    let ifClosed: String?

    // choice
    let discloses: String?

    /// Where the item points in the app, e.g. `/stats#false-starts`.
    var links: [WhatsNewLink] = []

    // changelog only
    /// A choice's recorded answer and who settled it.
    var answer: WhatsNewAnswer? = nil
    /// An action the server can see was really done.
    var done: Bool? = nil
    /// A tracked action still owed.
    var open: Bool? = nil

    /// The catalog's stable key — copy can change without the identity moving.
    var id: String { key }
}

/// A recorded choice: on or off, and `decidedBy` "EXPLICIT" (the user said so) or "DISMISSED" (left at its default).
struct WhatsNewAnswer: Decodable, Sendable {
    let enabled: Bool
    let decidedBy: String
    var isExplicit: Bool { decidedBy == "EXPLICIT" }
}

/// GET /whats-new/changelog: every release newest first, with what the server knows about each item.
struct WhatsNewChangelog: Decodable, Sendable {
    let releases: [WhatsNewRelease]
    let openCount: Int
}

/// GET /whats-new/update-status: whether a newer server release exists. `enabled` false = the check is off.
struct ServerUpdateStatus: Decodable, Sendable {
    let enabled: Bool
    let current: String
    let latest: String?
    let hasUpdate: Bool
}

/// One of an item's links: its label and the in-app path it opens.
struct WhatsNewLink: Decodable, Sendable {
    let label: String
    let href: String
}

extension WhatsNewRelease: Decodable {
    private enum CodingKeys: String, CodingKey { case version, title, summary, date, note, items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(String.self, forKey: .version)) ?? ""
        title   = (try? c.decode(String.self, forKey: .title))   ?? "kima update"
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        date    = (try? c.decode(String.self, forKey: .date))    ?? ""
        note    = try? c.decode(WhatsNewNote.self, forKey: .note)
        items   = (try? c.decode([WhatsNewItem].self, forKey: .items)) ?? []
    }
}

extension WhatsNewNote: Decodable {
    private enum CodingKeys: String, CodingKey { case from, body }

    /// Field-lenient on purpose: a note missing its signature still shows its body. Losing the
    /// maintainer's message to a missing signature is the worse failure.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = (try? c.decode(String.self, forKey: .from)) ?? "kima"
        body = (try? c.decode(String.self, forKey: .body)) ?? ""
    }
}

extension WhatsNewItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case kind, key, title, summary, body, cta, run
        case confirmTitle, confirmMessage, confirmLabel, ifClosed, discloses, links
        case answer, done, open
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // An unrecognized kind keeps the item as a note (title+body render;
        // nothing runnable is lost — the web would drop the whole response).
        kind = (try? c.decode(WhatsNewItemKind.self, forKey: .kind)) ?? .note
        key   = (try? c.decode(String.self, forKey: .key))   ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        // An item with no one-liner shows its body in the list line instead of an empty row.
        let decodedSummary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        body  = (try? c.decode(String.self, forKey: .body))  ?? ""
        summary = decodedSummary.isEmpty ? body : decodedSummary

        cta              = try? c.decode(String.self, forKey: .cta)
        run              = try? c.decode(String.self, forKey: .run)
        confirmTitle     = try? c.decode(String.self, forKey: .confirmTitle)
        confirmMessage   = try? c.decode(String.self, forKey: .confirmMessage)
        confirmLabel     = try? c.decode(String.self, forKey: .confirmLabel)
        ifClosed         = try? c.decode(String.self, forKey: .ifClosed)
        discloses        = try? c.decode(String.self, forKey: .discloses)
        links            = (try? c.decode([WhatsNewLink].self, forKey: .links)) ?? []
        answer           = try? c.decode(WhatsNewAnswer.self, forKey: .answer)
        done             = try? c.decode(Bool.self, forKey: .done)
        open             = try? c.decode(Bool.self, forKey: .open)
    }
}

// MARK: - Mood-mix release state (GET /whats-new/mood-mixes)

/// The user's saved mood mix + what they decided about it, server-side.
/// `decision` is "rebuild" | "keep" | nil — "rebuild" means the mix was cleared
/// (by Rebuild or Remove).
struct MoodMixReleaseState: Sendable {
    struct Mix: Decodable, Sendable {
        let id: String
        let name: String
        let mood: String
        let trackCount: Int
        let retired: Bool
    }
    struct Ref: Decodable, Sendable {
        let id: String
        let name: String
    }
    var mix: Mix?
    var decision: String?
    var playlist: Ref?
}

extension MoodMixReleaseState: Decodable {
    private enum CodingKeys: String, CodingKey { case mix, decision, playlist }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mix      = try? c.decode(Mix.self, forKey: .mix)
        decision = try? c.decode(String.self, forKey: .decision)
        playlist = try? c.decode(Ref.self, forKey: .playlist)
    }
}

/// POST /whats-new/mood-mixes/save response (saveMoodMixAsPlaylist).
struct MoodMixSaveResult: Decodable, Sendable {
    let id: String
    let name: String
}
