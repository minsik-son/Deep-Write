import UIKit

final class MercuryRippleView: UIView {

    // MARK: - Configuration
    private static let targetFPS: Int = 24
    private static let maxRipples: Int = 15
    private static let rippleSpeed: CGFloat = 180        // pts/sec 확산 속도
    private static let rippleMaxRadius: CGFloat = 200    // 최대 반경
    private static let rippleLifetime: CGFloat = 1.2     // 초

    static let perspectiveY: CGFloat = 1.0                // 완전한 원형 (원근감 없음)

    // MARK: - Ripple Snapshot (외부 노출용)
    struct RippleSnapshot {
        let centerX: CGFloat
        let centerY: CGFloat
        let radius: CGFloat
        let ringWidth: CGFloat
        let progress: CGFloat      // 0.0 → 1.0 (수명 진행도)
        let intensity: CGFloat     // 0.3 ~ 1.0
    }

    // MARK: - Ripple State
    private struct Ripple {
        let centerX: CGFloat
        let centerY: CGFloat
        let startTime: CFTimeInterval
        let intensity: CGFloat   // 0.5 ~ 1.0 (일반키 ~ 스페이스바)
    }

    private var ripples: [Ripple] = []
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private(set) var isAnimating = false
    private var lastTimestamp: CFTimeInterval = 0

    // MARK: - Color Palette (Deep Space Blue + Ice White ripple)
    // 배경은 KeyboardTheme.keyboardBackground가 처리하므로 여기선 물결만 그림
    private static let rippleColorR: CGFloat = 0.75
    private static let rippleColorG: CGFloat = 0.85
    private static let rippleColorB: CGFloat = 0.95

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
        isOpaque = false
        backgroundColor = .clear
        contentScaleFactor = 1.0   // 메모리 절약: 1x 해상도
        isUserInteractionEnabled = false
    }

    // MARK: - Public API

    var isActive: Bool { isAnimating }

    /// 터치 위치에 물결 추가
    func addRipple(at point: CGPoint, intensity: CGFloat = 0.7) {
        guard isAnimating else { return }

        // FIFO: 최대 개수 초과 시 오래된 것 제거
        if ripples.count >= Self.maxRipples {
            ripples.removeFirst()
        }

        let ripple = Ripple(
            centerX: point.x,
            centerY: point.y,
            startTime: CACurrentMediaTime(),
            intensity: min(max(intensity, 0.3), 1.0)
        )
        ripples.append(ripple)
    }

    func startAnimation() {
        guard !isAnimating else { return }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }

        isAnimating = true
        lastTimestamp = 0
        ripples.removeAll()

        let proxy = DisplayLinkProxy(target: self, action: #selector(animationTick(_:)))
        displayLinkProxy = proxy
        let dl = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.proxyTick(_:)))
        if #available(iOS 15.0, *) {
            dl.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: Float(Self.targetFPS))
        } else {
            dl.preferredFramesPerSecond = Self.targetFPS
        }
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    func stopAnimation() {
        guard isAnimating else { return }
        isAnimating = false
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil
        ripples.removeAll()
        setNeedsDisplay()
    }

    func pauseAnimation() {
        guard isAnimating else { return }
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil
        isAnimating = false
    }

    func resumeAnimation() {
        guard !isAnimating else { return }
        guard !ripples.isEmpty else { startAnimation(); return }

        isAnimating = true
        lastTimestamp = 0

        let proxy = DisplayLinkProxy(target: self, action: #selector(animationTick(_:)))
        displayLinkProxy = proxy
        let dl = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.proxyTick(_:)))
        if #available(iOS 15.0, *) {
            dl.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: Float(Self.targetFPS))
        } else {
            dl.preferredFramesPerSecond = Self.targetFPS
        }
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    // MARK: - Snapshot API (렌즈 효과용)

    /// 현재 활성 리플들의 기하 정보 스냅샷 반환
    func activeRippleSnapshots() -> [RippleSnapshot] {
        guard isAnimating, !ripples.isEmpty else { return [] }
        let now = CACurrentMediaTime()
        var snapshots: [RippleSnapshot] = []
        snapshots.reserveCapacity(ripples.count)

        for ripple in ripples {
            let age = CGFloat(now - ripple.startTime)
            let progress = age / Self.rippleLifetime
            guard progress >= 0, progress <= 1.0 else { continue }

            let radius = Self.rippleSpeed * age
            guard radius > 0 else { continue }

            let ringWidth = 5.0 + progress * radius * 0.18

            snapshots.append(RippleSnapshot(
                centerX: ripple.centerX,
                centerY: ripple.centerY,
                radius: radius,
                ringWidth: ringWidth,
                progress: progress,
                intensity: ripple.intensity
            ))
        }
        return snapshots
    }

    // MARK: - Animation Loop

    @objc private func animationTick(_ dl: CADisplayLink) {
        guard isAnimating else { return }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            stopAnimation()
            return
        }

        let now = CACurrentMediaTime()

        // 수명 초과한 리플 제거
        ripples.removeAll { now - $0.startTime > CFTimeInterval(Self.rippleLifetime) }

        // 리플이 없으면 draw 스킵 (idle 상태에서 CPU 절약)
        if ripples.isEmpty {
            // 마지막 프레임 한 번만 클리어
            if lastTimestamp != 0 {
                lastTimestamp = 0
                setNeedsDisplay()
            }
            return
        }

        lastTimestamp = now
        setNeedsDisplay()
    }

    // MARK: - Draw

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.clear(rect)

        guard !ripples.isEmpty else { return }

        let now = CACurrentMediaTime()
        let r = Self.rippleColorR
        let g = Self.rippleColorG
        let b = Self.rippleColorB

        for ripple in ripples {
            let age = CGFloat(now - ripple.startTime)
            let progress = age / Self.rippleLifetime   // 0.0 → 1.0

            guard progress >= 0, progress <= 1.0 else { continue }

            let radius = Self.rippleSpeed * age
            guard radius > 0 else { continue }

            // 물결 링 두께: 초기엔 실처럼 얇고(2pt), 점차 넓어짐
            let ringWidth = 2.0 + progress * radius * 0.12

            // 알파: 시작 시 밝고 점차 사라짐 (ease-out)
            let baseAlpha = ripple.intensity * (1.0 - progress * progress) * 0.5

            // 그라데이션 경계 물결 (5겹 서브링)
            drawSoftRing(ctx: ctx, cx: ripple.centerX, cy: ripple.centerY,
                         radius: radius, ringWidth: ringWidth,
                         r: r, g: g, b: b, peakAlpha: baseAlpha)
        }
    }

    /// 그라데이션 경계 물결 — 5겹 서브링으로 부드러운 페이드
    private func drawSoftRing(ctx: CGContext,
                               cx: CGFloat, cy: CGFloat,
                               radius: CGFloat, ringWidth: CGFloat,
                               r: CGFloat, g: CGFloat, b: CGFloat,
                               peakAlpha: CGFloat) {
        guard peakAlpha > 0.005 else { return }
        guard radius > 0 else { return }

        let steps = 5
        let stepWidth = ringWidth / CGFloat(steps)

        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        ctx.scaleBy(x: 1.0, y: Self.perspectiveY)

        for i in 0..<steps {
            // t: 0.1, 0.3, 0.5, 0.7, 0.9 (각 서브링의 중심 위치 비율)
            let t = (CGFloat(i) + 0.5) / CGFloat(steps)

            // cosine bell: 중앙(t=0.5)에서 최대, 양 끝(t=0, t=1)에서 0
            let bell = (cos((t - 0.5) * 2.0 * .pi) + 1.0) * 0.5
            let alpha = peakAlpha * bell
            guard alpha > 0.005 else { continue }

            // 서브링 위치: ring 중심(radius)에서 offset
            let offset = (t - 0.5) * ringWidth
            let subRadius = radius + offset
            let innerR = max(subRadius - stepWidth * 0.55, 0)  // 약간 겹침(0.55)으로 간극 방지
            let outerR = subRadius + stepWidth * 0.55

            let outerRect = CGRect(x: -outerR, y: -outerR, width: outerR * 2, height: outerR * 2)
            let innerRect = CGRect(x: -innerR, y: -innerR, width: innerR * 2, height: innerR * 2)
            ctx.addEllipse(in: outerRect)
            ctx.addEllipse(in: innerRect)
            ctx.setFillColor(red: r, green: g, blue: b, alpha: alpha)
            ctx.fillPath(using: .evenOdd)
        }

        ctx.restoreGState()
    }

    // MARK: - Cleanup
    deinit {
        displayLink?.invalidate()
        displayLink = nil
    }
}
