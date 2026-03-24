import UIKit

final class KeyPreviewView: UIView {

    // MARK: - UI Components
    private let textLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 28, weight: .regular)
        return label
    }()

    private let bubbleLayer = CAShapeLayer()

    // MARK: - Constants
    private struct Config {
        static let bubbleWidthMultiplier: CGFloat = 1.2
        static let bubbleHeight: CGFloat = 56
        static let stemHeight: CGFloat = 8
        static let cornerRadius: CGFloat = 8
        static let minStemHeight: CGFloat = 2
        static let edgePadding: CGFloat = 2
        static let shadowOpacity: Float = 0.15
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
        let totalH = Config.bubbleHeight + Config.stemHeight

        var originX = keyFrame.midX - bubbleW / 2
        originX = max(Config.edgePadding,
                      min(originX, parentBounds.width - bubbleW - Config.edgePadding))

        var originY = keyFrame.minY - totalH
        var actualStemH = Config.stemHeight

        if originY < Config.edgePadding {
            let overflow = Config.edgePadding - originY
            actualStemH = max(Config.minStemHeight, Config.stemHeight - overflow)
            originY = Config.edgePadding
        }

        frame = CGRect(x: originX, y: originY, width: bubbleW, height: Config.bubbleHeight + actualStemH)

        let bubbleRect = CGRect(x: 0, y: 0, width: bubbleW, height: Config.bubbleHeight)
        let path = UIBezierPath(roundedRect: bubbleRect, cornerRadius: Config.cornerRadius)

        let stemCenterX = keyFrame.midX - originX
        let stemW: CGFloat = 12
        let stemTop = Config.bubbleHeight
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
        textLabel.frame = bubbleRect

        isHidden = false
    }

    func hide() {
        isHidden = true
    }
}
