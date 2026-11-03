import Foundation

/// Which stars the map lights up: search matches, else blend results, else show-similar, else the
/// pinned legend chip's stars (as the web does). A pinned mood's stars also take the mood colour in
/// the renderer.
enum VibeHighlights {

    /// Everything the choice depends on. Defaults are the idle state.
    struct Input {
        /// Every track matching the search box; wins over everything else.
        var searchIds: [String] = []
        var blendIds: [String] = []
        var similarIds: [String] = []
        /// The tracks under the pinned legend chip, mood or not.
        var pinnedIds: [String] = []
    }

    static func ids(_ i: Input) -> [String] {
        if !i.searchIds.isEmpty { return i.searchIds }
        if !i.blendIds.isEmpty { return i.blendIds }
        if !i.similarIds.isEmpty { return i.similarIds }
        return i.pinnedIds
    }
}
