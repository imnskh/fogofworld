import MapKit
import UIKit
import CoreLocation

final class TrackOverlayRenderer: MKOverlayRenderer {
    private let lock = NSLock()
    let lodCache = TrackLODCache()
    var visible = true
    var displayTimeInterval: TimeInterval?

    private let trackColor = UIColor.systemBlue.withAlphaComponent(0.7).cgColor
    private let lineWidth: CGFloat = 3
    private let stationaryDuration: TimeInterval = 30 * 60 // 30 min
    private let stationaryDistance: Double = 30 // 30m

    func updatePoints(_ points: [RecordedPoint]) {
        lock.lock()
        lodCache.setAll(points)
        lock.unlock()
        setNeedsDisplay()
    }

    func appendPoint(_ point: RecordedPoint) {
        lock.lock()
        lodCache.appendPoint(point)
        lock.unlock()
        setNeedsDisplay()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard visible else { return }

        let region = MKCoordinateRegion(mapRect)
        let level = TrackLODCache.Level.from(latitudeDelta: region.span.latitudeDelta)

        lock.lock()
        var points = lodCache.points(for: level)
        lock.unlock()

        if let interval = displayTimeInterval {
            let cutoff = Date().addingTimeInterval(-interval)
            points = points.filter { $0.timestamp >= cutoff }
        }

        points = mergeStationary(points)

        guard points.count >= 2 else { return }

        let padding = mapRect.size.width * 0.1
        let expandedRect = mapRect.insetBy(dx: -padding, dy: -padding)

        context.setStrokeColor(trackColor)
        context.setLineWidth(lineWidth / zoomScale)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        var isDrawing = false
        var prevInside = false

        for i in 0..<points.count {
            let mapPoint = MKMapPoint(points[i].coordinate)
            let inside = expandedRect.contains(mapPoint)

            if i == 0 {
                prevInside = inside
                if inside {
                    let cgPoint = point(for: mapPoint)
                    context.move(to: cgPoint)
                    isDrawing = true
                }
                continue
            }

            let cgPoint = point(for: mapPoint)

            if inside || prevInside {
                if !isDrawing {
                    let prevMapPoint = MKMapPoint(points[i - 1].coordinate)
                    context.move(to: point(for: prevMapPoint))
                    isDrawing = true
                }
                context.addLine(to: cgPoint)
            } else {
                if isDrawing {
                    context.strokePath()
                    isDrawing = false
                }
            }

            prevInside = inside
        }

        if isDrawing {
            context.strokePath()
        }
    }

    private func mergeStationary(_ points: [RecordedPoint]) -> [RecordedPoint] {
        guard points.count > 2 else { return points }

        var result: [RecordedPoint] = []
        var stationaryStart = 0

        for i in 0..<points.count {
            let distFromStart = Self.distance(from: points[stationaryStart], to: points[i])

            if distFromStart > stationaryDistance {
                if i - stationaryStart > 1 {
                    let duration = points[i - 1].timestamp.timeIntervalSince(points[stationaryStart].timestamp)
                    if duration >= stationaryDuration {
                        result.append(points[stationaryStart])
                        result.append(points[i - 1])
                    } else {
                        for j in stationaryStart..<i {
                            result.append(points[j])
                        }
                    }
                } else {
                    result.append(points[stationaryStart])
                }
                stationaryStart = i
            }
        }

        let lastDuration = points[points.count - 1].timestamp.timeIntervalSince(points[stationaryStart].timestamp)
        if points.count - stationaryStart > 1 && lastDuration >= stationaryDuration {
            result.append(points[stationaryStart])
            result.append(points[points.count - 1])
        } else {
            for j in stationaryStart..<points.count {
                result.append(points[j])
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
