import Foundation

/// Typed navigation routes. Phase 3 adds a media player route.
enum AppRoute: Hashable {
    case songs(bandId: Int)
    case rehearsals(bandId: Int)
}
