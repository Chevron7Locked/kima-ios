import Foundation
import Observation

// MARK: - Entity kind discriminator

/// Which library entity the metadata editor is operating on.
/// Carries the current entity value so the ViewModel can pre-populate form fields
/// and route save/reset calls to the correct endpoint.
enum MetadataEntityKind {
    case artist(Artist)
    case album(Album)
    case track(Track)
}

// MARK: - ViewModel

/// Drives the MetadataEditorView sheet.
@MainActor
@Observable
final class MetadataEditorViewModel {

    let kind: MetadataEntityKind

    // MARK: Form fields (two-way bound to the view)

    /// Artist name / album title / track title.
    var nameOrTitle: String = ""
    /// Artist biography (artist only).
    var bio: String = ""
    /// Comma-separated genre list (artist + album).
    var genres: String = ""
    /// MusicBrainz artist ID or release-group ID (artist uses `mbid`; album uses `rgMbid`).
    var mbidOrRgMbid: String = ""
    /// Artist hero image URL or album cover art URL (not applicable to tracks).
    var imageUrl: String = ""
    /// Release year string (album only; empty = no override).
    var year: String = ""
    /// Track number string (track only; empty = no override).
    var trackNo: String = ""

    // MARK: Loading state

    var isSaving = false
    var isResetting = false

    // MARK: Computed labels (drive the view's copy)

    var entityLabel: String {
        switch kind {
        case .artist: return "artist"
        case .album:  return "album"
        case .track:  return "track"
        }
    }

    var nameLabel: String {
        switch kind {
        case .artist: return "artist name"
        case .album:  return "album title"
        case .track:  return "track title"
        }
    }

    var imageLabel: String {
        switch kind {
        case .artist: return "artist image url"
        default:      return "cover art url"
        }
    }

    var mbidLabel: String {
        switch kind {
        case .album: return "MusicBrainz release group id"
        default:     return "MusicBrainz id"
        }
    }

    var hasUserOverrides: Bool {
        switch kind {
        case .artist(let a): return a.hasUserOverrides == true
        case .album(let a):  return a.hasUserOverrides == true
        case .track(let t):  return t.hasUserOverrides == true
        }
    }

    // MARK: Original-value hints

    /// Shown below the name/title field when a user override is active.
    var originalNameOrTitle: String? {
        switch kind {
        case .artist(let a): return a.displayName != nil ? a.name : nil
        case .album(let a):  return a.displayTitle != nil ? a.title : nil
        case .track(let t):  return t.displayTitle != nil ? t.title : nil
        }
    }

    /// Shown below the bio field when the user has overridden the bio.
    var originalBio: String? {
        guard case .artist(let a) = kind, a.userSummary != nil else { return nil }
        let raw = a.summary ?? a.bio ?? ""
        return raw.isEmpty ? nil : raw
    }

    /// Shown below the genres field when user genres override the auto-detected ones.
    var originalGenres: String? {
        switch kind {
        case .artist(let a):
            guard a.userGenres?.isEmpty == false else { return nil }
            let g = a.genres ?? []
            return g.isEmpty ? nil : g.joined(separator: ", ")
        case .album(let a):
            guard a.userGenres?.isEmpty == false else { return nil }
            let g = a.genres ?? []
            return g.isEmpty ? nil : g.joined(separator: ", ")
        default: return nil
        }
    }

    /// Shown below the year field when a user override year is active.
    var originalYear: Int? {
        guard case .album(let a) = kind, a.displayYear != nil else { return nil }
        return a.year
    }

    /// Shown below the image URL field when a user image URL is active.
    var originalImageUrl: String? {
        switch kind {
        case .artist(let a):
            return a.userHeroUrl != nil ? a.heroUrl : nil
        case .album(let a):
            return a.userCoverUrl != nil ? a.coverUrl : nil
        default: return nil
        }
    }

    @ObservationIgnored private var initial = FormSnapshot()

    var current: FormSnapshot {
        FormSnapshot(nameOrTitle: nameOrTitle, bio: bio, genres: genres,
                     mbidOrRgMbid: mbidOrRgMbid, imageUrl: imageUrl, year: year, trackNo: trackNo)
    }

    // MARK: Init

    init(kind: MetadataEntityKind) {
        self.kind = kind
        loadFormData()
    }

    private func loadFormData() {
        switch kind {
        case .artist(let artist):
            nameOrTitle  = artist.effectiveName
            bio          = artist.userSummary ?? artist.summary ?? artist.bio ?? ""
            genres       = (artist.userGenres.nonEmpty ?? artist.genres ?? []).joined(separator: ", ")
            mbidOrRgMbid = artist.mbid ?? ""
            imageUrl     = artist.userHeroUrl ?? artist.heroUrl ?? ""

        case .album(let album):
            nameOrTitle  = album.effectiveTitle
            year         = (album.displayYear ?? album.year).map(String.init) ?? ""
            genres       = (album.userGenres.nonEmpty ?? album.genres ?? []).joined(separator: ", ")
            mbidOrRgMbid = album.rgMbid ?? ""
            imageUrl     = album.userCoverUrl ?? album.coverUrl ?? ""

        case .track(let track):
            nameOrTitle = track.effectiveTitle
            let no = track.displayTrackNo ?? track.trackNo ?? track.trackNumber
            trackNo = no.map(String.init) ?? ""
        }
        initial = current
    }

    // MARK: Actions

    /// Sends the changed fields. False when nothing changed, so nothing was sent.
    func save(client: KimaAPIClient) async throws -> Bool {
        // Build first so a bad year/track number throws before the saving spinner starts.
        let before = initial, after = current
        switch kind {
        case .artist(let artist):
            let update = Self.artistUpdate(from: before, to: after)
            guard !update.isEmpty else { return false }
            isSaving = true
            defer { isSaving = false }
            _ = try await client.updateArtistMetadata(id: artist.id, update: update)

        case .album(let album):
            let update = try Self.albumUpdate(from: before, to: after)
            guard !update.isEmpty else { return false }
            isSaving = true
            defer { isSaving = false }
            _ = try await client.updateAlbumMetadata(id: album.id, update: update)

        case .track(let track):
            let update = try Self.trackUpdate(from: before, to: after)
            guard !update.isEmpty else { return false }
            isSaving = true
            defer { isSaving = false }
            _ = try await client.updateTrackMetadata(id: track.id, update: update)
        }
        return true
    }

    func reset(client: KimaAPIClient) async throws {
        isResetting = true
        defer { isResetting = false }
        switch kind {
        case .artist(let a): try await client.resetArtistMetadata(id: a.id)
        case .album(let a):  try await client.resetAlbumMetadata(id: a.id)
        case .track(let t):  try await client.resetTrackMetadata(id: t.id)
        }
    }

    // MARK: Helpers

    static func parseGenres(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: Diff builders (pure, unit-tested)
    // Only fields the user changed are sent, so editing the bio does not also pin the
    // name, genres, id and image as manual overrides. Emptying a field clears its override.

    static func artistUpdate(from a: FormSnapshot, to b: FormSnapshot) -> ArtistMetadataUpdate {
        ArtistMetadataUpdate(
            name:    textEdit(a.nameOrTitle, b.nameOrTitle),
            bio:     textEdit(a.bio, b.bio),
            genres:  genresEdit(a.genres, b.genres),
            mbid:    idEdit(a.mbidOrRgMbid, b.mbidOrRgMbid),
            heroUrl: textEdit(a.imageUrl, b.imageUrl)
        )
    }

    static func albumUpdate(from a: FormSnapshot, to b: FormSnapshot) throws -> AlbumMetadataUpdate {
        AlbumMetadataUpdate(
            title:    textEdit(a.nameOrTitle, b.nameOrTitle),
            year:     try numberEdit(a.year, b.year, error: .year),
            genres:   genresEdit(a.genres, b.genres),
            rgMbid:   idEdit(a.mbidOrRgMbid, b.mbidOrRgMbid),
            coverUrl: textEdit(a.imageUrl, b.imageUrl)
        )
    }

    static func trackUpdate(from a: FormSnapshot, to b: FormSnapshot) throws -> TrackMetadataUpdate {
        TrackMetadataUpdate(
            title:   textEdit(a.nameOrTitle, b.nameOrTitle),
            trackNo: try numberEdit(a.trackNo, b.trackNo, error: .trackNumber)
        )
    }

    private static func textEdit(_ a: String, _ b: String) -> MetadataEdit<String>? {
        guard b.nilIfEmpty != a.nilIfEmpty else { return nil }
        return b.nilIfEmpty.map { .set($0) } ?? .clear
    }

    private static func numberEdit(_ a: String, _ b: String, error: MetadataInputError) throws -> MetadataEdit<Int>? {
        guard b.nilIfEmpty != a.nilIfEmpty else { return nil }
        guard let t = b.nilIfEmpty else { return .clear }
        guard let n = Int(t) else { throw error }
        return .set(n)
    }

    private static func genresEdit(_ a: String, _ b: String) -> MetadataEdit<[String]>? {
        let new = parseGenres(b)
        return new != parseGenres(a) ? .set(new) : nil
    }

    /// A MusicBrainz id can be replaced but not removed, so an emptied id field is no change.
    private static func idEdit(_ a: String, _ b: String) -> String? {
        guard b.nilIfEmpty != a.nilIfEmpty else { return nil }
        return b.nilIfEmpty
    }
}

/// The editable form fields at one moment; `initial` vs `current` drives the diff.
struct FormSnapshot: Equatable {
    var nameOrTitle = "", bio = "", genres = "", mbidOrRgMbid = "", imageUrl = "", year = "", trackNo = ""
}

enum MetadataInputError: LocalizedError {
    case year, trackNumber
    var errorDescription: String? {
        switch self {
        case .year: return "year must be a number"
        case .trackNumber: return "track number must be a number"
        }
    }
}

private extension ArtistMetadataUpdate {
    var isEmpty: Bool { name == nil && bio == nil && genres == nil && mbid == nil && heroUrl == nil }
}
private extension AlbumMetadataUpdate {
    var isEmpty: Bool { title == nil && year == nil && genres == nil && rgMbid == nil && coverUrl == nil }
}
private extension TrackMetadataUpdate {
    var isEmpty: Bool { title == nil && trackNo == nil }
}

// MARK: - String convenience

private extension String {
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

private extension Optional where Wrapped == [String] {
    /// An empty override list means "no override" (what the server's reset stores).
    var nonEmpty: [String]? { self?.isEmpty == false ? self : nil }
}
