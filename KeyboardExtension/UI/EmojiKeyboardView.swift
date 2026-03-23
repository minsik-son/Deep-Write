import UIKit

class EmojiKeyboardView: UIView {

    var onEmojiSelected: ((String) -> Void)?
    var onBackToKeyboard: (() -> Void)?

    private var isDark = false
    private var currentCategoryIndex = 0
    private var cachedCellSize: CGSize = .zero
    private var previousCollectionViewBounds: CGSize = .zero

    // MARK: - Emoji Categories

    private struct EmojiCategory {
        let icon: String      // SF Symbol name
        let emojis: [String]
    }

    private let categories: [EmojiCategory] = [
        EmojiCategory(icon: "face.smiling", emojis: [
            "😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂",
            "🙂", "🙃", "😉", "😊", "😇", "🥰", "😍", "🤩",
            "😘", "😗", "☺️", "😚", "😙", "🥲", "😋", "😛",
            "😜", "🤪", "😝", "🤑", "🤗", "🤭", "🤫", "🤔",
            "🫡", "🤐", "🤨", "😐", "😑", "😶", "🫥", "😏",
            "😒", "🙄", "😬", "🤥", "😌", "😔", "😪", "🤤",
            "😴", "😷", "🤒", "🤕", "🤢", "🤮", "🥵", "🥶",
            "🥴", "😵", "🤯", "🤠", "🥳", "🥸", "😎", "🤓",
            "🧐", "😕", "🫤", "😟", "🙁", "☹️", "😮", "😯",
            "😲", "😳", "🥺", "🥹", "😦", "😧", "😨", "😰",
            "😥", "😢", "😭", "😱", "😖", "😣", "😞", "😓",
            "😩", "😫", "🥱", "😤", "😡", "😠", "🤬", "😈",
            "👿", "💀", "☠️", "💩", "🤡", "👹", "👺", "👻",
            "👽", "👾", "🤖", "😺", "😸", "😹", "😻", "😼",
            "😽", "🙀", "😿", "😾", "🙈", "🙉", "🙊", "💋",
            "💌", "💘", "💝", "💖", "💗", "💓", "💞", "💕",
            "💟", "❣️", "💔", "❤️‍🔥", "❤️‍🩹", "❤️", "🧡", "💛",
            "💚", "💙", "💜", "🤎", "🖤", "🤍", "💯", "💢",
            "👋", "🤚", "🖐️", "✋", "🖖", "🫱", "🫲", "🫳",
            "🫴", "👌", "🤌", "🤏", "✌️", "🤞", "🫰", "🤟",
            "🤘", "🤙", "👈", "👉", "👆", "🖕", "👇", "☝️",
            "🫵", "👍", "👎", "✊", "👊", "🤛", "🤜", "👏",
            "🙌", "🫶", "👐", "🤲", "🤝", "🙏", "✍️", "💅",
        ]),
        EmojiCategory(icon: "person.fill", emojis: [
            // 사람 기본
            "👶", "🧒", "👦", "👧", "🧑", "👱", "👨", "👩",
            "🧔", "👨‍🦰", "👨‍🦱", "👨‍🦳", "👨‍🦲", "👩‍🦰", "👩‍🦱", "👩‍🦳",
            "👩‍🦲", "👴", "👵", "🧓", "👲", "👳‍♂️", "👳‍♀️", "🧕",
            "👮‍♂️", "👮‍♀️", "👷‍♂️", "👷‍♀️", "💂‍♂️", "💂‍♀️", "🕵️‍♂️", "🕵️‍♀️",
            "👨‍⚕️", "👩‍⚕️", "👨‍🌾", "👩‍🌾", "👨‍🍳", "👩‍🍳", "👨‍🎓", "👩‍🎓",
            "👨‍🎤", "👩‍🎤", "👨‍🏫", "👩‍🏫", "👨‍🏭", "👩‍🏭", "👨‍💻", "👩‍💻",
            "👨‍💼", "👩‍💼", "👨‍🔧", "👩‍🔧", "👨‍🔬", "👩‍🔬", "👨‍🎨", "👩‍🎨",
            "👨‍🚀", "👩‍🚀", "👨‍🚒", "👩‍🚒", "👨‍✈️", "👩‍✈️", "👨‍⚖️", "👩‍⚖️",
            // 제스처
            "🙍‍♂️", "🙍‍♀️", "🙎‍♂️", "🙎‍♀️", "🙅‍♂️", "🙅‍♀️", "🙆‍♂️", "🙆‍♀️",
            "💁‍♂️", "💁‍♀️", "🙋‍♂️", "🙋‍♀️", "🧏‍♂️", "🧏‍♀️", "🙇‍♂️", "🙇‍♀️",
            "🤦‍♂️", "🤦‍♀️", "🤷‍♂️", "🤷‍♀️", "💆‍♂️", "💆‍♀️", "💇‍♂️", "💇‍♀️",
            // 가족 & 커플
            "👫", "👬", "👭", "💏", "💑", "👪", "👨‍👩‍👦", "👨‍👩‍👧",
            "👨‍👩‍👧‍👦", "👨‍👩‍👦‍👦", "👨‍👩‍👧‍👧", "🫂",
            // 활동하는 사람
            "🚶‍♂️", "🚶‍♀️", "🧍‍♂️", "🧍‍♀️", "🧎‍♂️", "🧎‍♀️", "🏃‍♂️", "🏃‍♀️",
            "💃", "🕺", "🕴️", "👯‍♂️", "👯‍♀️", "🧖‍♂️", "🧖‍♀️", "🧗‍♂️",
            "🧗‍♀️", "🧘‍♂️", "🧘‍♀️", "🛀", "🛌",
        ]),
        EmojiCategory(icon: "pawprint.fill", emojis: [
            "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼",
            "🐻‍❄️", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵",
            "🙈", "🙉", "🙊", "🐒", "🐔", "🐧", "🐦", "🐤",
            "🐣", "🐥", "🦆", "🦅", "🦉", "🦇", "🐺", "🐗",
            "🐴", "🦄", "🐝", "🪱", "🐛", "🦋", "🐌", "🐞",
            "🐜", "🪰", "🪲", "🪳", "🦟", "🦗", "🕷️", "🕸️",
            "🦂", "🐢", "🐍", "🦎", "🦖", "🦕", "🐙", "🦑",
            "🦐", "🦞", "🦀", "🐡", "🐠", "🐟", "🐬", "🐳",
            "🐋", "🦈", "🐊", "🐅", "🐆", "🦓", "🦍", "🦧",
            "🦣", "🐘", "🦛", "🦏", "🐪", "🐫", "🦒", "🦘",
            "🦬", "🐃", "🐂", "🐄", "🐎", "🐖", "🐏", "🐑",
            "🦙", "🐐", "🦌", "🐕", "🐩", "🦮", "🐕‍🦺", "🐈",
            "🌵", "🎄", "🌲", "🌳", "🌴", "🪵", "🌱", "🌿",
            "☘️", "🍀", "🎍", "🪴", "🎋", "🍃", "🍂", "🍁",
            "🌾", "🌺", "🌻", "🌹", "🥀", "🌷", "🌼", "🌸",
            "💐", "🍄", "🌰", "🎃", "🐚", "🪸", "🪨", "🌎",
        ]),
        EmojiCategory(icon: "fork.knife", emojis: [
            "🍏", "🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇",
            "🍓", "🫐", "🍈", "🍒", "🍑", "🥭", "🍍", "🥥",
            "🥝", "🍅", "🍆", "🥑", "🥦", "🥬", "🥒", "🌶️",
            "🫑", "🌽", "🥕", "🫒", "🧄", "🧅", "🥔", "🍠",
            "🫘", "🥐", "🍞", "🥖", "🥨", "🧀", "🥚", "🍳",
            "🧈", "🥞", "🧇", "🥓", "🥩", "🍗", "🍖", "🌭",
            "🍔", "🍟", "🍕", "🫓", "🥪", "🥙", "🧆", "🌮",
            "🌯", "🫔", "🥗", "🥘", "🫕", "🥫", "🍝", "🍜",
            "🍲", "🍛", "🍣", "🍱", "🥟", "🦪", "🍤", "🍙",
            "🍚", "🍘", "🍥", "🥠", "🥮", "🍢", "🍡", "🍧",
            "🍨", "🍦", "🥧", "🧁", "🍰", "🎂", "🍮", "🍭",
            "🍬", "🍫", "🍿", "🍩", "🍪", "🌰", "🥜", "🍯",
            "🥛", "🍼", "🫖", "☕", "🍵", "🧃", "🥤", "🧋",
            "🍶", "🍺", "🍻", "🥂", "🍷", "🥃", "🍸", "🍹",
            "🧉", "🍾", "🧊", "🥄", "🍴", "🍽️", "🥣", "🥡",
        ]),
        EmojiCategory(icon: "sportscourt.fill", emojis: [
            "⚽", "🏀", "🏈", "⚾", "🥎", "🎾", "🏐", "🏉",
            "🥏", "🎱", "🪀", "🏓", "🏸", "🏒", "🏑", "🥍",
            "🏏", "🪃", "🥅", "⛳", "🪁", "🏹", "🎣", "🤿",
            "🥊", "🥋", "🎽", "🛹", "🛼", "🛷", "⛸️", "🥌",
            "🎿", "⛷️", "🏂", "🪂", "🏋️", "🤼", "🤸", "🤺",
            "⛹️", "🤾", "🏌️", "🏇", "🧘", "🏄", "🏊", "🤽",
            "🚣", "🧗", "🚵", "🚴", "🏆", "🥇", "🥈", "🥉",
            "🏅", "🎖️", "🏵️", "🎗️", "🎫", "🎟️", "🎪", "🤹",
            "🎭", "🩰", "🎨", "🎬", "🎤", "🎧", "🎼", "🎹",
            "🥁", "🪘", "🎷", "🎺", "🪗", "🎸", "🪕", "🎻",
            "🎲", "♟️", "🎯", "🎳", "🎮", "🕹️", "🧩", "🪄",
        ]),
        EmojiCategory(icon: "car.fill", emojis: [
            "🚗", "🚕", "🚙", "🚌", "🚎", "🏎️", "🚓", "🚑",
            "🚒", "🚐", "🛻", "🚚", "🚛", "🚜", "🛵", "🏍️",
            "🛺", "🚲", "🛴", "🛹", "🚏", "🛣️", "🛤️", "🛞",
            "⛽", "🚨", "🚥", "🚦", "🛑", "🚧", "⚓", "🛟",
            "⛵", "🛶", "🚤", "🛳️", "⛴️", "🛥️", "🚢", "✈️",
            "🛩️", "🛫", "🛬", "🪂", "💺", "🚁", "🚟", "🚠",
            "🚡", "🛰️", "🚀", "🛸", "🌍", "🌎", "🌏", "🌐",
            "🗺️", "🧭", "🏔️", "⛰️", "🌋", "🗻", "🏕️", "🏖️",
            "🏜️", "🏝️", "🏞️", "🏟️", "🏛️", "🏗️", "🧱", "🪨",
            "🪵", "🛖", "🏘️", "🏚️", "🏠", "🏡", "🏢", "🏣",
            "🏤", "🏥", "🏦", "🏨", "🏩", "🏪", "🏫", "🏬",
            "🏭", "🏯", "🏰", "💒", "🗼", "🗽", "⛪", "🕌",
            "🛕", "🕍", "⛩️", "🕋", "⛲", "⛺", "🌁", "🌃",
            "🏙️", "🌄", "🌅", "🌆", "🌇", "🌉", "♨️", "🎠",
            "🛝", "🎡", "🎢", "💈", "🎪", "🚂", "🚃", "🚄",
            "🚅", "🚆", "🚇", "🚈", "🚉", "🚊", "🚝", "🚞",
        ]),
        EmojiCategory(icon: "lightbulb.fill", emojis: [
            "⌚", "📱", "📲", "💻", "⌨️", "🖥️", "🖨️", "🖱️",
            "🖲️", "💽", "💾", "💿", "📀", "🧮", "🎥", "🎞️",
            "📽️", "🎬", "📺", "📷", "📸", "📹", "📼", "🔍",
            "🔎", "🕯️", "💡", "🔦", "🏮", "🪔", "📔", "📕",
            "📖", "📗", "📘", "📙", "📚", "📓", "📒", "📃",
            "📜", "📄", "📰", "🗞️", "📑", "🔖", "🏷️", "💰",
            "🪙", "💴", "💵", "💶", "💷", "💸", "💳", "🧾",
            "💹", "✉️", "📧", "📨", "📩", "📤", "📥", "📦",
            "📫", "📪", "📬", "📭", "📮", "🗳️", "✏️", "✒️",
            "🖋️", "🖊️", "🖌️", "🖍️", "📝", "💼", "📁", "📂",
            "🗂️", "📅", "📆", "🗒️", "🗓️", "📇", "📈", "📉",
            "📊", "📋", "📌", "📍", "📎", "🖇️", "📏", "📐",
            "✂️", "🗃️", "🗄️", "🗑️", "🔒", "🔓", "🔏", "🔐",
            "🔑", "🗝️", "🔨", "🪓", "⛏️", "⚒️", "🛠️", "🗡️",
            "⚔️", "🔫", "🪃", "🏹", "🛡️", "🪚", "🔧", "🪛",
            "🔩", "⚙️", "🗜️", "⚖️", "🦯", "🔗", "⛓️", "🪝",
        ]),
        EmojiCategory(icon: "number.circle.fill", emojis: [
            "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍",
            "🤎", "❤️‍🔥", "❤️‍🩹", "💔", "❣️", "💕", "💞", "💓",
            "💗", "💖", "💝", "💘", "💟", "☮️", "✝️", "☪️",
            "🕉️", "☸️", "✡️", "🔯", "🕎", "☯️", "☦️", "🛐",
            "⛎", "♈", "♉", "♊", "♋", "♌", "♍", "♎",
            "♏", "♐", "♑", "♒", "♓", "🆔", "⚛️", "🉑",
            "☢️", "☣️", "📴", "📳", "🈶", "🈚", "🈸", "🈺",
            "🈷️", "✴️", "🆚", "💮", "🉐", "㊙️", "㊗️", "🈴",
            "🈵", "🈹", "🈲", "🅰️", "🅱️", "🆎", "🆑", "🅾️",
            "🆘", "❌", "⭕", "🛑", "⛔", "📛", "🚫", "💯",
            "💢", "♨️", "🚷", "🚯", "🚳", "🚱", "🔞", "📵",
            "🚭", "❗", "❕", "❓", "❔", "‼️", "⁉️", "🔅",
            "🔆", "〽️", "⚠️", "🚸", "🔱", "⚜️", "🔰", "♻️",
            "✅", "🈯", "💹", "❇️", "✳️", "❎", "🌐", "💠",
            "Ⓜ️", "🌀", "💤", "🏧", "🚾", "♿", "🅿️", "🛗",
            "🈳", "🈂️", "🛂", "🛃", "🛄", "🛅", "🚹", "🚺",
        ]),
        EmojiCategory(icon: "flag.fill", emojis: [
            "🏁", "🚩", "🎌", "🏴", "🏳️", "🏳️‍🌈", "🏳️‍⚧️", "🏴‍☠️",
            "🇰🇷", "🇺🇸", "🇯🇵", "🇨🇳", "🇬🇧", "🇫🇷", "🇩🇪", "🇮🇹",
            "🇪🇸", "🇵🇹", "🇧🇷", "🇷🇺", "🇮🇳", "🇦🇺", "🇨🇦", "🇲🇽",
            "🇹🇷", "🇸🇦", "🇦🇪", "🇹🇭", "🇻🇳", "🇮🇩", "🇲🇾", "🇸🇬",
            "🇵🇭", "🇳🇿", "🇦🇷", "🇨🇱", "🇨🇴", "🇵🇪", "🇪🇬", "🇿🇦",
            "🇳🇬", "🇰🇪", "🇪🇹", "🇬🇭", "🇹🇼", "🇭🇰", "🇲🇴", "🇲🇳",
            "🇰🇵", "🇰🇭", "🇱🇦", "🇲🇲", "🇧🇩", "🇵🇰", "🇦🇫", "🇮🇶",
            "🇮🇷", "🇮🇱", "🇵🇸", "🇱🇧", "🇯🇴", "🇸🇾", "🇾🇪", "🇴🇲",
        ]),
    ]

    // MARK: - Views

    private let collectionView: UICollectionView = {
        let layout = UIFlowLayout()
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.sectionInset = UIEdgeInsets(top: 8, left: 8, bottom: 12, right: 8)
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.backgroundColor = .clear
        cv.showsVerticalScrollIndicator = false
        cv.register(EmojiCell.self, forCellWithReuseIdentifier: "EmojiCell")
        return cv
    }()

    private let categoryBar: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let categoryStack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.distribution = .equalSpacing
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private var abcButton: UIButton!
    private var backspaceButton: UIButton!
    private var categoryButtons: [UIButton] = []

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupViews() {
        addSubview(collectionView)
        addSubview(categoryBar)
        categoryBar.addSubview(categoryStack)

        collectionView.dataSource = self
        collectionView.delegate = self
        // Long press gesture for skin tone selection
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        longPress.delaysTouchesEnded = false
        collectionView.addGestureRecognizer(longPress)

        // ABC button
        abcButton = UIButton(type: .system)
        abcButton.setTitle("ABC", for: .normal)
        abcButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        abcButton.addTarget(self, action: #selector(abcTapped), for: .touchUpInside)
        abcButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            abcButton.widthAnchor.constraint(equalToConstant: 36),
            abcButton.heightAnchor.constraint(equalToConstant: 40),
        ])
        categoryStack.addArrangedSubview(abcButton)

        // Category buttons
        for (index, category) in categories.enumerated() {
            let btn = UIButton(type: .system)
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            btn.setImage(UIImage(systemName: category.icon, withConfiguration: config), for: .normal)
            btn.tag = index
            btn.addTarget(self, action: #selector(categoryTapped(_:)), for: .touchUpInside)
            btn.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                btn.widthAnchor.constraint(equalToConstant: 26),
                btn.heightAnchor.constraint(equalToConstant: 40),
            ])
            categoryStack.addArrangedSubview(btn)
            categoryButtons.append(btn)
        }

        // Backspace button
        backspaceButton = UIButton(type: .system)
        let bsConfig = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        backspaceButton.setImage(UIImage(systemName: "delete.left", withConfiguration: bsConfig), for: .normal)
        backspaceButton.addTarget(self, action: #selector(backspaceTapped), for: .touchUpInside)
        backspaceButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            backspaceButton.widthAnchor.constraint(equalToConstant: 36),
            backspaceButton.heightAnchor.constraint(equalToConstant: 40),
        ])
        categoryStack.addArrangedSubview(backspaceButton)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: categoryBar.topAnchor),

            categoryBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            categoryBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            categoryBar.bottomAnchor.constraint(equalTo: bottomAnchor),
            categoryBar.heightAnchor.constraint(equalToConstant: 40),

            categoryStack.topAnchor.constraint(equalTo: categoryBar.topAnchor),
            categoryStack.leadingAnchor.constraint(equalTo: categoryBar.leadingAnchor, constant: 4),
            categoryStack.trailingAnchor.constraint(equalTo: categoryBar.trailingAnchor, constant: -4),
            categoryStack.bottomAnchor.constraint(equalTo: categoryBar.bottomAnchor),
        ])

        updateCategoryHighlight()
    }

    // MARK: - Actions

    @objc private func abcTapped() {
        onBackToKeyboard?()
    }

    @objc private func categoryTapped(_ sender: UIButton) {
        // 카테고리 전환 전에 이전 카테고리의 CoreText 글리프 캐시 클리어
        // → 최대 1개 카테고리분의 글리프만 메모리에 유지
        CoreTextCacheManager.shared.clearGlyphCaches()

        currentCategoryIndex = sender.tag
        collectionView.reloadData()
        collectionView.setContentOffset(.zero, animated: false)
        updateCategoryHighlight()
    }

    @objc private func backspaceTapped() {
        onEmojiSelected?(KeyboardLayoutView.backKey)
    }

    // MARK: - Category Highlight

    private func updateCategoryHighlight() {
        for (index, btn) in categoryButtons.enumerated() {
            btn.tintColor = (index == currentCategoryIndex) ? .systemBlue : (isDark ? .lightGray : .gray)
        }
    }

    // MARK: - Public

    func updateAppearance(isDark: Bool) {
        self.isDark = isDark
        backgroundColor = isDark ? UIColor(white: 0.08, alpha: 1) : UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1)
        categoryBar.backgroundColor = isDark ? UIColor(white: 0.15, alpha: 1) : UIColor(white: 0.92, alpha: 1)
        abcButton.setTitleColor(isDark ? .white : .black, for: .normal)
        backspaceButton.tintColor = isDark ? .white : .black
        updateCategoryHighlight()
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let currentBounds = collectionView.bounds.size
        if currentBounds != previousCollectionViewBounds && currentBounds.width > 0 && currentBounds.height > 0 {
            previousCollectionViewBounds = currentBounds
            cachedCellSize = .zero
            collectionView.collectionViewLayout.invalidateLayout()
        }
    }

    // MARK: - Cleanup

    /// 이모지 키보드가 dismiss될 때 호출. CoreText 글리프 캐시를 전부 클리어.
    func prepareForDismiss() {
        dismissSkinTonePopup()
        CoreTextCacheManager.shared.clearGlyphCaches()
    }

    // MARK: - Skin Tone Selection

    private static let skinToneModifiers: [String] = [
        "",           // 기본 (노란색)
        "\u{1F3FB}",  // Light
        "\u{1F3FC}",  // Medium-Light
        "\u{1F3FD}",  // Medium
        "\u{1F3FE}",  // Medium-Dark
        "\u{1F3FF}",  // Dark
    ]

    private static let skinToneRanges: [ClosedRange<UInt32>] = [
        0x261D...0x261D,
        0x270A...0x270D,
        0x1F385...0x1F385,
        0x1F3C2...0x1F3C4,
        0x1F3C7...0x1F3C7,
        0x1F3CA...0x1F3CC,
        0x1F442...0x1F443,
        0x1F446...0x1F450,
        0x1F466...0x1F478,
        0x1F47C...0x1F47C,
        0x1F481...0x1F4AA,
        0x1F574...0x1F575,
        0x1F57A...0x1F57A,
        0x1F590...0x1F590,
        0x1F595...0x1F596,
        0x1F645...0x1F64F,
        0x1F6A3...0x1F6A3,
        0x1F6B4...0x1F6B6,
        0x1F6C0...0x1F6C0,
        0x1F6CC...0x1F6CC,
        0x1F90C...0x1F90F,
        0x1F918...0x1F91F,
        0x1F926...0x1F926,
        0x1F930...0x1F939,
        0x1F93D...0x1F93E,
        0x1F977...0x1F977,
        0x1F9B5...0x1F9B6,
        0x1F9B8...0x1F9B9,
        0x1F9BB...0x1F9BB,
        0x1F9CD...0x1F9CF,
        0x1F9D1...0x1F9DD,
        0x1FAC3...0x1FAC5,
        0x1FAF0...0x1FAF8,
    ]

    private static func supportsSkinTone(_ emoji: String) -> Bool {
        guard let firstScalar = emoji.unicodeScalars.first else { return false }
        let value = firstScalar.value
        let zwjCount = emoji.unicodeScalars.filter { $0.value == 0x200D }.count
        if zwjCount >= 2 { return false }
        return skinToneRanges.contains { $0.contains(value) }
    }

    private static func extractBaseEmoji(_ emoji: String) -> String {
        let filtered = emoji.unicodeScalars.filter {
            let isSkinTone = $0.value >= 0x1F3FB && $0.value <= 0x1F3FF
            let isVariationSelector = $0.value == 0xFE0E || $0.value == 0xFE0F
            return !isSkinTone && !isVariationSelector
        }
        var scalarView = String.UnicodeScalarView()
        scalarView.append(contentsOf: filtered)
        return String(scalarView)
    }

    private static func isModifierTarget(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return
            v == 0x261D ||
            (v >= 0x270A && v <= 0x270D) ||
            (v >= 0x1F442 && v <= 0x1F443) ||
            (v >= 0x1F446 && v <= 0x1F450) ||
            (v >= 0x1F466 && v <= 0x1F478) ||
            v == 0x1F47C ||
            (v >= 0x1F481 && v <= 0x1F487) ||
            v == 0x1F4AA ||
            v == 0x1F385 ||
            (v >= 0x1F3C2 && v <= 0x1F3C4) ||
            v == 0x1F3C7 ||
            (v >= 0x1F3CA && v <= 0x1F3CC) ||
            (v >= 0x1F574 && v <= 0x1F575) ||
            v == 0x1F57A ||
            v == 0x1F590 ||
            (v >= 0x1F595 && v <= 0x1F596) ||
            (v >= 0x1F645 && v <= 0x1F64F) ||
            v == 0x1F6A3 ||
            (v >= 0x1F6B4 && v <= 0x1F6B6) ||
            v == 0x1F6C0 ||
            v == 0x1F6CC ||
            (v >= 0x1F90C && v <= 0x1F90F) ||
            (v >= 0x1F918 && v <= 0x1F91F) ||
            v == 0x1F926 ||
            (v >= 0x1F930 && v <= 0x1F939) ||
            (v >= 0x1F93D && v <= 0x1F93E) ||
            v == 0x1F977 ||
            (v >= 0x1F9B5 && v <= 0x1F9B6) ||
            (v >= 0x1F9B8 && v <= 0x1F9B9) ||
            v == 0x1F9BB ||
            (v >= 0x1F9CD && v <= 0x1F9CF) ||
            (v >= 0x1F9D1 && v <= 0x1F9DD) ||
            (v >= 0x1FAC3 && v <= 0x1FAC5) ||
            (v >= 0x1FAF0 && v <= 0x1FAF8)
    }

    private static func skinToneVariants(for emoji: String) -> [String] {
        let base = extractBaseEmoji(emoji)

        return skinToneModifiers.map { modifier in
            if modifier.isEmpty { return base }

            let targetScalars = base.unicodeScalars.filter { isModifierTarget($0) }

            if targetScalars.count <= 1 {
                var result = String.UnicodeScalarView()
                var inserted = false
                for scalar in base.unicodeScalars {
                    result.append(scalar)
                    if !inserted && isModifierTarget(scalar) {
                        for ms in modifier.unicodeScalars {
                            result.append(ms)
                        }
                        inserted = true
                    }
                }
                if !inserted {
                    for ms in modifier.unicodeScalars {
                        result.append(ms)
                    }
                }
                return String(result)
            } else {
                var result = String.UnicodeScalarView()
                for scalar in base.unicodeScalars {
                    result.append(scalar)
                    if isModifierTarget(scalar) {
                        for ms in modifier.unicodeScalars {
                            result.append(ms)
                        }
                    }
                }
                return String(result)
            }
        }
    }

    // MARK: - Skin Tone Drag-to-Select State

    private var skinTonePopup: UIView?
    private var skinToneLabels: [UILabel] = []
    private var highlightedSkinToneIndex: Int = -1
    private var currentSkinToneVariants: [String] = []

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            handleLongPressBegan(gesture)
        case .changed:
            handleLongPressChanged(gesture)
        case .ended:
            handleLongPressEnded(gesture)
        case .cancelled, .failed:
            dismissSkinTonePopup()
        default:
            break
        }
    }

    private func handleLongPressBegan(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point) else { return }

        guard currentCategoryIndex < categories.count else { return }
        let currentEmojis = categories[currentCategoryIndex].emojis
        guard indexPath.item < currentEmojis.count else { return }

        let emoji = currentEmojis[indexPath.item]
        guard Self.supportsSkinTone(emoji) else { return }

        dismissSkinTonePopup()

        let variants = Self.skinToneVariants(for: emoji)
        guard variants.count > 1 else { return }
        currentSkinToneVariants = variants

        guard let cell = collectionView.cellForItem(at: indexPath) else { return }
        let cellFrameInSelf = collectionView.convert(cell.frame, to: self)

        showSkinTonePopup(variants: variants, anchorFrame: cellFrameInSelf)

        let pointInSelf = gesture.location(in: self)
        updateHighlight(at: pointInSelf)
    }

    private func handleLongPressChanged(_ gesture: UILongPressGestureRecognizer) {
        guard skinTonePopup != nil else { return }
        let pointInSelf = gesture.location(in: self)
        updateHighlight(at: pointInSelf)
    }

    private func handleLongPressEnded(_ gesture: UILongPressGestureRecognizer) {
        guard skinTonePopup != nil else { return }

        if highlightedSkinToneIndex >= 0 && highlightedSkinToneIndex < currentSkinToneVariants.count {
            let selectedEmoji = currentSkinToneVariants[highlightedSkinToneIndex]
            onEmojiSelected?(selectedEmoji)
        }

        dismissSkinTonePopup()
    }

    private func updateHighlight(at point: CGPoint) {
        guard let popup = skinTonePopup else { return }

        var newIndex = -1

        let expandedFrame = popup.frame.insetBy(dx: -8, dy: -12)
        if expandedFrame.contains(point) {
            for (index, label) in skinToneLabels.enumerated() {
                let labelFrameInSelf = popup.convert(label.frame, to: self)
                let hitRect = CGRect(x: labelFrameInSelf.minX, y: expandedFrame.minY,
                                     width: labelFrameInSelf.width, height: expandedFrame.height)
                if hitRect.contains(point) {
                    newIndex = index
                    break
                }
            }
        }

        if newIndex != highlightedSkinToneIndex {
            if highlightedSkinToneIndex >= 0 && highlightedSkinToneIndex < skinToneLabels.count {
                let prevLabel = skinToneLabels[highlightedSkinToneIndex]
                prevLabel.transform = .identity
                prevLabel.backgroundColor = .clear
            }

            if newIndex >= 0 && newIndex < skinToneLabels.count {
                let label = skinToneLabels[newIndex]
                label.transform = CGAffineTransform(scaleX: 1.3, y: 1.3)
                label.backgroundColor = isDark
                    ? UIColor(white: 0.4, alpha: 0.6)
                    : UIColor(white: 0.85, alpha: 0.6)
                label.layer.cornerRadius = 6
            }

            highlightedSkinToneIndex = newIndex
        }
    }

    private func showSkinTonePopup(variants: [String], anchorFrame: CGRect) {
        let popupHeight: CGFloat = 48
        let itemWidth: CGFloat = 42
        let popupWidth: CGFloat = CGFloat(variants.count) * itemWidth + 16
        let cornerRadius: CGFloat = 12

        var popupX = anchorFrame.midX - popupWidth / 2
        popupX = max(4, min(popupX, bounds.width - popupWidth - 4))
        let popupY = max(4, anchorFrame.minY - popupHeight - 6)

        let popup = UIView(frame: CGRect(x: popupX, y: popupY, width: popupWidth, height: popupHeight))
        popup.backgroundColor = isDark ? UIColor(white: 0.25, alpha: 0.98) : UIColor(white: 0.98, alpha: 0.98)
        popup.layer.cornerRadius = cornerRadius
        popup.layer.shadowColor = UIColor.black.cgColor
        popup.layer.shadowOpacity = 0.25
        popup.layer.shadowOffset = CGSize(width: 0, height: 2)
        popup.layer.shadowRadius = 8
        popup.isUserInteractionEnabled = false

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        popup.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: popup.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: popup.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: popup.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: popup.trailingAnchor, constant: -8),
        ])

        var labels: [UILabel] = []
        for variant in variants {
            let label = UILabel()
            label.text = variant
            label.font = .systemFont(ofSize: 30)
            label.textAlignment = .center
            label.clipsToBounds = true
            stack.addArrangedSubview(label)
            labels.append(label)
        }

        addSubview(popup)
        skinTonePopup = popup
        skinToneLabels = labels
        highlightedSkinToneIndex = -1
    }

    private func dismissSkinTonePopup() {
        skinTonePopup?.removeFromSuperview()
        skinTonePopup = nil
        skinToneLabels = []
        highlightedSkinToneIndex = -1
        currentSkinToneVariants = []
    }
}

// MARK: - UICollectionView DataSource & Delegate

extension EmojiKeyboardView: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return categories[currentCategoryIndex].emojis.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "EmojiCell", for: indexPath) as! EmojiCell
        cell.label.text = categories[currentCategoryIndex].emojis[indexPath.item]
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let emoji = categories[currentCategoryIndex].emojis[indexPath.item]
        onEmojiSelected?(emoji)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if cachedCellSize == .zero || cachedCellSize.width <= 0 {
            let totalWidth = collectionView.bounds.width - 16 // 8 + 8 left/right insets
            let columns: CGFloat = 8
            let hSpacing: CGFloat = 4 * (columns - 1)
            let cellWidth = floor((totalWidth - hSpacing) / columns)

            // 세로: 정확히 4줄만 보이도록 계산
            let visibleRows: CGFloat = 4
            let vSpacing: CGFloat = 4 * (visibleRows - 1)
            let topInset: CGFloat = 8
            let bottomInset: CGFloat = 12
            let availableHeight = collectionView.bounds.height - topInset - bottomInset - vSpacing

            let cellHeight: CGFloat
            if availableHeight > 0 {
                cellHeight = floor(availableHeight / visibleRows)
            } else {
                cellHeight = cellWidth
            }

            cachedCellSize = CGSize(width: cellWidth, height: cellHeight)
        }
        return cachedCellSize
    }
}

// MARK: - Custom Flow Layout (to suppress constraint warnings)

private class UIFlowLayout: UICollectionViewFlowLayout {}

// MARK: - Emoji Cell

private class EmojiCell: UICollectionViewCell {

    let label: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 26)
        l.textAlignment = .center
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
