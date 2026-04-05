import UIKit

/// 토스 스타일 인라인 성공 애니메이션 — 초록 원 + 체크 마크 + 성공 문구.
final class SuccessCheckAnimationView: UIView {

    private let circleView = UIView()
    private let checkLayer = CAShapeLayer()
    private let titleLabel = UILabel()
    private let descLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        buildUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildUI()
    }

    private func buildUI() {
        backgroundColor = .white
        alpha = 0

        // Circle
        circleView.backgroundColor = UIColor.systemGreen
        circleView.layer.cornerRadius = 30
        circleView.translatesAutoresizingMaskIntoConstraints = false
        circleView.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
        addSubview(circleView)

        // Check mark
        checkLayer.fillColor = nil
        checkLayer.strokeColor = UIColor.white.cgColor
        checkLayer.lineWidth = 3.5
        checkLayer.lineCap = .round
        checkLayer.lineJoin = .round
        checkLayer.strokeEnd = 0
        circleView.layer.addSublayer(checkLayer)

        // Title
        titleLabel.text = L("onboarding.verify.success_title_inline")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.alpha = 0
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // Description
        descLabel.text = L("onboarding.verify.success_desc_inline")
        descLabel.font = .systemFont(ofSize: 15)
        descLabel.textColor = .secondaryLabel
        descLabel.textAlignment = .center
        descLabel.alpha = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(descLabel)

        NSLayoutConstraint.activate([
            circleView.centerXAnchor.constraint(equalTo: centerXAnchor),
            circleView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),
            circleView.widthAnchor.constraint(equalToConstant: 60),
            circleView.heightAnchor.constraint(equalToConstant: 60),

            titleLabel.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            descLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            descLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let s: CGFloat = 60
        let path = UIBezierPath()
        path.move(to: CGPoint(x: s * 0.25, y: s * 0.50))
        path.addLine(to: CGPoint(x: s * 0.42, y: s * 0.67))
        path.addLine(to: CGPoint(x: s * 0.75, y: s * 0.35))
        checkLayer.path = path.cgPath
        checkLayer.frame = CGRect(x: 0, y: 0, width: s, height: s)
    }

    /// 성공 애니메이션 재생
    func playAnimation() {
        alpha = 1

        // Circle scale
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5) {
            self.circleView.transform = .identity
        }

        // Check stroke
        let strokeAnim = CABasicAnimation(keyPath: "strokeEnd")
        strokeAnim.fromValue = 0
        strokeAnim.toValue = 1
        strokeAnim.duration = 0.35
        strokeAnim.beginTime = CACurrentMediaTime() + 0.25
        strokeAnim.fillMode = .forwards
        strokeAnim.isRemovedOnCompletion = false
        checkLayer.add(strokeAnim, forKey: "checkStroke")

        // Title + desc fade in
        UIView.animate(withDuration: 0.3, delay: 0.5) {
            self.titleLabel.alpha = 1
            self.descLabel.alpha = 1
        }
    }
}
