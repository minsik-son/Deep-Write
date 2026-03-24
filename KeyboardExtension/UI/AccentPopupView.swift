import UIKit

class AccentPopupView: UIView {

    private var accentLabels: [UILabel] = []
    private var selectedIndex: Int = -1
    private let cellWidth: CGFloat = 36
    private let cellHeight: CGFloat = 42
    private var storedTheme: KeyboardTheme?

    var selectedCharacter: String? {
        guard selectedIndex >= 0, selectedIndex < accentLabels.count else { return nil }
        return accentLabels[selectedIndex].text
    }

    func configure(accents: [String], sourceFrame: CGRect, in parentView: UIView, theme: KeyboardTheme? = nil, isDark: Bool = false) {
        subviews.forEach { $0.removeFromSuperview() }
        accentLabels.removeAll()
        selectedIndex = -1
        storedTheme = theme

        let totalWidth = cellWidth * CGFloat(accents.count)
        let popupHeight = cellHeight

        // Position above the source key, centered
        let centerX = sourceFrame.midX
        var originX = centerX - totalWidth / 2
        // Clamp to parent bounds
        originX = max(4, min(originX, parentView.bounds.width - totalWidth - 4))
        // Y-clamp — prevent going above top edge
        var originY = sourceFrame.minY - popupHeight - 4
        originY = max(2, originY)

        frame = CGRect(x: originX, y: originY, width: totalWidth, height: popupHeight)

        if let theme = theme {
            backgroundColor = theme.keyBackground
        } else {
            backgroundColor = UIColor.systemBackground
        }
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 4
        clipsToBounds = false

        for (i, accent) in accents.enumerated() {
            let label = UILabel()
            label.text = accent
            label.font = .systemFont(ofSize: 22)
            label.textAlignment = .center
            label.frame = CGRect(x: cellWidth * CGFloat(i), y: 0, width: cellWidth, height: popupHeight)
            label.layer.cornerRadius = 6
            label.clipsToBounds = true
            addSubview(label)
            accentLabels.append(label)
        }
    }

    func updateSelection(at point: CGPoint) {
        // Convert point to local coordinates
        let localPoint = convert(point, from: superview)
        let newIndex: Int
        if bounds.contains(localPoint) {
            newIndex = Int(localPoint.x / cellWidth)
        } else if localPoint.x < 0 {
            newIndex = 0
        } else if localPoint.x >= bounds.width {
            newIndex = accentLabels.count - 1
        } else {
            newIndex = -1
        }

        guard newIndex != selectedIndex else { return }

        // Deselect previous
        if selectedIndex >= 0, selectedIndex < accentLabels.count {
            accentLabels[selectedIndex].backgroundColor = .clear
            accentLabels[selectedIndex].textColor = .label
        }

        selectedIndex = newIndex

        // Select new
        if selectedIndex >= 0, selectedIndex < accentLabels.count {
            accentLabels[selectedIndex].backgroundColor = storedTheme?.returnKeyAccentColor ?? UIColor.systemBlue
            accentLabels[selectedIndex].textColor = .white
        }
    }
}
