import Foundation
import CoreLocation

final class TrackLODCache {
    enum Level: Int, CaseIterable {
        case l0 = 0 // raw
        case l1 = 1 // 50m merge
        case l2 = 2 // 200m merge
        case l3 = 3 // 1km merge

        var mergeDistance: Double {
            switch self {
            case .l0: return 0
            case .l1: return 50
            case .l2: return 200
            case .l3: return 1000
            }
        }

        static func from(latitudeDelta: Double) -> Level {
            if latitudeDelta > 1.0 { return .l3 }
            if latitudeDelta > 0.2 { return .l2 }
            if latitudeDelta > 0.05 { return .l1 }
            return .l0
        }
    }

    private var caches: [Level: [RecordedPoint]] = [
        .l0: [],
        .l1: [],
        .l2: [],
        .l3: [],
    ]

    private var lastPoints: [Level: RecordedPoint?] = [:]

    func points(for level: Level) -> [RecordedPoint] {
        caches[level] ?? []
    }

    func setAll(_ points: [RecordedPoint]) {
        caches[.l0] = points
        for level in Level.allCases where level != .l0 {
            caches[level] = Self.simplify(points, mergeDistance: level.mergeDistance)
            lastPoints[level] = caches[level]?.last
        }
    }

    func appendPoint(_ point: RecordedPoint) {
        caches[.l0]?.append(point)

        for level in Level.allCases where level != .l0 {
            if let last = lastPoints[level] ?? caches[level]?.last {
                let dist = Self.distance(from: last, to: point)
                if dist >= level.mergeDistance {
                    caches[level]?.append(point)
                    lastPoints[level] = point
                }
            } else {
                caches[level]?.append(point)
                lastPoints[level] = point
            }
        }
    }

    private static func simplify(_ points: [RecordedPoint], mergeDistance: Double) -> [RecordedPoint] {
        guard let first = points.first else { return [] }
        var result = [first]
        for point in points.dropFirst() {
            if distance(from: result[result.count - 1], to: point) >= mergeDistance {
                result.append(point)
            }
        }
        return result
    }

    private static func distance(from a: RecordedPoint, to b: RecordedPoint) -> Double {
        let locA = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let locB = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return locA.distance(from: locB)
    }
}
