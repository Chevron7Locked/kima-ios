import Foundation

// MARK: - VibeResultTrack → Track

extension VibeResultTrack {

    /// Build a fully-populated `Track` from this alchemy/search result. The nested `album` and `artist` objects and
    /// `duration` are real; `audioFeatures` is nil (not returned), and `distance`/`similarity` have no slot in `Track`.
    func asTrack() -> Track {
        Track(
            id: id,
            title: title,
            duration: duration,
            trackNo: trackNo,
            artist: TrackArtistRef(id: artist.id, name: artist.name),
            album: TrackAlbumRef(id: album.id, title: album.title, coverArt: album.coverUrl)
        )
    }
}

// MARK: - VibePathTrack → Track

extension VibePathTrack {

    /// Build a `Track` from a journey waypoint or anchor. `VibePathTrack` is flat and denormalised (the path
    /// service JOINs before responding), so every field is populated; this covers `startTrack`/`endTrack` too.
    func asTrack() -> Track {
        Track(
            id: id,
            title: title,
            duration: duration,
            artist: TrackArtistRef(id: artistId, name: artistName),
            album: TrackAlbumRef(id: albumId, title: albumTitle, coverArt: albumCoverUrl)
        )
    }
}
