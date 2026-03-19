import UIKit

final class CherryBlossomView: UIView {

    // MARK: - Configuration

    /// 꽃잎 총 개수 — 메모리 최적화 위해 40개로 제한
    private static let petalCount = 40
    private static let targetFPS: Int = 20

    // MARK: - Petal Particle

    private struct Petal {
        var layer: CAShapeLayer
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var speed: CGFloat           // px/s 낙하 속도
        var horizontalSpeed: CGFloat // px/s 수평 이동 속도 (음수 = 왼쪽)
        var wobblePhase: CGFloat     // sin wave 위상
        var wobbleAmp: CGFloat       // sin wave 진폭
        var rotationSpeed: CGFloat   // rad/s
        var currentRotation: CGFloat
        var opacity: Float
        var variant: Int             // 꽃잎 모양 (0~3)
    }

    // MARK: - State

    private var petals: [Petal] = []
    private var flowerLayers: [CALayer] = []
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var lastTimestamp: CFTimeInterval = 0
    private(set) var isAnimating = false
    var isActive: Bool { isAnimating }

    /// 키보드 키들의 frame 배열
    var keyFrames: [CGRect] = []

    // MARK: - Pre-rendered petal paths (4가지 모양)

    /// 벚꽃잎 모양 — 끝이 뾰족하고 V노치
    private static func petalPath(size: CGFloat, variant: Int) -> UIBezierPath {
        let s = size
        let path = UIBezierPath()

        switch variant {
        case 0:
            // 클래식 벚꽃잎 — V노치 + 뾰족한 끝
            path.move(to: CGPoint(x: s * 0.5, y: s * 0.92))
            path.addCurve(to: CGPoint(x: s * 0.17, y: s * 0.25),
                          controlPoint1: CGPoint(x: s * 0.33, y: s * 0.67),
                          controlPoint2: CGPoint(x: s * 0.08, y: s * 0.50))
            path.addCurve(to: CGPoint(x: s * 0.44, y: s * 0.17),
                          controlPoint1: CGPoint(x: s * 0.21, y: s * 0.12),
                          controlPoint2: CGPoint(x: s * 0.33, y: s * 0.08))
            path.addLine(to: CGPoint(x: s * 0.5, y: s * 0.04))
            path.addLine(to: CGPoint(x: s * 0.56, y: s * 0.17))
            path.addCurve(to: CGPoint(x: s * 0.83, y: s * 0.25),
                          controlPoint1: CGPoint(x: s * 0.67, y: s * 0.08),
                          controlPoint2: CGPoint(x: s * 0.79, y: s * 0.12))
            path.addCurve(to: CGPoint(x: s * 0.5, y: s * 0.92),
                          controlPoint1: CGPoint(x: s * 0.92, y: s * 0.50),
                          controlPoint2: CGPoint(x: s * 0.67, y: s * 0.67))
            path.close()

        case 1:
            // 날카로운 타원 — 양쪽 끝 뾰족
            path.move(to: CGPoint(x: s * 0.5, y: s * 0.08))
            path.addCurve(to: CGPoint(x: s * 0.5, y: s * 0.92),
                          controlPoint1: CGPoint(x: s * 0.83, y: s * 0.33),
                          controlPoint2: CGPoint(x: s * 0.83, y: s * 0.67))
            path.addCurve(to: CGPoint(x: s * 0.5, y: s * 0.08),
                          controlPoint1: CGPoint(x: s * 0.17, y: s * 0.67),
                          controlPoint2: CGPoint(x: s * 0.17, y: s * 0.33))
            path.close()

        case 2:
            // 바람에 비틀린 반쪽 — 비대칭
            path.move(to: CGPoint(x: s * 0.42, y: s * 0.92))
            path.addCurve(to: CGPoint(x: s * 0.5, y: s * 0.04),
                          controlPoint1: CGPoint(x: s * 0.25, y: s * 0.67),
                          controlPoint2: CGPoint(x: s * 0.25, y: s * 0.21))
            path.addCurve(to: CGPoint(x: s * 0.42, y: s * 0.92),
                          controlPoint1: CGPoint(x: s * 0.63, y: s * 0.17),
                          controlPoint2: CGPoint(x: s * 0.58, y: s * 0.54))
            path.close()

        default:
            // 물방울형 — 작은 꽃잎
            path.move(to: CGPoint(x: s * 0.5, y: s * 0.08))
            path.addQuadCurve(to: CGPoint(x: s * 0.5, y: s * 0.92),
                              controlPoint: CGPoint(x: s * 0.83, y: s * 0.50))
            path.addQuadCurve(to: CGPoint(x: s * 0.5, y: s * 0.08),
                              controlPoint: CGPoint(x: s * 0.17, y: s * 0.50))
            path.close()
        }

        return path
    }

    // MARK: - Petal Colors

    private static let petalColors: [UIColor] = [
        UIColor(red: 1.0, green: 0.718, blue: 0.773, alpha: 1),   // #FFB7C5
        UIColor(red: 1.0, green: 0.784, blue: 0.839, alpha: 1),   // #FFC8D6
        UIColor(red: 1.0, green: 0.667, blue: 0.733, alpha: 1),   // #FFAABB
        UIColor(red: 1.0, green: 0.624, blue: 0.690, alpha: 1),   // #FF9FB0
        UIColor(red: 1.0, green: 0.816, blue: 0.855, alpha: 1),   // #FFD0DA
        UIColor(red: 1.0, green: 0.878, blue: 0.910, alpha: 1),   // #FFE0E8
        UIColor(red: 1.0, green: 0.659, blue: 0.722, alpha: 1),   // #FFA8B8
        UIColor(red: 1.0, green: 0.691, blue: 0.745, alpha: 1),   // #FFB0BE
    ]

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        contentScaleFactor = 1.0  // 메모리 절약
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public API

    func startAnimation() {
        guard !isAnimating else { return }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        isAnimating = true

        createFlowerCluster()
        createPetals()

        displayLink?.invalidate()
        let proxy = DisplayLinkProxy(target: self, action: #selector(animationTick(_:)))
        displayLinkProxy = proxy
        let dl = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.proxyTick(_:)))
        if #available(iOS 15.0, *) {
            dl.preferredFrameRateRange = CAFrameRateRange(
                minimum: 12, maximum: 24, preferred: Float(Self.targetFPS)
            )
        } else {
            dl.preferredFramesPerSecond = Self.targetFPS
        }
        dl.add(to: .main, forMode: .common)
        displayLink = dl
        lastTimestamp = 0
    }

    func stopAnimation() {
        isAnimating = false
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil
        removeAllPetals()
        removeFlowerCluster()
    }

    func pauseAnimation() {
        displayLink?.isPaused = true
    }

    func resumeAnimation() {
        displayLink?.isPaused = false
        lastTimestamp = 0
    }

    // MARK: - Flower Cluster (1시 방향 정적 벚꽃)

    private func createFlowerCluster() {
        removeFlowerCluster()

        let viewW = bounds.width > 0 ? bounds.width : 390
        let viewH = bounds.height > 0 ? bounds.height : 260

        // 꽃 클러스터 영역: 오른쪽 상단 (1시 방향)
        let clusterMinX = viewW * 0.72
        let clusterMaxX = viewW * 1.02
        let clusterMinY = viewH * -0.05
        let clusterMaxY = viewH * 0.28

        // 꽃잎 단일 경로 (재사용)
        func singlePetalPath(scale: CGFloat) -> UIBezierPath {
            let path = UIBezierPath()
            let s = scale
            path.move(to: CGPoint(x: 0, y: -7.5 * s))
            path.addCurve(to: CGPoint(x: -5 * s, y: 1 * s),
                          controlPoint1: CGPoint(x: -3 * s, y: -6 * s),
                          controlPoint2: CGPoint(x: -5.5 * s, y: -2 * s))
            path.addCurve(to: CGPoint(x: -1 * s, y: 4.5 * s),
                          controlPoint1: CGPoint(x: -4.5 * s, y: 3.5 * s),
                          controlPoint2: CGPoint(x: -2.5 * s, y: 5.5 * s))
            path.addLine(to: CGPoint(x: 0, y: 3.2 * s))
            path.addLine(to: CGPoint(x: 1 * s, y: 4.5 * s))
            path.addCurve(to: CGPoint(x: 5 * s, y: 1 * s),
                          controlPoint1: CGPoint(x: 2.5 * s, y: 5.5 * s),
                          controlPoint2: CGPoint(x: 4.5 * s, y: 3.5 * s))
            path.addCurve(to: CGPoint(x: 0, y: -7.5 * s),
                          controlPoint1: CGPoint(x: 5.5 * s, y: -2 * s),
                          controlPoint2: CGPoint(x: 3 * s, y: -6 * s))
            path.close()
            return path
        }

        struct FlowerSpec {
            let cx: CGFloat; let cy: CGFloat
            let scale: CGFloat; let opacity: Float
        }

        var specs: [FlowerSpec] = []

        // 뒤 레이어 (연하고 투명) — 20개
        for _ in 0..<20 {
            specs.append(FlowerSpec(
                cx: CGFloat.random(in: clusterMinX...clusterMaxX),
                cy: CGFloat.random(in: clusterMinY...clusterMaxY),
                scale: CGFloat.random(in: 0.6...1.2),
                opacity: Float.random(in: 0.3...0.55)
            ))
        }

        // 핵심부 (밀집, 큰 꽃) — 25개
        let coreMinX = viewW * 0.74
        let coreMaxX = viewW * 0.98
        let coreMaxY = viewH * 0.18
        for _ in 0..<25 {
            specs.append(FlowerSpec(
                cx: CGFloat.random(in: coreMinX...coreMaxX),
                cy: CGFloat.random(in: clusterMinY...coreMaxY),
                scale: CGFloat.random(in: 1.0...1.4),
                opacity: Float.random(in: 0.82...0.98)
            ))
        }

        // 중간부 (가지 따라 퍼짐) — 20개
        let midMinX = viewW * 0.65
        let midMaxX = viewW * 0.92
        let midMaxY = viewH * 0.25
        for _ in 0..<20 {
            specs.append(FlowerSpec(
                cx: CGFloat.random(in: midMinX...midMaxX),
                cy: CGFloat.random(in: clusterMinY + 15...midMaxY),
                scale: CGFloat.random(in: 0.8...1.2),
                opacity: Float.random(in: 0.7...0.95)
            ))
        }

        // 하단 가장자리 — 15개
        let bottomMinX = viewW * 0.68
        let bottomMaxX = viewW * 0.85
        for _ in 0..<15 {
            specs.append(FlowerSpec(
                cx: CGFloat.random(in: bottomMinX...bottomMaxX),
                cy: CGFloat.random(in: viewH * 0.15...viewH * 0.28),
                scale: CGFloat.random(in: 0.55...0.95),
                opacity: Float.random(in: 0.6...0.85)
            ))
        }

        // 오른쪽 위 모서리 — 10개
        for _ in 0..<10 {
            specs.append(FlowerSpec(
                cx: CGFloat.random(in: viewW * 0.92...viewW * 1.02),
                cy: CGFloat.random(in: clusterMinY...viewH * 0.12),
                scale: CGFloat.random(in: 0.65...1.15),
                opacity: Float.random(in: 0.55...0.85)
            ))
        }

        // 앞 오버랩 — 10개
        for _ in 0..<10 {
            specs.append(FlowerSpec(
                cx: CGFloat.random(in: viewW * 0.70...viewW * 0.97),
                cy: CGFloat.random(in: 0...viewH * 0.22),
                scale: CGFloat.random(in: 0.7...1.1),
                opacity: Float.random(in: 0.7...0.92)
            ))
        }

        // 3개 합성 CAShapeLayer로 렌더 (back/mid/front)
        let backLayer = CAShapeLayer()
        let midLayer = CAShapeLayer()
        let frontLayer = CAShapeLayer()

        let backPath = UIBezierPath()
        let midPath = UIBezierPath()
        let frontPath = UIBezierPath()

        for (i, spec) in specs.enumerated() {
            autoreleasepool {  // Phase 9: 500개 UIBezierPath 생성 시 transient spike 방지
                let targetPath: UIBezierPath
                if i < 20 {
                    targetPath = backPath
                } else if i < 65 {
                    targetPath = midPath
                } else {
                    targetPath = frontPath
                }

                let baseAngle = CGFloat.random(in: 0...(CGFloat.pi * 2 / 5))
                for j in 0..<5 {
                    let angle = baseAngle + CGFloat(j) * (CGFloat.pi * 2.0 / 5.0)
                    let petal = singlePetalPath(scale: spec.scale)

                    var transform = CGAffineTransform.identity
                    transform = transform.translatedBy(x: spec.cx, y: spec.cy)
                    transform = transform.rotated(by: angle)
                    petal.apply(transform)

                    targetPath.append(petal)
                }
            }
        }

        backLayer.path = backPath.cgPath
        backLayer.fillColor = UIColor(red: 1.0, green: 0.85, blue: 0.89, alpha: 0.45).cgColor
        backLayer.strokeColor = nil
        layer.addSublayer(backLayer)
        flowerLayers.append(backLayer)

        midLayer.path = midPath.cgPath
        midLayer.fillColor = UIColor(red: 1.0, green: 0.80, blue: 0.85, alpha: 0.75).cgColor
        midLayer.strokeColor = nil
        layer.addSublayer(midLayer)
        flowerLayers.append(midLayer)

        frontLayer.path = frontPath.cgPath
        frontLayer.fillColor = UIColor(red: 1.0, green: 0.78, blue: 0.84, alpha: 0.88).cgColor
        frontLayer.strokeColor = nil
        layer.addSublayer(frontLayer)
        flowerLayers.append(frontLayer)

        // 꽃술 점 레이어 (작은 노란 점들)
        let stamenLayer = CAShapeLayer()
        let stamenPath = UIBezierPath()
        for i in 20..<min(45, specs.count) {
            let spec = specs[i]
            let dotCount = Int.random(in: 3...5)
            for _ in 0..<dotCount {
                let angle = CGFloat.random(in: 0...(CGFloat.pi * 2))
                let r = spec.scale * CGFloat.random(in: 1.5...3.0)
                let dotX = spec.cx + cos(angle) * r
                let dotY = spec.cy + sin(angle) * r
                let dotR = spec.scale * 0.4
                stamenPath.append(UIBezierPath(
                    arcCenter: CGPoint(x: dotX, y: dotY),
                    radius: dotR,
                    startAngle: 0, endAngle: .pi * 2,
                    clockwise: true
                ))
            }
        }
        stamenLayer.path = stamenPath.cgPath
        stamenLayer.fillColor = UIColor(red: 1.0, green: 0.92, blue: 0.63, alpha: 0.6).cgColor
        stamenLayer.strokeColor = nil
        layer.addSublayer(stamenLayer)
        flowerLayers.append(stamenLayer)
    }

    private func removeFlowerCluster() {
        flowerLayers.forEach { $0.removeFromSuperlayer() }
        flowerLayers.removeAll()
    }

    // MARK: - Petal Creation

    private func createPetals() {
        removeAllPetals()

        let viewW = bounds.width > 0 ? bounds.width : 390
        let viewH = bounds.height > 0 ? bounds.height : 260

        for _ in 0..<Self.petalCount {
            let petal = makePetal(viewW: viewW, viewH: viewH, randomizeY: true)
            petals.append(petal)
        }
    }

    private func makePetal(viewW: CGFloat, viewH: CGFloat, randomizeY: Bool) -> Petal {
        let size = CGFloat.random(in: 6...14)
        let variant = Int.random(in: 0...3)
        let color = Self.petalColors[Int.random(in: 0..<Self.petalColors.count)]

        let shapeLayer = CAShapeLayer()
        shapeLayer.path = Self.petalPath(size: size, variant: variant).cgPath
        shapeLayer.fillColor = color.cgColor
        shapeLayer.strokeColor = nil
        shapeLayer.bounds = CGRect(x: 0, y: 0, width: size, height: size)

        // 시작 위치: 1시 방향 (오른쪽 상단)
        let startX = viewW * 0.58 + CGFloat.random(in: 0...viewW * 0.42)
        let startY = randomizeY
            ? CGFloat.random(in: -viewH * 0.1...viewH)
            : CGFloat.random(in: -size * 2...viewH * 0.15)

        shapeLayer.position = CGPoint(x: startX, y: startY)

        let maxOpacity = Float.random(in: 0.55...0.85)
        shapeLayer.opacity = maxOpacity

        layer.addSublayer(shapeLayer)

        // 방향 다양화: 메인 7시(70%) + 9시(15%) + 수직(15%)
        let dirRoll = CGFloat.random(in: 0...1)
        let hSpeed: CGFloat
        let vSpeed: CGFloat

        if dirRoll < 0.70 {
            // 7시 방향 — 왼쪽 아래 대각선 (속도 절반)
            hSpeed = CGFloat.random(in: -40 ... -15)
            vSpeed = CGFloat.random(in: 20...40)
        } else if dirRoll < 0.85 {
            // 9시 방향 — 거의 수평 (속도 절반)
            hSpeed = CGFloat.random(in: -50 ... -25)
            vSpeed = CGFloat.random(in: 8...18)
        } else {
            // 수직 낙하 (속도 절반)
            hSpeed = CGFloat.random(in: -8...3)
            vSpeed = CGFloat.random(in: 25...45)
        }

        return Petal(
            layer: shapeLayer,
            x: startX,
            y: startY,
            size: size,
            speed: vSpeed,
            horizontalSpeed: hSpeed,
            wobblePhase: CGFloat.random(in: 0...(2 * .pi)),
            wobbleAmp: CGFloat.random(in: 8...25),
            rotationSpeed: CGFloat.random(in: -2...2),
            currentRotation: CGFloat.random(in: 0...(2 * .pi)),
            opacity: maxOpacity,
            variant: variant
        )
    }

    private func removeAllPetals() {
        petals.forEach { $0.layer.removeFromSuperlayer() }
        petals.removeAll()
    }

    // MARK: - Animation Tick

    @objc private func animationTick(_ displayLink: CADisplayLink) {
        guard isAnimating else { return }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            stopAnimation()
            return
        }

        let now = CACurrentMediaTime()
        if lastTimestamp == 0 { lastTimestamp = now; return }
        let dt = CGFloat(now - lastTimestamp)
        lastTimestamp = now

        guard dt > 0 && dt < 0.5 else { return }

        let viewW = bounds.width > 0 ? bounds.width : 390
        let viewH = bounds.height > 0 ? bounds.height : 260

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for i in petals.indices {
            updatePetal(&petals[i], dt: dt, viewW: viewW, viewH: viewH)
        }

        CATransaction.commit()
    }

    private func updatePetal(_ petal: inout Petal, dt: CGFloat, viewW: CGFloat, viewH: CGFloat) {
        // 낙하 + 수평이동
        petal.y += petal.speed * dt
        petal.x += petal.horizontalSpeed * dt

        // 좌우 wobble (sin wave)
        petal.wobblePhase += dt * 0.6
        let sway = sin(petal.wobblePhase) * petal.wobbleAmp * 0.3
        petal.x += sway

        // 회전
        petal.currentRotation += petal.rotationSpeed * dt

        // 화면 밖으로 나가면 위(1시방향)에서 리셋
        if petal.y > viewH + 20 || petal.x < -30 || petal.x > viewW + 30 {
            resetPetal(&petal, viewW: viewW, viewH: viewH)
        }

        petal.layer.position = CGPoint(x: petal.x, y: petal.y)
        petal.layer.transform = CATransform3DMakeRotation(petal.currentRotation, 0, 0, 1)

        // 키 영역 지날 때 opacity 감소 (유리 뒤 효과)
        var behindKey = false
        for frame in keyFrames {
            if frame.contains(petal.layer.position) {
                behindKey = true
                break
            }
        }
        let targetOpacity = behindKey ? petal.opacity * 0.4 : petal.opacity

        // Fade-in/out at edges
        let fadeInZone: CGFloat = 25
        let fadeOutZone: CGFloat = 35
        var finalOpacity = targetOpacity
        if petal.y < fadeInZone {
            finalOpacity *= Float(max(0, petal.y / fadeInZone))
        } else if petal.y > viewH - fadeOutZone {
            finalOpacity *= Float(max(0, (viewH - petal.y) / fadeOutZone))
        }

        petal.layer.opacity = finalOpacity
    }

    private func resetPetal(_ petal: inout Petal, viewW: CGFloat, viewH: CGFloat) {
        // 1시 방향에서 리스폰
        petal.x = viewW * 0.58 + CGFloat.random(in: 0...viewW * 0.42)
        petal.y = CGFloat.random(in: -petal.size * 2...viewH * 0.1)
        petal.wobblePhase = CGFloat.random(in: 0...(2 * .pi))
        petal.currentRotation = CGFloat.random(in: 0...(2 * .pi))

        // 방향 재랜덤
        let dirRoll = CGFloat.random(in: 0...1)
        if dirRoll < 0.70 {
            petal.horizontalSpeed = CGFloat.random(in: -40 ... -15)
            petal.speed = CGFloat.random(in: 20...40)
        } else if dirRoll < 0.85 {
            petal.horizontalSpeed = CGFloat.random(in: -50 ... -25)
            petal.speed = CGFloat.random(in: 8...18)
        } else {
            petal.horizontalSpeed = CGFloat.random(in: -8...3)
            petal.speed = CGFloat.random(in: 25...45)
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard isAnimating, bounds.width > 0, bounds.height > 0 else { return }
        let viewW = bounds.width
        let viewH = bounds.height
        for i in petals.indices {
            if petals[i].x > viewW {
                petals[i].x = CGFloat.random(in: 0...viewW)
            }
            if petals[i].y > viewH {
                petals[i].y = CGFloat.random(in: -viewH * 0.3...0)
            }
            petals[i].layer.position = CGPoint(x: petals[i].x, y: petals[i].y)
        }
    }

    // MARK: - Cleanup

    deinit {
        displayLink?.invalidate()
        displayLink = nil
    }
}
