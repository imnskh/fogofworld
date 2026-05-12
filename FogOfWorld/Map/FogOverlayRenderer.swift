import MapKit
import UIKit

final class FogOverlayRenderer: MKOverlayRenderer {
    private let lock = NSLock()
    private var _tiles: Set<TileCoord> = []

    private let fogColor = UIColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 0.88).cgColor
    private let clearColor = UIColor.white.cgColor
    private let minZoomScale: MKZoomScale = 0.003

    func updateTiles(_ tiles: Set<TileCoord>) {
        lock.lock()
        _tiles = tiles
        lock.unlock()
        setNeedsDisplay()
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let drawRect = rect(for: mapRect)

        context.setFillColor(fogColor)
        context.fill(drawRect)

        guard zoomScale >= minZoomScale else { return }

        lock.lock()
        let tiles = _tiles
        lock.unlock()

        context.setBlendMode(.destinationOut)
        context.setFillColor(clearColor)

        let padding = TileCoord.size * 1000
        let expandedRect = mapRect.insetBy(dx: -padding, dy: -padding)
        let (xRange, yRange) = TileCoord.tileRange(for: expandedRect)

        let tileCount = (xRange.upperBound - xRange.lowerBound + 1)
            * (yRange.upperBound - yRange.lowerBound + 1)
        guard tileCount < 50_000 else { return }

        for tx in xRange {
            for ty in yRange {
                let coord = TileCoord(x: tx, y: ty)
                guard tiles.contains(coord) else { continue }

                let tileMapRect = coord.mapRect
                var tileRect = rect(for: tileMapRect)
                tileRect = tileRect.insetBy(
                    dx: -tileRect.width * 0.2,
                    dy: -tileRect.height * 0.2
                )
                context.fillEllipse(in: tileRect)
            }
        }
    }
}
