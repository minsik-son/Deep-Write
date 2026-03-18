import UIKit

final class StardustView: UIView {

    // MARK: - Configuration
    private static let targetFPS: Int = 24
    private static let maxParticles: Int = 100
    private static let particleLifetime: CGFloat = 2.0       // 초
    private static let burstCount: Int = 6                   // 일반 키 burst 파티클 수
    private static let supernovaBurstCount: Int = 12         // 스페이스바 burst

    // 이동 방향: 우상단 (약 30도)
    private static let driftDirX: CGFloat = 0.5
    private static let driftDirY: CGFloat = -0.866
    private static let driftSpeed: CGFloat = 30              // pts/sec 기본 이동속도

    // MARK: - Particle State
    private struct Particle {
        var x: CGFloat
        var y: CGFloat
        var vx: CGFloat                // velocity x
        var vy: CGFloat                // velocity y
        let startTime: CFTimeInterval
        let size: CGFloat              // 2.0 ~ 5.0
        let colorIndex: Int            // 0~3 (4가지 색상)
        let brightness: CGFloat        // 0.6 ~ 1.0
    }

    private var particles: [Particle] = []
    private var displayLink: CADisplayLink?
    private(set) var isAnimating = false
    private var lastTimestamp: CFTimeInterval = 0

    // MARK: - Pre-rendered Spark Images (4가지 색상)
    private static var sparkImages: [CGImage] = []

    // 색상 팔레트: 네온 블루, 골드, 핑크, 화이트
    private static let sparkColors: [(r: CGFloat, g: CGFloat, b: CGFloat)] = [
        (0.40, 0.60, 1.00),   // 네온 블루
        (1.00, 0.85, 0.40),   // 골드
        (1.00, 0.50, 0.75),   // 핑크
        (0.90, 0.92, 1.00),   // 쿨 화이트
    ]

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
        contentScaleFactor = 1.0
        isUserInteractionEnabled = false

        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { _ in
            StardustView.clearSparkImageCache()
        }
    }

    // MARK: - Spark Image Cache

    private static func ensureSparkImages() {
        guard sparkImages.isEmpty else { return }
        assert(Thread.isMainThread, "ensureSparkImages must be called on main thread")

        let size: CGFloat = 8
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))

        for color in sparkColors {
            let img = renderer.image { ctx in
                let rect = CGRect(x: 1, y: 1, width: size - 2, height: size - 2)
                ctx.cgContext.setFillColor(CGColor(red: color.r, green: color.g, blue: color.b, alpha: 1.0))
                ctx.cgContext.fillEllipse(in: rect)
            }
            if let cgImage = img.cgImage {
                sparkImages.append(cgImage)
            }
        }
    }

    /// Phase 5: static 캐시 메모리 해제
    static func clearSparkImageCache() {
        sparkImages.removeAll()
    }

    // MARK: - Public API

    var isActive: Bool { isAnimating }

    /// 터치 위치에 스파크 burst 추가
    func addBurst(at point: CGPoint, isSupernova: Bool = false) {
        guard isAnimating else { return }

        Self.ensureSparkImages()

        let count = isSupernova ? Self.supernovaBurstCount : Self.burstCount
        let now = CACurrentMediaTime()

        for _ in 0..<count {
            // FIFO: 최대 개수 초과 시 오래된 것 제거
            if particles.count >= Self.maxParticles {
                particles.removeFirst()
            }

            // 방사형 초기 속도 (랜덤 각도 + 드릿트 방향 합산)
            let angle = CGFloat.random(in: 0 ..< .pi * 2)
            let burstSpeed = CGFloat.random(in: 20...80) * (isSupernova ? 1.5 : 1.0)
            let vx = cos(angle) * burstSpeed + Self.driftDirX * Self.driftSpeed
            let vy = sin(angle) * burstSpeed + Self.driftDirY * Self.driftSpeed

            let particle = Particle(
                x: point.x + CGFloat.random(in: -3...3),
                y: point.y + CGFloat.random(in: -3...3),
                vx: vx,
                vy: vy,
                startTime: now,
                size: CGFloat.random(in: isSupernova ? 3.0...6.0 : 2.0...4.0),
                colorIndex: Int.random(in: 0..<Self.sparkColors.count),
                brightness: CGFloat.random(in: 0.6...1.0)
            )
            particles.append(particle)
        }
    }

    // MARK: - Animation Lifecycle

    func startAnimation() {
        guard !isAnimating else { return }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }

        Self.ensureSparkImages()
        isAnimating = true
        lastTimestamp = 0
        particles.removeAll()

        let dl = CADisplayLink(target: WeakProxy(target: self), selector: #selector(animationTick))
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
        particles.removeAll()
        setNeedsDisplay()
    }

    func pauseAnimation() {
        guard isAnimating else { return }
        displayLink?.invalidate()
        displayLink = nil
        isAnimating = false
    }

    func resumeAnimation() {
        guard !isAnimating else { return }
        guard !particles.isEmpty else { startAnimation(); return }

        isAnimating = true
        lastTimestamp = 0

        let dl = CADisplayLink(target: WeakProxy(target: self), selector: #selector(animationTick))
        if #available(iOS 15.0, *) {
            dl.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: Float(Self.targetFPS))
        } else {
            dl.preferredFramesPerSecond = Self.targetFPS
        }
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    // MARK: - Animation Loop

    @objc private func animationTick(_ dl: CADisplayLink) {
        guard isAnimating else { return }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            stopAnimation()
            return
        }

        let now = CACurrentMediaTime()
        let dt: CGFloat
        if lastTimestamp == 0 {
            dt = 1.0 / CGFloat(Self.targetFPS)
        } else {
            dt = min(CGFloat(now - lastTimestamp), 0.1)   // 최대 100ms cap
        }
        lastTimestamp = now

        // 수명 초과 파티클 제거
        particles.removeAll { now - $0.startTime > CFTimeInterval(Self.particleLifetime) }

        // 위치 업데이트 (속도 감쇠 적용)
        for i in particles.indices {
            particles[i].x += particles[i].vx * dt
            particles[i].y += particles[i].vy * dt

            // 속도 감쇠 (마찰): 매 프레임 2% 감소
            particles[i].vx *= 0.98
            particles[i].vy *= 0.98
        }

        // 파티클이 없으면 draw 스킵
        if particles.isEmpty {
            if lastTimestamp != 0 {
                lastTimestamp = 0
                setNeedsDisplay()
            }
            return
        }

        setNeedsDisplay()
    }

    // MARK: - Draw

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.clear(rect)

        guard !particles.isEmpty, !Self.sparkImages.isEmpty else { return }

        let now = CACurrentMediaTime()

        for particle in particles {
            let age = CGFloat(now - particle.startTime)
            let progress = age / Self.particleLifetime
            guard progress >= 0, progress <= 1.0 else { continue }

            // 알파: fade out (ease-out cubic)
            let alpha = particle.brightness * (1.0 - progress) * (1.0 - progress) * 0.85

            guard alpha > 0.01 else { continue }

            let imgIndex = particle.colorIndex % Self.sparkImages.count
            let sparkImg = Self.sparkImages[imgIndex]

            // 스파크가 나이가 들수록 약간 커짐 (팽창)
            let scale = 1.0 + progress * 0.5
            let drawSize = particle.size * scale

            let drawRect = CGRect(
                x: particle.x - drawSize * 0.5,
                y: particle.y - drawSize * 0.5,
                width: drawSize,
                height: drawSize
            )

            // sparkImage를 마스크로 사용하고, 색상 + 알파로 fill
            let color = Self.sparkColors[imgIndex]
            ctx.saveGState()
            ctx.clip(to: drawRect, mask: sparkImg)
            ctx.setFillColor(CGColor(red: color.r, green: color.g, blue: color.b, alpha: alpha))
            ctx.fill(drawRect)
            ctx.restoreGState()
        }
    }

    // MARK: - Cleanup
    deinit {
        NotificationCenter.default.removeObserver(self)
        displayLink?.invalidate()
        displayLink = nil
    }
}
