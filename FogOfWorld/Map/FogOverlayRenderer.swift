import MapKit
import UIKit

final class FogOverlayRenderer: MKOverlayRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var _tiles: Set<TileCoord> = []
    private var animatingTiles: [TileCoord: CFAbsoluteTime] = [:]
    // 起動直後のディスクからの一括ロードを「全タイル解禁アニメ」にしないためのフラグ。
    // 一度目の updateTiles 呼び出しは内容にかかわらずアニメ対象から除外する。
    private var hasReceivedInitialLoad = false
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?

    // 霧のエフェクト全体 (境界ソフト化 + 解禁アニメ) を一括 ON/OFF するスイッチ。
    // OFF にすると元の単色 ellipse 塗りに戻り、アニメも止まる。
    // setter は main thread からのみ呼ぶ前提 (displayLink の操作 + setNeedsDisplay が main 要求のため)。
    // 値の読み書きは `lock` で保護し、`updateTiles` / `draw` 側のロック内読み出しと整合させる。
    private var _effectsEnabled: Bool = true
    var effectsEnabled: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _effectsEnabled
        }
        set {
            lock.lock()
            guard _effectsEnabled != newValue else {
                lock.unlock()
                return
            }
            _effectsEnabled = newValue
            if !newValue {
                animatingTiles.removeAll()
            }
            lock.unlock()
            if !newValue {
                displayLink?.invalidate()
                displayLink = nil
                displayLinkProxy = nil
            }
            setNeedsDisplay()
        }
    }

    private let fogColor = UIColor(red: 0.12, green: 0.12, blue: 0.18, alpha: 0.88).cgColor
    // effectsEnabled == false 時の穴あけ用。destinationOut 下では白 (α=1) で完全クリア。
    private let clearColor = UIColor.white.cgColor
    private let minZoomScale: MKZoomScale = 0.003
    private let revealAnimationDuration: CFAbsoluteTime = 0.6
    // updateTiles が一気に大量の差分を受け取った場合（例: import の replace モード）に、
    // それを「ユーザー操作で1個ずつ解禁された」とみなして全件アニメさせないための閾値。
    private let bulkImportDiffThreshold = 50

    // 解禁タイル中心は完全クリア（α=1）の「コア」を確保しつつ、外周だけで α=1→0 にフェードする
    // 3-stop グラデーション。2-stop（中心から線形に減衰）だと境界の滲みが内側まで食い込んで見えるため、
    // 内側にしっかりクリア領域を残してから外側だけで霧へ溶ける形にする。
    //
    // 0.0..0.7 を α=1 コア、後段で半径 `0.95 × max(w,h)` を取ることで隣接タイル間に霧の残りが出ない。
    // 検証 (gradient 座標 = 中心からの実距離 / baseRadius):
    //   - 隣接2タイル (辺接合): 接合線中点までの距離 0.5 tileSize → gradient 座標 0.526 < 0.7
    //     両側ともコア内に入り、destinationOut の重ねで完全クリア。
    //   - 4タイル対角交差点: 中心から √2/2 ≈ 0.707 tileSize → gradient 座標 0.744 で
    //     フェード帯 (0.7..1.0) にあり 1 枚あたり α ≈ 0.85 にしかならないが、
    //     destinationOut の 4 重重ね合わせで `1 - (1 - 0.85)^4 ≈ 0.9995` → 実質完全クリア。
    // 0.7..1.0 がフェード帯 (30%) で、孤立タイルでは外周がふわっと霧に溶ける。
    private let revealGradient: CGGradient = {
        let colors = [
            UIColor(white: 1, alpha: 1).cgColor,
            UIColor(white: 1, alpha: 1).cgColor,
            UIColor(white: 1, alpha: 0).cgColor
        ] as CFArray
        return CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors,
            locations: [0, 0.7, 1]
        )!
    }()

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Public API

    func updateTiles(_ tiles: Set<TileCoord>) {
        lock.lock()
        // effects OFF 中に追加されたタイルはアニメ対象にしない。後で ON にしても遡って光らせない。
        let shouldDetectNewcomers = hasReceivedInitialLoad && _effectsEnabled
        hasReceivedInitialLoad = true
        // 大量差分時はバルクインポート等とみなしてアニメ対象外。
        // 旧コードは count の delta で判定していたが、replace モードで同サイズの全く別の集合が来た場合に
        // delta ≈ 0 で誤って通常更新扱いになる問題があったので、subtracting の結果サイズで判定する。
        let newcomers: Set<TileCoord>
        if !shouldDetectNewcomers {
            newcomers = []
        } else {
            let candidates = tiles.subtracting(_tiles)
            newcomers = candidates.count > bulkImportDiffThreshold ? [] : candidates
        }
        _tiles = tiles
        if !newcomers.isEmpty {
            let now = CFAbsoluteTimeGetCurrent()
            for tile in newcomers {
                animatingTiles[tile] = now
            }
        }
        // インポートの replace モード等で消えたタイルが animatingTiles に残らないようにする。
        if !animatingTiles.isEmpty {
            animatingTiles = animatingTiles.filter { tiles.contains($0.key) }
        }
        let hasActiveAnimation = !animatingTiles.isEmpty
        lock.unlock()

        if hasActiveAnimation {
            // CADisplayLink の add(to:) は main run loop 上で行う必要がある。
            DispatchQueue.main.async { [weak self] in
                self?.ensureDisplayLink()
            }
        }
        setNeedsDisplay()
    }

    // MARK: - Animation driver

    private func ensureDisplayLink() {
        // CADisplayLink の add(to:) は main run loop に対して main thread から呼ぶ前提。
        // 呼び出し元 (updateTiles → DispatchQueue.main.async) でその契約を満たしているが、
        // 将来別の経路から呼ばれても気付けるよう assert で固定する。
        assert(Thread.isMainThread, "ensureDisplayLink must be called on the main thread")
        // async 越えの間に effectsEnabled OFF / animatingTiles 空化が起きた場合、display link は不要。
        // ここで再確認しないと「次フレームで自滅」する displayLink が一瞬作られる無駄が出る。
        lock.lock()
        let stillNeeded = _effectsEnabled && !animatingTiles.isEmpty
        lock.unlock()
        guard stillNeeded, displayLink == nil else { return }
        // CADisplayLink は target を強参照するため、weak proxy を挟んで循環参照を防ぐ。
        let proxy = DisplayLinkProxy(target: self)
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
        displayLinkProxy = proxy
    }

    fileprivate func tickAnimation() {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        let hadAnimating = !animatingTiles.isEmpty
        animatingTiles = animatingTiles.filter { now - $0.value < revealAnimationDuration }
        let stillAnimating = !animatingTiles.isEmpty
        lock.unlock()
        if !stillAnimating {
            displayLink?.invalidate()
            displayLink = nil
            displayLinkProxy = nil
        }
        // 1フレーム前にすでに全タイル消化済みなら追加再描画は不要。
        if hadAnimating {
            setNeedsDisplay()
        }
    }

    // MARK: - Rendering

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let drawRect = rect(for: mapRect)

        // 1. ベースの霧（単色）
        context.setFillColor(fogColor)
        context.fill(drawRect)

        guard zoomScale >= minZoomScale else { return }

        lock.lock()
        let tiles = _tiles
        let useEffects = _effectsEnabled
        // useEffects=false なら animating コピーは不要 (アニメ自体走らない)。
        let animating = useEffects ? animatingTiles : [:]
        lock.unlock()

        // ビューポート端でのシーム回避: gradient 半径は最大 0.95 × max(w,h) tileSize 分外側に延びるので、
        // MapKit overlay tile の境界をまたいで halo の片側が描画されないことがある。
        // Mercator 投影下では緯度が上がるほど tile の縦横比が歪む (height/width = 1/cos(lat))。
        // 半径基準が max(w,h) なので、高緯度では水平方向に `0.95 / cos(lat)` タイル幅まで広がる。
        // サンプルタイルの width/height から拡張幅を動的に算出することで、極地でも halo の漏れを防ぐ。
        let (rawX, rawY) = TileCoord.tileRange(for: mapRect)
        let sampleTileRect = rect(for: TileCoord(x: rawX.lowerBound, y: rawY.lowerBound).mapRect)
        let inflateRadius = max(sampleTileRect.width, sampleTileRect.height) * 0.95
        let xPadding = max(1, Int(ceil(inflateRadius / sampleTileRect.width)))
        let yPadding = max(1, Int(ceil(inflateRadius / sampleTileRect.height)))
        let xRange = (rawX.lowerBound - xPadding)...(rawX.upperBound + xPadding)
        let yRange = (rawY.lowerBound - yPadding)...(rawY.upperBound + yPadding)

        // 2. 解放済みタイルで穴あけ。
        // タイル集合を走査して可視範囲のみフィルタする方式に変更した:
        //   - 旧: xRange×yRange の全セルを走査して tiles.contains() でルックアップ
        //   - 新: tiles を走査して xRange/yRange に入るものだけ描画
        // ズームアウト時にセル数が爆発しても O(tiles.count) で済む。これにより
        // 旧コードにあった "guard tileCount < 50_000 else { return }" のセーフガードが不要になり、
        // 広域表示でも霧が穴あけされ続ける。
        context.setBlendMode(.destinationOut)

        if useEffects {
            let now = CFAbsoluteTimeGetCurrent()
            for tile in tiles {
                guard xRange.contains(tile.x), yRange.contains(tile.y) else { continue }

                let tileRect = rect(for: tile.mapRect)
                let center = CGPoint(x: tileRect.midX, y: tileRect.midY)
                // 半径を 0.95 × max(w,h) に取ることで、対角に並ぶ 4 タイルが角で接する点
                // (中心から √2/2 ≈ 0.707 tileSize) まで確実に円が届き、霧の残りが出ない。
                // revealGradient 側のコア (locations 0..0.7) と組み合わせると、隣接タイル境界が完全クリアになる。
                let baseRadius = max(tileRect.width, tileRect.height) * 0.95

                // 新タイルなら radius と alpha を easeOutCubic でフェードイン。
                // 「霧がふっと押し退けられて晴れる」感を出す。
                var radiusScale: CGFloat = 1
                var alphaScale: CGFloat = 1
                if let start = animating[tile] {
                    let progress = min(max((now - start) / revealAnimationDuration, 0), 1)
                    let eased = 1 - pow(1 - progress, 3)
                    radiusScale = CGFloat(eased)
                    alphaScale = CGFloat(eased)
                }

                let radius = baseRadius * radiusScale
                if radius <= 0 { continue }

                if alphaScale < 0.999 {
                    context.saveGState()
                    context.setAlpha(alphaScale)
                    context.drawRadialGradient(
                        revealGradient,
                        startCenter: center, startRadius: 0,
                        endCenter: center, endRadius: radius,
                        options: []
                    )
                    context.restoreGState()
                } else {
                    context.drawRadialGradient(
                        revealGradient,
                        startCenter: center, startRadius: 0,
                        endCenter: center, endRadius: radius,
                        options: []
                    )
                }
            }
        } else {
            // OFF: オリジナルの単純な ellipse 塗り。境界はくっきり、アニメなし。
            context.setFillColor(clearColor)
            for tile in tiles {
                guard xRange.contains(tile.x), yRange.contains(tile.y) else { continue }
                let tileRect = rect(for: tile.mapRect)
                let insetRect = tileRect.insetBy(
                    dx: -tileRect.width * 0.2,
                    dy: -tileRect.height * 0.2
                )
                context.fillEllipse(in: insetRect)
            }
        }
    }
}

// CADisplayLink が target を強参照するため、weak proxy 経由で循環参照を回避する。
private final class DisplayLinkProxy: NSObject {
    weak var target: FogOverlayRenderer?

    init(target: FogOverlayRenderer) {
        self.target = target
    }

    @objc func tick() {
        target?.tickAnimation()
    }
}
