import Foundation
import CoreLocation

/// Reverse-geocodes (lat, lon) → human-readable place ("San Francisco, CA")
/// for the metadata table's GPS row. Caches results in memory keyed by a
/// rounded coord — the same photo tagged at two cm of jitter doesn't burn
/// two CLGeocoder requests against Apple's per-process rate limit.
///
/// The cache is best-effort: a network failure or rate-limit miss returns
/// nil, and the GPS row falls back to raw lat/lon. Callers must tolerate
/// nil even after a successful future call to the same coord (cache rows
/// only hold *successful* lookups).
actor GeoCache {
    static let shared = GeoCache()

    /// Round to 3 decimals (~110 m of precision) — fine enough that two
    /// photos in the same neighborhood hit the same cache row, coarse
    /// enough that a few houses produce one cache miss per area.
    private static let roundDecimals: Double = 1000

    /// In-memory results. Persistence between launches isn't worth the
    /// complexity — a session typically covers a few hundred unique
    /// coords; recomputation across restarts is cheap and avoids a stale-
    /// cache class of bug.
    private var cache: [String: String] = [:]

    /// In-flight tasks keyed by coord key. Multiple comparison-view loads
    /// for the same coord coalesce onto a single CLGeocoder call.
    private var inflight: [String: Task<String?, Never>] = [:]

    private let geocoder = CLGeocoder()

    private init() {}

    /// Returns a place name for the coord, or nil if reverse-geocoding
    /// failed / is unavailable. Coalesces concurrent callers; results
    /// are cached for the process lifetime.
    func placeName(latitude: Double, longitude: Double) async -> String? {
        let key = Self.key(latitude: latitude, longitude: longitude)
        if let hit = cache[key] { return hit }
        if let task = inflight[key] { return await task.value }

        let task = Task<String?, Never> { [geocoder] in
            await Self.reverseGeocode(geocoder: geocoder, latitude: latitude, longitude: longitude)
        }
        inflight[key] = task
        let result = await task.value
        inflight[key] = nil
        if let r = result { cache[key] = r }
        return result
    }

    private static func key(latitude: Double, longitude: Double) -> String {
        let lat = (latitude * roundDecimals).rounded() / roundDecimals
        let lon = (longitude * roundDecimals).rounded() / roundDecimals
        return String(format: "%.3f,%.3f", lat, lon)
    }

    private static func reverseGeocode(
        geocoder: CLGeocoder,
        latitude: Double,
        longitude: Double
    ) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let p = placemarks.first else { return nil }
            // Order of preference: locality (city), administrativeArea
            // (state/region), country. Combine the most specific two we
            // have. Suburbs ("subLocality") on macOS are usually noisy
            // ("Russian Hill") so we leave them out by default.
            var parts: [String] = []
            if let l = p.locality { parts.append(l) }
            if let a = p.administrativeArea, !parts.contains(a) { parts.append(a) }
            if parts.isEmpty, let c = p.country { parts.append(c) }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        } catch {
            return nil
        }
    }
}
