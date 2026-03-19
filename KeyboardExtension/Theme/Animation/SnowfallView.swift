import UIKit

final class SnowfallView: UIView {

    // MARK: - Configuration
    private static let particleCount = 50
    private static let targetFPS: Int = 24

    // MARK: - Particle
    private struct Snowflake {
        var layer: CALayer
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
        var speed: CGFloat          // px/s
        var drift: CGFloat          // px/s lateral amplitude
        var driftPhase: CGFloat     // sin wave phase
        var opacity: Float
    }

    // MARK: - State
    private var snowflakes: [Snowflake] = []
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var lastTimestamp: CFTimeInterval = 0
    private(set) var isActive = false

    /// 키보드 키들의 frame 배열. KeyboardLayoutView에서 업데이트.
    var keyFrames: [CGRect] = []

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Public API

    func startAnimation() {
        guard !isActive else { return }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { return }
        isActive = true

        createSnowflakes()

        displayLink?.invalidate()
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
        lastTimestamp = 0
    }

    func stopAnimation() {
        isActive = false
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil
        removeAllSnowflakes()
    }

    func pauseAnimation() {
        displayLink?.isPaused = true
    }

    func resumeAnimation() {
        displayLink?.isPaused = false
        lastTimestamp = 0
    }

    // MARK: - Snowflake Creation

    private func createSnowflakes() {
        removeAllSnowflakes()

        let viewH = bounds.height > 0 ? bounds.height : 340
        let viewW = bounds.width > 0 ? bounds.width : 390

        for _ in 0..<Self.particleCount {
            let size = CGFloat.random(in: 2...6)
            let snowLayer = CALayer()
            snowLayer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            snowLayer.cornerRadius = size / 2
            snowLayer.backgroundColor = UIColor.white.cgColor
            snowLayer.shadowColor = UIColor.white.cgColor
            snowLayer.shadowOffset = .zero
            snowLayer.shadowRadius = size * 0.5
            snowLayer.shadowOpacity = 0.6

            let x = CGFloat.random(in: 0...viewW)
            let y = CGFloat.random(in: -viewH...viewH)
            snowLayer.position = CGPoint(x: x, y: y)

            let maxOpacity = Float.random(in: 0.5...0.9)
            snowLayer.opacity = maxOpacity

            layer.addSublayer(snowLayer)

            snowflakes.append(Snowflake(
                layer: snowLayer,
                x: x, y: y,
                size: size,
                speed: CGFloat.random(in: 30...70),
                drift: CGFloat.random(in: -8...8),
                driftPhase: CGFloat.random(in: 0...(2 * .pi)),
                opacity: maxOpacity
            ))
        }
    }

    private func removeAllSnowflakes() {
        snowflakes.forEach { $0.layer.removeFromSuperlayer() }
        snowflakes.removeAll()
    }

    // MARK: - Animation Tick

    @objc private func animationTick(_ displayLink: CADisplayLink) {
        guard isActive else { return }

        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            stopAnimation()
            return
        }

        let now = CACurrentMediaTime()
        if lastTimestamp == 0 { lastTimestamp = now; return }
        let dt = CGFloat(now - lastTimestamp)
        lastTimestamp = now

        guard dt > 0 && dt < 0.5 else { return }

        let viewH = bounds.height > 0 ? bounds.height : 340
        let viewW = bounds.width > 0 ? bounds.width : 390

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for i in snowflakes.indices {
            updateSnowflake(&snowflakes[i], dt: dt, viewW: viewW, viewH: viewH)
        }

        CATransaction.commit()
    }

    private func updateSnowflake(_ flake: inout Snowflake, dt: CGFloat, viewW: CGFloat, viewH: CGFloat) {
        // 낙하
        flake.y += flake.speed * dt

        // 좌우 drift (sin wave)
        flake.driftPhase += dt * 0.8
        let sway = sin(flake.driftPhase) * flake.drift
        flake.x += sway * dt

        // 화면 아래로 벗어나면 위로 리셋
        if flake.y > viewH + 10 {
            flake.y = -flake.size
            flake.x = CGFloat.random(in: 0...viewW)
            flake.driftPhase = CGFloat.random(in: 0...(2 * .pi))
        }

        // 좌우 wrap
        if flake.x < -10 { flake.x = viewW + 5 }
        if flake.x > viewW + 10 { flake.x = -5 }

        flake.layer.position = CGPoint(x: flake.x, y: flake.y)

        // 키 영역을 지나갈 때 opacity 감소 (유리 뒤 효과)
        var behindKey = false
        for frame in keyFrames {
            if frame.contains(flake.layer.position) {
                behindKey = true
                break
            }
        }
        let targetOpacity = behindKey ? flake.opacity * 0.45 : flake.opacity

        // Fade-in at top, fade-out at bottom
        let fadeInZone: CGFloat = 20
        let fadeOutZone: CGFloat = 30
        var finalOpacity = targetOpacity
        if flake.y < fadeInZone {
            finalOpacity *= Float(max(0, flake.y / fadeInZone))
        } else if flake.y > viewH - fadeOutZone {
            finalOpacity *= Float(max(0, (viewH - flake.y) / fadeOutZone))
        }

        flake.layer.opacity = finalOpacity
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard isActive, bounds.width > 0, bounds.height > 0 else { return }
        let viewW = bounds.width
        let viewH = bounds.height
        for i in snowflakes.indices {
            if snowflakes[i].x > viewW {
                snowflakes[i].x = CGFloat.random(in: 0...viewW)
            }
            if snowflakes[i].y > viewH {
                snowflakes[i].y = CGFloat.random(in: -viewH * 0.3...0)
            }
            snowflakes[i].layer.position = CGPoint(x: snowflakes[i].x, y: snowflakes[i].y)
        }
    }

    // MARK: - Cleanup
    deinit {
        displayLink?.invalidate()
        displayLink = nil
    }
}
