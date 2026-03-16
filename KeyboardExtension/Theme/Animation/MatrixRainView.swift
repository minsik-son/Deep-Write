import UIKit

/// 영화 매트릭스 스타일 떨어지는 코드 애니메이션 배경 뷰
final class MatrixRainView: UIView {

    // MARK: - Configuration

    private static let targetFPS: Int = 12
    private static let charSize: CGFloat = 14
    private static let columnWidth: CGFloat = 16

    /// 반복 사용할 문자 목록 (카타카나 + 숫자 + 알파벳)
    private static let characters: [String] = {
        var chars: [String] = []
        // Half-width katakana (U+FF66 - U+FF9D)
        for code in 0xFF66...0xFF9D {
            if let scalar = Unicode.Scalar(code) {
                chars.append(String(scalar))
            }
        }
        // Digits
        for c in "0123456789" { chars.append(String(c)) }
        // Uppercase
        for c in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" { chars.append(String(c)) }
        return chars
    }()

    // MARK: - Pre-rendered Character Images (메인스레드 보장)

    /// 흰색 문자 CGImage 캐시 — draw 시 CGContext tint로 색상 적용
    /// 메인스레드에서만 초기화 (UIGraphicsImageRenderer가 UIKit API이므로)
    private static var _characterImages: [CGImage]?

    /// 캐시된 문자 이미지 배열 반환. 미초기화 시 빈 배열 반환 (draw 스킵됨)
    private static var characterImages: [CGImage] {
        return _characterImages ?? []
    }

    /// 메인스레드에서 문자 이미지 캐시 초기화 — startAnimation()에서 호출
    private static func ensureCharacterImages() {
        assert(Thread.isMainThread, "ensureCharacterImages must be called on main thread")
        guard _characterImages == nil else { return }

        let font = UIFont(name: "Menlo", size: charSize)
            ?? UIFont.monospacedSystemFont(ofSize: charSize, weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let size = CGSize(width: charSize, height: charSize)

        _characterImages = characters.compactMap { char in
            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { _ in
                char.draw(at: .zero, withAttributes: attrs)
            }
            return image.cgImage
        }
    }

    /// 메모리 워닝 시 문자 이미지 캐시 해제 — 다음 startAnimation()에서 재생성됨
    static func clearCharacterImageCache() {
        _characterImages = nil
    }

    // MARK: - Color Palette (pre-cached — v3 색상 개선)

    /// 20단계 색상 팔레트: index 0 = head (밝은 흰-초록), index 19 = tail (어두운 초록)
    private static let colorPalette: [(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)] = {
        var colors: [(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)] = []
        for i in 0..<20 {
            let t = CGFloat(i) / 19.0
            let r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
            if t < 0.05 {
                // Head: 은은한 밝은 초록 (소폭 밝기 증가)
                r = 0.18; g = 0.65; b = 0.22; a = 0.55
            } else if t < 0.15 {
                // Near head: 초록 전이 (은은하게)
                let fade = (t - 0.05) / 0.10
                r = 0.18 - fade * 0.18
                g = 0.65 - fade * 0.17
                b = 0.22 - fade * 0.14
                a = 0.55 - fade * 0.12
            } else {
                // Trail: 어두운 초록으로 페이드 (소폭 밝기 증가)
                let fade = (t - 0.15) / 0.85
                r = 0.0
                g = 0.48 - fade * 0.36
                b = 0.10 - fade * 0.06
                a = max(0.43 - fade * 0.36, 0.05)
            }
            colors.append((r, g, b, a))
        }
        return colors
    }()

    // MARK: - Column State

    private struct Trail {
        var headY: CGFloat
        var chars: [Int]
        var changeCountdown: Int
    }

    private struct RainColumn {
        var speed: CGFloat
        var trailLength: CGFloat
        var trails: [Trail]  // 항상 2개
    }

    private var columns: [RainColumn] = []

    // MARK: - Animation State

    private var rainDisplayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var isAnimating = false
    private var needsStop = false

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        isOpaque = false
        contentScaleFactor = 1.0
        isUserInteractionEnabled = false
        clearsContextBeforeDrawing = true
    }

    // MARK: - Lifecycle

    func startAnimation() {
        guard !isAnimating else { return }

        Self.ensureCharacterImages()
        guard !Self.characterImages.isEmpty else { return }

        rainDisplayLink?.invalidate()
        rainDisplayLink = nil
        needsStop = false

        isAnimating = true
        initializeColumns()

        let dl = CADisplayLink(target: self, selector: #selector(animationTick))
        if #available(iOS 15.0, *) {
            dl.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 12)
        } else {
            dl.preferredFramesPerSecond = Self.targetFPS
        }
        dl.add(to: .main, forMode: .common)
        rainDisplayLink = dl
        lastTimestamp = 0
    }

    /// 애니메이션 정지 — idempotent (여러 번 호출 안전)
    func stopAnimation() {
        needsStop = false
        isAnimating = false
        rainDisplayLink?.invalidate()
        rainDisplayLink = nil
        columns.removeAll()
        setNeedsDisplay()
    }

    var isActive: Bool { isAnimating }

    // MARK: - Pause / Resume (columns 데이터 유지)

    /// 애니메이션 일시정지 — CADisplayLink만 해제, columns 데이터 유지
    func pauseAnimation() {
        guard isAnimating else { return }
        rainDisplayLink?.invalidate()
        rainDisplayLink = nil
        isAnimating = false
    }

    /// 일시정지된 애니메이션 재개 — 기존 columns 위치에서 이어서 재생
    func resumeAnimation() {
        guard !isAnimating else { return }

        guard !columns.isEmpty else {
            startAnimation()
            return
        }

        guard !Self.characterImages.isEmpty else {
            startAnimation()
            return
        }

        isAnimating = true
        needsStop = false
        lastTimestamp = 0

        let dl = CADisplayLink(target: self, selector: #selector(animationTick))
        if #available(iOS 15.0, *) {
            dl.preferredFrameRateRange = CAFrameRateRange(minimum: 8, maximum: 15, preferred: 12)
        } else {
            dl.preferredFramesPerSecond = Self.targetFPS
        }
        dl.add(to: .main, forMode: .common)
        rainDisplayLink = dl
    }

    // MARK: - Column Initialization

    private func initializeColumns() {
        columns.removeAll()
        let viewWidth = bounds.width > 0 ? bounds.width : 400
        let viewHeight = bounds.height > 0 ? bounds.height : 300
        let numColumns = Int(viewWidth / Self.columnWidth)

        for _ in 0..<numColumns {
            columns.append(createColumn(viewHeight: viewHeight, staggered: true))
        }
    }

    private func createColumn(viewHeight: CGFloat, staggered: Bool) -> RainColumn {
        let maxVisibleChars = Int(viewHeight / Self.charSize) + 5
        let speed = CGFloat.random(in: 150...220)
        let trailLength = CGFloat.random(in: 550...700)

        // Trail A: 메인 트레일
        let startYA: CGFloat = staggered
            ? -CGFloat.random(in: 0...(viewHeight * 0.8))
            : -CGFloat.random(in: 20...120)
        let charsA = (0..<maxVisibleChars).map { _ in
            Int.random(in: 0..<Self.characters.count)
        }
        let trailA = Trail(
            headY: startYA,
            chars: charsA,
            changeCountdown: Int.random(in: 4...18)
        )

        // Trail B: Trail A 뒤를 잇는 두 번째 트레일
        let startYB = startYA - trailLength - CGFloat.random(in: 0...30)
        let charsB = (0..<maxVisibleChars).map { _ in
            Int.random(in: 0..<Self.characters.count)
        }
        let trailB = Trail(
            headY: startYB,
            chars: charsB,
            changeCountdown: Int.random(in: 4...18)
        )

        return RainColumn(
            speed: speed,
            trailLength: trailLength,
            trails: [trailA, trailB]
        )
    }

    /// 단일 트레일 재생성 — 화면 밖으로 나간 트레일만 리셋
    private func createTrail(viewHeight: CGFloat, siblingHeadY: CGFloat, trailLength: CGFloat) -> Trail {
        let maxVisibleChars = Int(viewHeight / Self.charSize) + 5
        let chars = (0..<maxVisibleChars).map { _ in
            Int.random(in: 0..<Self.characters.count)
        }
        let siblingTailY = siblingHeadY - trailLength
        let startY = min(siblingTailY - CGFloat.random(in: 0...30), -CGFloat.random(in: 20...120))
        return Trail(
            headY: startY,
            chars: chars,
            changeCountdown: Int.random(in: 4...18)
        )
    }

    // MARK: - Animation Tick

    @objc private func animationTick() {
        if needsStop {
            stopAnimation()
            return
        }

        guard isAnimating else { return }
        guard let dl = rainDisplayLink else { return }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            needsStop = true
            return
        }

        let timestamp = dl.timestamp
        let dt: CGFloat
        if lastTimestamp == 0 || timestamp <= lastTimestamp {
            dt = 1.0 / CGFloat(Self.targetFPS)
        } else {
            dt = min(CGFloat(timestamp - lastTimestamp), 0.1)
        }
        lastTimestamp = timestamp

        let viewHeight = bounds.height
        guard viewHeight > 0 else { return }

        for i in columns.indices {
            let speed = columns[i].speed
            let trailLen = columns[i].trailLength

            for t in columns[i].trails.indices {
                columns[i].trails[t].headY += speed * dt

                if columns[i].trails[t].headY - trailLen > viewHeight {
                    let siblingIdx = (t == 0) ? 1 : 0
                    let siblingHeadY = columns[i].trails[siblingIdx].headY
                    columns[i].trails[t] = createTrail(
                        viewHeight: viewHeight,
                        siblingHeadY: siblingHeadY,
                        trailLength: trailLen
                    )
                }

                columns[i].trails[t].changeCountdown -= 1
                if columns[i].trails[t].changeCountdown <= 0 {
                    let chars = columns[i].trails[t].chars
                    if !chars.isEmpty {
                        let randIdx = Int.random(in: 0..<chars.count)
                        columns[i].trails[t].chars[randIdx] = Int.random(in: 0..<Self.characters.count)
                    }
                    columns[i].trails[t].changeCountdown = Int.random(in: 4...18)
                }
            }
        }

        setNeedsDisplay()
    }

    // MARK: - Drawing (v3: UIKit 네이티브 좌표계 — context flip 제거)

    override func draw(_ rect: CGRect) {
        guard isAnimating, !columns.isEmpty else { return }
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let viewHeight = bounds.height
        let charH = Self.charSize
        let paletteCount = Self.colorPalette.count
        let charImages = Self.characterImages

        guard !charImages.isEmpty else { return }

        for (colIdx, col) in columns.enumerated() {
            let x = CGFloat(colIdx) * Self.columnWidth + 1

            for trail in col.trails {
                let headCharRow = Int(trail.headY / charH)
                let tailY = trail.headY - col.trailLength
                let tailCharRow = max(0, Int(tailY / charH))

                guard headCharRow >= 0 else { continue }
                guard tailCharRow <= headCharRow else { continue }

                for charRow in tailCharRow...headCharRow {
                    let y = CGFloat(charRow) * charH

                    guard y >= -charH, y < viewHeight + charH else { continue }

                    let distFromHead = trail.headY - y
                    let normalized = distFromHead / col.trailLength

                    guard normalized >= 0, normalized <= 1.0 else { continue }

                    let paletteIdx = min(Int(normalized * CGFloat(paletteCount)), paletteCount - 1)

                    let charIdx = abs(charRow) % trail.chars.count
                    let imageIdx = trail.chars[charIdx]
                    guard imageIdx < charImages.count else { continue }
                    let charImage = charImages[imageIdx]

                    let drawRect = CGRect(x: x, y: y, width: charH, height: charH)

                    let color = Self.colorPalette[paletteIdx]

                    ctx.saveGState()
                    ctx.clip(to: drawRect, mask: charImage)
                    ctx.setFillColor(red: color.r, green: color.g, blue: color.b, alpha: color.a)
                    ctx.fill(drawRect)
                    ctx.restoreGState()
                }
            }
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        if isAnimating && !columns.isEmpty {
            let expectedCols = Int(bounds.width / Self.columnWidth)
            if abs(expectedCols - columns.count) > 2 {
                initializeColumns()
            }
        }
    }

    // MARK: - Cleanup

    deinit {
        rainDisplayLink?.invalidate()
        rainDisplayLink = nil
    }
}
