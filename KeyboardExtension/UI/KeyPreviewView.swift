import UIKit

final class KeyPreviewView: UIView {

    // MARK: - UI Components
    private let textLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        // font는 configure()에서 largeFont/smallFont 캐시로 설정
        return label
    }()

    private let bubbleLayer = CAShapeLayer()

    // 캐시된 폰트 (매 configure() 호출 시 .systemFont() 재생성 방지)
    private let largeFont = UIFont.systemFont(ofSize: 28, weight: .regular)
    private let smallFont = UIFont.systemFont(ofSize: 20, weight: .regular)

    // MARK: - Constants
    private struct Config {
        static let bubbleWidthMultiplier: CGFloat = 1.2
        static let bubbleHeight: CGFloat = 56
        static let stemHeight: CGFloat = 8
        static let cornerRadius: CGFloat = 8
        static let minStemHeight: CGFloat = 2
        static let edgePadding: CGFloat = 2
        static let shadowOpacity: Float = 0.15

        // 축소 프리뷰 (1열 키 등 위 공간 부족 시)
        static let minBubbleHeight: CGFloat = 36
        static let largeFontSize: CGFloat = 28
        static let smallFontSize: CGFloat = 20
        // 프리뷰 표시 최소 필요 공간
        static let minAvailableSpace: CGFloat = 38  // minBubbleHeight + minStemHeight
    }

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.insertSublayer(bubbleLayer, at: 0)
        addSubview(textLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Configure

    func configure(text: String,
                   sourceButton: UIButton,
                   parentBounds: CGRect,
                   theme: KeyboardTheme? = nil,
                   isDark: Bool = false) {
        guard let sv = sourceButton.superview else { return }
        let keyFrame = sv.convert(sourceButton.frame, to: superview)

        let bubbleW = max(keyFrame.width * Config.bubbleWidthMultiplier, 36)

        // ── X 위치 (기존과 동일) ──
        var originX = keyFrame.midX - bubbleW / 2
        originX = max(Config.edgePadding,
                      min(originX, parentBounds.width - bubbleW - Config.edgePadding))

        // ── Y 위치 (v2: 공간 부족 시 축소, 극도 부족 시 숨김) ──
        let availableAbove = keyFrame.minY - Config.edgePadding

        // 공간 극도 부족 → 프리뷰 숨김 (숫자행 키 등)
        if availableAbove < Config.minAvailableSpace {
            isHidden = true
            return
        }

        // 공간에 맞는 버블 높이 결정
        let fullTotalH = Config.bubbleHeight + Config.stemHeight   // 64pt
        let effectiveBubbleH: CGFloat
        let useSmallFont: Bool
        var actualStemH = Config.stemHeight

        if availableAbove >= fullTotalH {
            // 충분한 공간 — 기본 크기
            effectiveBubbleH = Config.bubbleHeight
            useSmallFont = false
        } else {
            // 부족 — 버블 높이 축소
            actualStemH = max(Config.minStemHeight, min(Config.stemHeight, availableAbove - Config.minBubbleHeight))
            effectiveBubbleH = availableAbove - actualStemH
            useSmallFont = true
        }

        let totalH = effectiveBubbleH + actualStemH
        var originY = keyFrame.minY - totalH

        // 안전 클램프 (극단적 케이스 방어)
        if originY < Config.edgePadding {
            originY = Config.edgePadding
        }

        frame = CGRect(x: originX, y: originY, width: bubbleW, height: effectiveBubbleH + actualStemH)

        let bubbleRect = CGRect(x: 0, y: 0, width: bubbleW, height: effectiveBubbleH)
        let path = UIBezierPath(roundedRect: bubbleRect, cornerRadius: Config.cornerRadius)

        let stemCenterX = keyFrame.midX - originX
        let stemW: CGFloat = 12
        let stemTop = effectiveBubbleH
        path.move(to: CGPoint(x: stemCenterX - stemW / 2, y: stemTop))
        path.addLine(to: CGPoint(x: stemCenterX, y: stemTop + actualStemH))
        path.addLine(to: CGPoint(x: stemCenterX + stemW / 2, y: stemTop))
        path.close()

        bubbleLayer.path = path.cgPath

        if let theme = theme {
            bubbleLayer.fillColor = theme.keyBackground.cgColor
            textLabel.textColor = theme.keyTextColor
        } else {
            bubbleLayer.fillColor = isDark
                ? UIColor(white: 0.35, alpha: 1.0).cgColor
                : UIColor.white.cgColor
            textLabel.textColor = isDark ? .white : .black
        }

        bubbleLayer.shadowColor = UIColor.black.cgColor
        bubbleLayer.shadowOffset = CGSize(width: 0, height: 1)
        bubbleLayer.shadowOpacity = Config.shadowOpacity
        bubbleLayer.shadowRadius = 3

        textLabel.text = text
        textLabel.font = useSmallFont ? smallFont : largeFont
        textLabel.frame = bubbleRect

        isHidden = false
    }

    func hide() {
        isHidden = true
    }
}
