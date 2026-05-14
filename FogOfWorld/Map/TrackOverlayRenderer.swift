import MapKit
import UIKit

final class TrackOverlayRenderer: MKOverlayRenderer {
    private let lock = NSLock()
    let lodCache = TrackLODCache()
    var visible = true

    private let trackColor = UIColor.systemBlue.withAlphaComponent(0.7).cgColor
    private let lineWidth: CGFloat = 3

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
        let points = lodCache.points(for: level)
        lock.unlock()

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
}
