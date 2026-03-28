import UIKit

final class ToolbarCustomizationViewController: UIViewController {

    // MARK: - Data

    private var currentItems: [ToolbarItemType] = []
    private var originalItems: [ToolbarItemType] = []
    private let allAvailableItems: [ToolbarItemType] = ToolbarItemType.allCases.filter { $0 != .settings }
    private var isEditMode = false
    private let maxSlots = 8

    // MARK: - UI

    private lazy var editButton: UIBarButtonItem = {
        UIBarButtonItem(title: L("settings.toolbar.edit"), style: .plain, target: self, action: #selector(toggleEditMode))
    }()

    private lazy var previewCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 48, height: 48)
        layout.minimumInteritemSpacing = 12
        layout.sectionInset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.showsHorizontalScrollIndicator = false
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.delegate = self
        cv.dataSource = self
        cv.register(ToolbarPreviewCell.self, forCellWithReuseIdentifier: ToolbarPreviewCell.reuseId)
        cv.register(ToolbarEmptySlotCell.self, forCellWithReuseIdentifier: ToolbarEmptySlotCell.reuseId)
        return cv
    }()

    private let separatorView: UIView = {
        let v = UIView()
        v.backgroundColor = .separator
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var gridCollectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        let spacing: CGFloat = 16
        let columns: CGFloat = 4
        let totalSpacing = spacing * (columns + 1)
        let itemWidth = (UIScreen.main.bounds.width - totalSpacing) / columns
        layout.itemSize = CGSize(width: itemWidth, height: 90)
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing
        layout.sectionInset = UIEdgeInsets(top: 16, left: spacing, bottom: 16, right: spacing)

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.delegate = self
        cv.dataSource = self
        cv.register(ToolbarGridCell.self, forCellWithReuseIdentifier: ToolbarGridCell.reuseId)
        return cv
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("settings.toolbar.title")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = editButton

        currentItems = ToolbarConfiguration.load()
        originalItems = currentItems
        setupLayout()
        setupDragAndDrop()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isEditMode && currentItems != originalItems {
            ToolbarConfiguration.save(currentItems)
        }
    }

    private func setupLayout() {
        view.addSubview(previewCollectionView)
        view.addSubview(separatorView)
        view.addSubview(gridCollectionView)

        NSLayoutConstraint.activate([
            previewCollectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            previewCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewCollectionView.heightAnchor.constraint(equalToConstant: 60),

            separatorView.topAnchor.constraint(equalTo: previewCollectionView.bottomAnchor, constant: 16),
            separatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            separatorView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            separatorView.heightAnchor.constraint(equalToConstant: 0.5),

            gridCollectionView.topAnchor.constraint(equalTo: separatorView.bottomAnchor),
            gridCollectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            gridCollectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            gridCollectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Edit Mode

    @objc private func toggleEditMode() {
        isEditMode.toggle()
        editButton.title = isEditMode ? L("settings.toolbar.save") : L("settings.toolbar.edit")

        if !isEditMode {
            ToolbarConfiguration.save(currentItems)
            originalItems = currentItems
        }

        previewCollectionView.reloadData()
        gridCollectionView.reloadData()
    }

    // MARK: - Helpers

    private func iconName(for item: ToolbarItemType) -> String {
        switch item {
        case .settings:     return "icon_toolbar_settings"
        case .emoji:        return "icon_toolbar_emoji"
        case .clipboard:    return "icon_toolbar_clipboard"
        case .savedPhrases: return "icon_toolbar_savedphrases"
        case .quickNote:    return "icon_toolbar_quicknote"
        case .correction:   return "icon_toolbar_correction"
        case .translation:  return "icon_toolbar_translation"
        case .calculator:   return "plus.forwardslash.minus"
        case .chatReplyGenerator: return "icon_toolbar_chat_reply"
        }
    }

    private func displayName(for item: ToolbarItemType) -> String {
        switch item {
        case .settings:     return L("settings.toolbar.item.settings")
        case .emoji:        return L("settings.toolbar.item.emoji")
        case .clipboard:    return L("settings.toolbar.item.clipboard")
        case .savedPhrases: return L("settings.toolbar.item.savedPhrases")
        case .quickNote:    return L("settings.toolbar.item.quickNote")
        case .correction:   return L("settings.toolbar.item.correction")
        case .translation:  return L("settings.toolbar.item.translation")
        case .calculator:   return L("settings.toolbar.item.calculator")
        case .chatReplyGenerator: return L("settings.toolbar.item.chatReplyGenerator")
        }
    }

    private func isItemInToolbar(_ item: ToolbarItemType) -> Bool {
        currentItems.contains(item)
    }

    private var availableGridItems: [ToolbarItemType] {
        allAvailableItems.filter { !isItemInToolbar($0) }
    }

    // MARK: - Drag & Drop (Long Press Reorder)

    private var draggedIndexPath: IndexPath?
    private var draggedSnapshot: UIView?

    private func setupDragAndDrop() {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.3
        previewCollectionView.addGestureRecognizer(longPress)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard isEditMode else { return }

        let location = gesture.location(in: previewCollectionView)

        switch gesture.state {
        case .began:
            guard let indexPath = previewCollectionView.indexPathForItem(at: location),
                  indexPath.item < currentItems.count,
                  currentItems[indexPath.item] != .settings else { return }

            draggedIndexPath = indexPath

            if let cell = previewCollectionView.cellForItem(at: indexPath) {
                let snapshot = cell.snapshotView(afterScreenUpdates: true) ?? UIView()
                snapshot.center = previewCollectionView.convert(location, to: view)
                snapshot.alpha = 0.9
                snapshot.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
                view.addSubview(snapshot)
                draggedSnapshot = snapshot

                UIView.animate(withDuration: 0.2) {
                    cell.alpha = 0.3
                }
            }

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        case .changed:
            guard let snapshot = draggedSnapshot else { return }
            snapshot.center = gesture.location(in: view)

            let previewLocation = gesture.location(in: previewCollectionView)
            guard let targetIndexPath = previewCollectionView.indexPathForItem(at: previewLocation),
                  let sourceIndexPath = draggedIndexPath,
                  targetIndexPath != sourceIndexPath,
                  targetIndexPath.item < currentItems.count,
                  targetIndexPath.item != 0
            else { return }

            let item = currentItems.remove(at: sourceIndexPath.item)
            currentItems.insert(item, at: targetIndexPath.item)
            previewCollectionView.moveItem(at: sourceIndexPath, to: targetIndexPath)
            draggedIndexPath = targetIndexPath

            UIImpactFeedbackGenerator(style: .light).impactOccurred()

        case .ended, .cancelled:
            guard let sourceIndexPath = draggedIndexPath else { return }

            if let cell = previewCollectionView.cellForItem(at: sourceIndexPath) {
                UIView.animate(withDuration: 0.2) {
                    cell.alpha = 1.0
                }
            }
            UIView.animate(withDuration: 0.15, animations: {
                self.draggedSnapshot?.alpha = 0
            }, completion: { _ in
                self.draggedSnapshot?.removeFromSuperview()
                self.draggedSnapshot = nil
            })

            draggedIndexPath = nil
            previewCollectionView.reloadData()

        default:
            break
        }
    }
}

// MARK: - UICollectionViewDataSource

extension ToolbarCustomizationViewController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView === previewCollectionView {
            return maxSlots
        } else {
            return availableGridItems.count
        }
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if collectionView === previewCollectionView {
            if indexPath.item < currentItems.count {
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ToolbarPreviewCell.reuseId, for: indexPath) as! ToolbarPreviewCell
                let item = currentItems[indexPath.item]
                cell.configure(
                    iconName: iconName(for: item),
                    showDeleteBadge: isEditMode && item != .settings
                )
                return cell
            } else {
                let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ToolbarEmptySlotCell.reuseId, for: indexPath) as! ToolbarEmptySlotCell
                return cell
            }
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ToolbarGridCell.reuseId, for: indexPath) as! ToolbarGridCell
            let item = availableGridItems[indexPath.item]
            cell.configure(iconName: iconName(for: item), title: displayName(for: item))
            return cell
        }
    }
}

// MARK: - UICollectionViewDelegate

extension ToolbarCustomizationViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        guard isEditMode else { return false }

        if collectionView === previewCollectionView {
            guard indexPath.item < currentItems.count else { return false }
            return currentItems[indexPath.item] != .settings
        }
        return true
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        guard isEditMode else { return false }

        if collectionView === previewCollectionView {
            guard indexPath.item < currentItems.count else { return false }
            guard currentItems[indexPath.item] != .settings else { return false }
            guard currentItems.count > 2 else { return false }
            return true
        }
        return true
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if collectionView === previewCollectionView {
            currentItems.remove(at: indexPath.item)
            previewCollectionView.reloadData()
            gridCollectionView.reloadData()

        } else {
            guard currentItems.count < maxSlots else { return }
            let item = availableGridItems[indexPath.item]
            currentItems.append(item)
            previewCollectionView.reloadData()
            gridCollectionView.reloadData()
        }
    }
}

// MARK: - ToolbarPreviewCell

private final class ToolbarPreviewCell: UICollectionViewCell {
    static let reuseId = "ToolbarPreviewCell"

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .label
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let deleteBadge: UIView = {
        let v = UIView()
        v.backgroundColor = .systemRed
        v.layer.cornerRadius = 9
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true

        let xLabel = UILabel()
        xLabel.text = "\u{2715}"
        xLabel.textColor = .white
        xLabel.font = .systemFont(ofSize: 10, weight: .bold)
        xLabel.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(xLabel)
        NSLayoutConstraint.activate([
            xLabel.centerXAnchor.constraint(equalTo: v.centerXAnchor),
            xLabel.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.clipsToBounds = false
        contentView.addSubview(iconImageView)
        contentView.addSubview(deleteBadge)

        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 24),
            iconImageView.heightAnchor.constraint(equalToConstant: 24),

            deleteBadge.widthAnchor.constraint(equalToConstant: 18),
            deleteBadge.heightAnchor.constraint(equalToConstant: 18),
            deleteBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: -4),
            deleteBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: 4),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconImageView.image = nil
        deleteBadge.isHidden = true
    }

    func configure(iconName: String, showDeleteBadge: Bool) {
        if let named = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate) {
            iconImageView.image = named
        } else {
            // Fallback: SF Symbol (calculator 등 에셋 없는 경우)
            iconImageView.image = UIImage(systemName: iconName)?.withRenderingMode(.alwaysTemplate)
        }
        deleteBadge.isHidden = !showDeleteBadge
    }
}

// MARK: - ToolbarEmptySlotCell

private final class ToolbarEmptySlotCell: UICollectionViewCell {
    static let reuseId = "ToolbarEmptySlotCell"

    private let dashedCircle: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = .clear
        return v
    }()

    private var dashedLayer: CAShapeLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(dashedCircle)
        NSLayoutConstraint.activate([
            dashedCircle.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            dashedCircle.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            dashedCircle.widthAnchor.constraint(equalToConstant: 32),
            dashedCircle.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        dashedLayer?.removeFromSuperlayer()
        let path = UIBezierPath(ovalIn: dashedCircle.bounds)
        let shape = CAShapeLayer()
        shape.path = path.cgPath
        shape.strokeColor = UIColor.tertiaryLabel.cgColor
        shape.fillColor = UIColor.clear.cgColor
        shape.lineWidth = 1.5
        shape.lineDashPattern = [4, 4]
        dashedCircle.layer.addSublayer(shape)
        dashedLayer = shape
    }
}

// MARK: - ToolbarGridCell

private final class ToolbarGridCell: UICollectionViewCell {
    static let reuseId = "ToolbarGridCell"

    private let iconImageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .label
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11)
        l.textColor = .label
        l.textAlignment = .center
        l.numberOfLines = 2
        l.adjustsFontSizeToFitWidth = true
        l.minimumScaleFactor = 0.8
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        let stack = UIStackView(arrangedSubviews: [iconImageView, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            iconImageView.widthAnchor.constraint(equalToConstant: 28),
            iconImageView.heightAnchor.constraint(equalToConstant: 28),

            stack.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconImageView.image = nil
        titleLabel.text = nil
    }

    func configure(iconName: String, title: String) {
        if let named = UIImage(named: iconName)?.withRenderingMode(.alwaysTemplate) {
            iconImageView.image = named
        } else {
            iconImageView.image = UIImage(systemName: iconName)?.withRenderingMode(.alwaysTemplate)
        }
        titleLabel.text = title
    }
}
