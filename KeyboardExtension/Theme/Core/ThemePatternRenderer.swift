import UIKit

final class ThemePatternRenderer {

    /// 직렬 큐: NSCache 접근의 원자성 보장 (null 체크 → 생성 → setObject race condition 방지)
    private static let cacheQueue = DispatchQueue(label: "com.translatorkeyboard.patternCache")

    /// NSCache: OS 메모리 압박 시 자동 퇴거(eviction). countLimit=5로 동시 보유 패턴 제한.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 5
        c.totalCostLimit = 5 * 1024 * 1024  // 5MB 상한
        return c
    }()

    static func patternImage(style: PatternStyle, tint: UIColor, opacity: CGFloat, size: CGSize = CGSize(width: 64, height: 64)) -> UIImage? {
        guard style != .none else { return nil }

        let key = "\(style)-\(tint.hexString)-\(opacity)-\(size.width)x\(size.height)"
        let nsKey = key as NSString

        // ── 직렬 큐로 원자적 캐시 접근 ──
        return cacheQueue.sync {
            if let cached = cache.object(forKey: nsKey) { return cached }

            let renderer = UIGraphicsImageRenderer(size: size)
            let image = renderer.image { ctx in
                let rect = CGRect(origin: .zero, size: size)
                UIColor.clear.setFill()
                ctx.fill(rect)

                switch style {
                case .stars:
                    drawStars(in: ctx.cgContext, rect: rect, tint: tint, opacity: opacity)
                case .noise:
                    drawNoise(in: ctx.cgContext, rect: rect, tint: tint, opacity: opacity)
                case .aurora:
                    drawAurora(in: ctx.cgContext, rect: rect, tint: tint, opacity: opacity)
                case .metalLines:
                    drawMetalLines(in: ctx.cgContext, rect: rect, tint: tint, opacity: opacity)
                case .petals:
                    drawPetals(in: ctx.cgContext, rect: rect, tint: tint, opacity: opacity)
                case .bubbles:
                    drawBubbles(in: ctx.cgContext, rect: rect, tint: tint, opacity: opacity)
                case .woodGrain:
                    drawWoodGrain(in: ctx.cgContext, rect: rect, tint: tint, opacity: opacity)
                case .matrixRain:
                    drawMatrixRain(in: ctx.cgContext, rect: rect, tint: tint, opacity: opacity)
                case .ripple:
                    drawRipple(in: ctx.cgContext, rect: rect, tint: tint, opacity: opacity)
                case .edgeGlow:
                    drawEdgeGlow(in: ctx.cgContext, rect: rect, tint: tint, opacity: opacity)
                case .snowfall:
                    break  // 눈 파티클은 SnowfallView에서 처리, 패턴 이미지 불필요
                case .cherryBlossom:
                    break  // 벚꽃 파티클은 CherryBlossomView에서 처리
                case .none:
                    break
                }
            }

            cache.setObject(image, forKey: nsKey)
            return image
        }
    }

    static func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - Pattern Drawing Methods (고정값 — 랜덤 없음)

    private static func drawStars(in ctx: CGContext, rect: CGRect, tint: UIColor, opacity: CGFloat) {
        let positions: [(x: CGFloat, y: CGFloat, radius: CGFloat, alpha: CGFloat)] = [
            (0.12, 0.15, 0.72, 0.65), (0.35, 0.08, 0.48, 0.50), (0.58, 0.25, 0.60, 0.75),
            (0.82, 0.18, 0.84, 0.55), (0.25, 0.55, 0.36, 0.40), (0.48, 0.42, 0.60, 0.70),
            (0.72, 0.62, 0.48, 0.45), (0.90, 0.45, 0.72, 0.60), (0.15, 0.78, 0.60, 0.50),
            (0.55, 0.85, 0.36, 0.35), (0.78, 0.82, 0.48, 0.55), (0.40, 0.68, 0.42, 0.45)
        ]
        for pos in positions {
            let x = rect.width * pos.x
            let y = rect.height * pos.y
            let r = pos.radius * 1.2
            ctx.setFillColor(tint.withAlphaComponent(opacity * pos.alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
    }

    private static func drawNoise(in ctx: CGContext, rect: CGRect, tint: UIColor, opacity: CGFloat) {
        let step: CGFloat = 4
        var ix = 0
        for x in stride(from: CGFloat(0), to: rect.width, by: step) {
            var iy = 0
            for y in stride(from: CGFloat(0), to: rect.height, by: step) {
                let hash = ((ix &* 7) &+ (iy &* 13)) % 17
                let a = opacity * CGFloat(hash) / 17.0
                ctx.setFillColor(tint.withAlphaComponent(a).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: step, height: step))
                iy += 1
            }
            ix += 1
        }
    }

    private static func drawAurora(in ctx: CGContext, rect: CGRect, tint: UIColor, opacity: CGFloat) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 0, y: rect.height * 0.3))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.25),
                          controlPoint: CGPoint(x: rect.width * 0.25, y: rect.height * 0.15))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: rect.height * 0.3),
                          controlPoint: CGPoint(x: rect.width * 0.75, y: rect.height * 0.35))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height * 0.4))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.38),
                          controlPoint: CGPoint(x: rect.width * 0.75, y: rect.height * 0.45))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.height * 0.4),
                          controlPoint: CGPoint(x: rect.width * 0.25, y: rect.height * 0.3))
        path.close()
        ctx.setFillColor(tint.withAlphaComponent(opacity).cgColor)
        ctx.addPath(path.cgPath)
        ctx.fillPath()
    }

    private static func drawMetalLines(in ctx: CGContext, rect: CGRect, tint: UIColor, opacity: CGFloat) {
        ctx.setStrokeColor(tint.withAlphaComponent(opacity).cgColor)
        ctx.setLineWidth(0.3)
        let spacing: CGFloat = 2
        for y in stride(from: CGFloat(0), to: rect.height, by: spacing) {
            ctx.move(to: CGPoint(x: 0, y: y))
            ctx.addLine(to: CGPoint(x: rect.width, y: y))
        }
        ctx.strokePath()
    }

    private static func drawPetals(in ctx: CGContext, rect: CGRect, tint: UIColor, opacity: CGFloat) {
        let petals: [(x: CGFloat, y: CGFloat, rx: CGFloat, angle: CGFloat, alpha: CGFloat)] = [
            (0.15, 0.12, 3.5, -30, 0.40), (0.55, 0.45, 2.5, 15, 0.35),
            (0.80, 0.20, 3.0, -45, 0.45), (0.30, 0.70, 2.8, 20, 0.38),
            (0.70, 0.60, 2.2, -15, 0.42), (0.45, 0.85, 3.0, 10, 0.35),
            (0.85, 0.80, 2.5, 35, 0.40), (0.10, 0.50, 2.0, -20, 0.37)
        ]
        for p in petals {
            ctx.saveGState()
            let cx = rect.width * p.x
            let cy = rect.height * p.y
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: p.angle * .pi / 180)
            ctx.setFillColor(tint.withAlphaComponent(opacity * p.alpha).cgColor)
            ctx.fillEllipse(in: CGRect(x: -p.rx, y: -p.rx * 0.5, width: p.rx * 2, height: p.rx))
            ctx.restoreGState()
        }
    }

    private static func drawBubbles(in ctx: CGContext, rect: CGRect, tint: UIColor, opacity: CGFloat) {
        let bubbles: [(x: CGFloat, y: CGFloat, r: CGFloat, alpha: CGFloat)] = [
            (0.18, 0.60, 3.0, 0.40), (0.35, 0.40, 2.0, 0.35), (0.55, 0.70, 2.5, 0.45),
            (0.72, 0.50, 3.2, 0.38), (0.85, 0.65, 2.8, 0.42), (0.28, 0.25, 1.5, 0.30),
            (0.62, 0.30, 2.0, 0.40), (0.90, 0.20, 1.8, 0.35), (0.15, 0.85, 2.5, 0.45),
            (0.50, 0.90, 1.6, 0.38)
        ]
        ctx.setLineWidth(0.5)
        for b in bubbles {
            let cx = rect.width * b.x
            let cy = rect.height * b.y
            ctx.setStrokeColor(tint.withAlphaComponent(opacity * b.alpha).cgColor)
            ctx.strokeEllipse(in: CGRect(x: cx - b.r, y: cy - b.r, width: b.r * 2, height: b.r * 2))
        }
    }

    private static func drawWoodGrain(in ctx: CGContext, rect: CGRect, tint: UIColor, opacity: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        tint.getRed(&r, green: &g, blue: &b, alpha: &a)

        let w = Int(rect.width)
        let h = Int(rect.height)

        // 1. Horizontal grain lines (sin wave)
        for y in 0..<h {
            let wave = sin(Double(y) * 0.15) * 0.3 + sin(Double(y) * 0.07) * 0.5
            let grainIntensity = (wave + 1.0) / 2.0
            let alpha = CGFloat(grainIntensity) * opacity * 0.6

            ctx.setStrokeColor(UIColor(red: r, green: g, blue: b, alpha: alpha).cgColor)
            ctx.setLineWidth(0.5)
            ctx.move(to: CGPoint(x: rect.origin.x, y: rect.origin.y + CGFloat(y)))
            ctx.addLine(to: CGPoint(x: rect.origin.x + rect.width, y: rect.origin.y + CGFloat(y)))
            ctx.strokePath()
        }

        // 2. Fine pore noise (deterministic hash)
        let step: CGFloat = 3
        var ix = 0
        for x in stride(from: CGFloat(0), to: CGFloat(w), by: step) {
            var iy = 0
            for y in stride(from: CGFloat(0), to: CGFloat(h), by: step) {
                let hash = ((ix &* 7) &+ (iy &* 13)) % 17
                let noiseAlpha = opacity * CGFloat(hash) / 17.0 * 0.2

                if noiseAlpha > 0.02 {
                    ctx.setFillColor(UIColor(red: r * 0.6, green: g * 0.6, blue: b * 0.6, alpha: noiseAlpha).cgColor)
                    ctx.fill(CGRect(x: rect.origin.x + x, y: rect.origin.y + CGFloat(y), width: 1, height: 1))
                }
                iy += 1
            }
            ix += 1
        }
    }

    private static func drawRipple(in ctx: CGContext, rect: CGRect, tint: UIColor, opacity: CGFloat) {
        // 정적 프리뷰: 비대칭 동심원 3개 (물결 퍼지는 느낌)
        let centerX = rect.width * 0.4
        let centerY = rect.height * 0.45

        for i in 1...3 {
            let radius = CGFloat(i) * 12.0
            let ringWidth: CGFloat = 2.5
            let ringAlpha = opacity * CGFloat(4 - i) / 3.0

            let ringRect = CGRect(
                x: centerX - radius,
                y: centerY - radius,
                width: radius * 2,
                height: radius * 2
            )

            ctx.setStrokeColor(tint.withAlphaComponent(ringAlpha).cgColor)
            ctx.setLineWidth(ringWidth)
            ctx.strokeEllipse(in: ringRect)
        }
    }

    private static func drawMatrixRain(in ctx: CGContext, rect: CGRect, tint: UIColor, opacity: CGFloat) {
        let cols = 16
        let rows = 16
        let cellW = rect.width / CGFloat(cols)
        let cellH = rect.height / CGFloat(rows)

        for col in 0..<cols {
            for row in 0..<rows {
                let hash = ((col &* 31) &+ (row &* 17) &+ 7) % 23
                guard hash < 8 else { continue }

                let intensity = CGFloat(hash + 1) / 8.0
                let alpha = opacity * intensity * 0.6

                let x = CGFloat(col) * cellW + cellW * 0.3
                let y = CGFloat(row) * cellH + cellH * 0.3
                let dotSize = cellW * 0.4 * intensity

                ctx.setFillColor(tint.withAlphaComponent(alpha).cgColor)
                ctx.fill(CGRect(x: x, y: y, width: dotSize, height: dotSize * 1.5))
            }
        }
    }

    // MARK: - Edge Glow Preview

    private static func drawEdgeGlow(in ctx: CGContext, rect: CGRect, tint: UIColor, opacity: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        tint.getRed(&r, green: &g, blue: &b, alpha: &a)

        // 미니 키 그리드 (3x2) — 테두리만 그리기
        let cols = 3, rows = 2
        let padding: CGFloat = 4
        let gap: CGFloat = 3
        let keyW = (rect.width - padding * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let keyH = (rect.height - padding * 2 - gap * CGFloat(rows - 1)) / CGFloat(rows)

        for row in 0..<rows {
            for col in 0..<cols {
                let x = padding + CGFloat(col) * (keyW + gap)
                let y = padding + CGFloat(row) * (keyH + gap)
                let keyRect = CGRect(x: x, y: y, width: keyW, height: keyH).insetBy(dx: 0.5, dy: 0.5)

                // 웨이브 시뮬레이션: 대각선(11→5시) 방향 밝기
                let norm = (CGFloat(col) / CGFloat(cols - 1) * 0.5 + CGFloat(row) / CGFloat(rows - 1) * 0.866)
                let wave = (sin(norm * .pi * 2 - .pi * 0.3) + 1.0) / 2.0
                let alpha = opacity + wave * (1.0 - opacity) * 0.7

                // 키 배경 (매우 어두운 초록 틴트)
                ctx.setFillColor(red: r * 0.05, green: g * 0.05, blue: b * 0.05, alpha: alpha * 0.3)
                let path = UIBezierPath(roundedRect: keyRect, cornerRadius: 3)
                ctx.addPath(path.cgPath)
                ctx.fillPath()

                // 키 테두리 (초록 레이저)
                ctx.setStrokeColor(red: r, green: g, blue: b, alpha: alpha * 0.6)
                ctx.setLineWidth(0.8)
                ctx.addPath(path.cgPath)
                ctx.strokePath()
            }
        }
    }
}
