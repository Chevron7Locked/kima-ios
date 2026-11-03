import SwiftUI
import XCTest
@testable import Kima

/// Renders the share, discover-rows and imports screens from fixtures into PNG attachments, since a
/// share link cannot be opened on the signed-in simulator without creating one on the server.
/// Attachments land in the .xcresult bundle — nothing is written to disk.
@MainActor
final class C2ShareRenderTests: XCTestCase {

    private struct Host<Content: View>: View {
        @Environment(\.dismiss) private var dismiss
        let content: (DismissAction) -> Content
        var body: some View { content(dismiss) }
    }

    private func render<V: View>(_ name: String, _ view: V, env: AppEnvironment? = nil) throws {
        // No app environment: the real share sheet is presented at window level without one.
        let root: AnyView = env.map { AnyView(view.appEnvironment($0, ToastCenter())) } ?? AnyView(view)
        let host = UIHostingController(rootView: root.background(KimaColor.base))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.windowLevel = .alert + 1
        window.rootViewController = host
        window.makeKeyAndVisible()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let png = try XCTUnwrap(image.pngData())
        let a = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        window.isHidden = true
    }

    private let track = #"{"id":"t1","title":"Blue in Green","duration":337,"trackNo":3,"album":{"id":"a1","title":"Kind of Blue","coverUrl":null,"artist":{"id":"r1","name":"Miles Davis"}}}"#

    func testRenderSharePages() throws {
        let vm = SharedContentViewModel(token: "fixture", baseURL: URL(string: "https://kima.example.com")!)
        let playlist = try JSONDecoder().decode(SharedPlaylist.self, from: Data(
            #"{"id":"p1","name":"Late Night Records","user":{"username":"kevin"},"items":[{"id":"i1","sort":0,"track":\#(track)},{"id":"i2","sort":1,"track":\#(track)}]}"#.utf8))
        let album = try JSONDecoder().decode(SharedAlbum.self, from: Data(
            #"{"id":"a1","title":"Kind of Blue","coverArt":null,"artist":{"id":"r1","name":"Miles Davis"},"tracks":[\#(track)]}"#.utf8))
        let single = try JSONDecoder().decode(SharedTrack.self, from: Data(track.utf8))
        try render("share-playlist", Host { SharedPlaylistBody(playlist: playlist, vm: vm, dismiss: $0) })
        try render("share-album", Host { SharedAlbumBody(album: album, vm: vm, dismiss: $0) })
        try render("share-track", Host { SharedTrackBody(track: single, vm: vm, dismiss: $0) })
    }

    /// Discover's featured pick and rows (the server's weekly playlist is not built, so the real page shows none).
    func testRenderDiscoverRows() throws {
        let env = AppEnvironment(server: KimaServer(baseURL: URL(string: "https://kima.example.com")!))
        func pick(_ i: Int, _ title: String, liked: Bool = false) throws -> DiscoverTrack {
            try JSONDecoder().decode(DiscoverTrack.self, from: Data(
                #"{"id":"d\#(i)","title":"\#(title)","artist":"Boards of Canada","album":"Geogaddi","albumId":"a\#(i)","isLiked":\#(liked),"likedAt":null,"similarity":0.8,"tier":"high","coverUrl":null,"available":true,"duration":245}"#.utf8))
        }
        let a = try pick(1, "Music Is Math"), b = try pick(2, "Dawn Chorus", liked: true), c = try pick(3, "Sunshine Recorder")
        let view = ScrollView {
            VStack(spacing: KimaSpacing.md) {
                DiscoverFeaturedPick(track: a, isCurrentTrack: true, isPlaying: true, onPlay: {}, onTogglePlay: {}, onLike: {})
                DiscoverFeaturedPick(track: b, isCurrentTrack: false, isPlaying: false, onPlay: {}, onTogglePlay: {}, onLike: {})
                DiscoverFeaturedRow(track: b, index: 2, isCurrentTrack: true, isPlaying: true, onPlay: {}, onTogglePlay: {}, onLike: {})
                DiscoverFeaturedRow(track: c, index: 3, isCurrentTrack: false, isPlaying: false, onPlay: {}, onTogglePlay: {}, onLike: {})
                DiscoverCrateRow(track: a, index: 4, isCurrentTrack: true, isPlaying: true, onPlay: {}, onTogglePlay: {}, onLike: {})
                DiscoverCrateRow(track: b, index: 5, isCurrentTrack: true, isPlaying: false, onPlay: {}, onTogglePlay: {}, onLike: {})
                DiscoverCrateRow(track: c, index: 6, isCurrentTrack: false, isPlaying: false, onPlay: {}, onTogglePlay: {}, onLike: {})
            }
            .padding(.top, 60)
        }
        try render("discover-rows", view, env: env)
    }

    /// After-only: the imports tab with one running import (its "N active" header), as no import runs on the server.
    func testRenderImportsActive() throws {
        let env = AppEnvironment(server: KimaServer(baseURL: URL(string: "https://kima.example.com")!))
        env.activity.imports = try JSONDecoder().decode([ImportJob].self, from: Data(
            #"[{"id":"j1","playlistName":"Late Night","status":"downloading","albumsTotal":12,"albumsCompleted":5,"error":null,"createdAt":"2026-10-09T20:00:00Z"},{"id":"j2","playlistName":"Morning Run","status":"completed","albumsTotal":4,"albumsCompleted":4,"error":null,"createdAt":"2026-10-01T20:00:00Z"}]"#.utf8))
        try render("imports-active", ImportsSection().padding(.top, 60), env: env)
    }
}
