import UIKit

class LayoutSettingsViewController: UITableViewController {

    private lazy var numberRowSwitch: UISwitch = {
        let toggle = UISwitch()
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        toggle.isOn = defaults?.object(forKey: AppConstants.UserDefaultsKeys.showNumberRow) == nil ? true : AppGroupManager.shared.bool(forKey: AppConstants.UserDefaultsKeys.showNumberRow)
        toggle.addTarget(self, action: #selector(numberRowToggled(_:)), for: .valueChanged)
        return toggle
    }()

    private lazy var keyTapPreviewSwitch: UISwitch = {
        let toggle = UISwitch()
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        toggle.isOn = defaults?.object(forKey: AppConstants.UserDefaultsKeys.keyTapPreview) == nil
            ? true
            : (defaults?.bool(forKey: AppConstants.UserDefaultsKeys.keyTapPreview) ?? true)
        toggle.addTarget(self, action: #selector(keyTapPreviewToggled(_:)), for: .valueChanged)
        return toggle
    }()

    private lazy var latinAlternativesSwitch: UISwitch = {
        let toggle = UISwitch()
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        toggle.isOn = defaults?.object(forKey: AppConstants.UserDefaultsKeys.latinAlternatives) == nil
            ? true
            : (defaults?.bool(forKey: AppConstants.UserDefaultsKeys.latinAlternatives) ?? true)
        toggle.addTarget(self, action: #selector(latinAlternativesToggled(_:)), for: .valueChanged)
        return toggle
    }()

    private lazy var periodKeySwitch: UISwitch = {
        let toggle = UISwitch()
        let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier)
        toggle.isOn = defaults?.object(forKey: AppConstants.UserDefaultsKeys.showPeriodKey) == nil
            ? true
            : (defaults?.bool(forKey: AppConstants.UserDefaultsKeys.showPeriodKey) ?? true)
        toggle.addTarget(self, action: #selector(periodKeyToggled(_:)), for: .valueChanged)
        return toggle
    }()

    private struct LanguageOption {
        let code: String
        let displayName: String
    }

    private let languageOptions: [LanguageOption] = [
        LanguageOption(code: "ko", displayName: L("language.korean")),
        LanguageOption(code: "es", displayName: "Español"),
        LanguageOption(code: "fr", displayName: "Français"),
        LanguageOption(code: "de", displayName: "Deutsch"),
        LanguageOption(code: "it", displayName: "Italiano"),
        LanguageOption(code: "ru", displayName: "Русский"),
    ]

    private var selectedLanguageCode: String?

    // v2: Additional languages toggle
    private lazy var additionalLanguagesSwitch: UISwitch = {
        let toggle = UISwitch()
        toggle.isOn = AppGroupManager.shared.bool(forKey: "additional_keyboard_language_enabled")
        toggle.addTarget(self, action: #selector(additionalLanguagesToggled(_:)), for: .valueChanged)
        return toggle
    }()

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("settings.layout")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "LayoutCell")
        // v3: 토글 ON + 실제 저장값이 있을 때만 선택 표시
        if additionalLanguagesSwitch.isOn {
            selectedLanguageCode = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.primaryKeyboardLanguage)
        } else {
            selectedLanguageCode = nil
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        title = L("settings.layout")
        tableView.reloadData()
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int { 3 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 4  // Number Row + Key Tap Preview + Latin Special Characters + Period Key
        case 1: return 1  // Additional languages toggle
        case 2: return additionalLanguagesSwitch.isOn ? languageOptions.count : 0
        default: return 0
        }
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 2: return additionalLanguagesSwitch.isOn ? L("settings.keyboard_language") : nil
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LayoutCell", for: indexPath)
        cell.accessoryView = nil
        cell.accessoryType = .none

        var config = cell.defaultContentConfiguration()

        switch indexPath.section {
        case 0:
            cell.selectionStyle = .none
            switch indexPath.row {
            case 0:
                config.text = L("settings.number_row")
                cell.contentConfiguration = config
                cell.accessoryView = numberRowSwitch
            case 1:
                config.text = L("settings.key_tap_preview")
                cell.contentConfiguration = config
                cell.accessoryView = keyTapPreviewSwitch
            case 2:
                config.text = L("settings.latin_special_characters")
                cell.contentConfiguration = config
                cell.accessoryView = latinAlternativesSwitch
            case 3:
                config.text = L("settings.period_key")
                cell.contentConfiguration = config
                cell.accessoryView = periodKeySwitch
            default:
                cell.contentConfiguration = config
            }
        case 1:
            // v2: Additional languages toggle
            config.text = L("settings.additional_languages")
            cell.contentConfiguration = config
            cell.accessoryView = additionalLanguagesSwitch
            cell.selectionStyle = .none
        case 2:
            let option = languageOptions[indexPath.row]
            config.text = option.displayName
            cell.contentConfiguration = config
            cell.accessoryType = (option.code == selectedLanguageCode) ? .checkmark : .none
            cell.selectionStyle = .default
        default:
            cell.contentConfiguration = config
        }

        return cell
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 2 else { return }

        let option = languageOptions[indexPath.row]
        selectedLanguageCode = option.code
        AppGroupManager.shared.set(option.code, forKey: AppConstants.UserDefaultsKeys.primaryKeyboardLanguage)

        tableView.reloadSections(IndexSet(integer: 2), with: .none)
    }

    // MARK: - Actions

    @objc private func numberRowToggled(_ sender: UISwitch) {
        AppGroupManager.shared.set(sender.isOn, forKey: AppConstants.UserDefaultsKeys.showNumberRow)
    }

    @objc private func keyTapPreviewToggled(_ sender: UISwitch) {
        AppGroupManager.shared.set(sender.isOn, forKey: AppConstants.UserDefaultsKeys.keyTapPreview)
    }

    @objc private func latinAlternativesToggled(_ sender: UISwitch) {
        AppGroupManager.shared.set(sender.isOn, forKey: AppConstants.UserDefaultsKeys.latinAlternatives)
    }

    @objc private func periodKeyToggled(_ sender: UISwitch) {
        AppGroupManager.shared.set(sender.isOn, forKey: AppConstants.UserDefaultsKeys.showPeriodKey)
    }

    @objc private func additionalLanguagesToggled(_ sender: UISwitch) {
        AppGroupManager.shared.set(sender.isOn, forKey: "additional_keyboard_language_enabled")
        // v3: OFF 시 선택 초기화, ON 시 기존 저장값 없으면 nil
        if !sender.isOn {
            selectedLanguageCode = nil
        } else {
            selectedLanguageCode = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.primaryKeyboardLanguage)
        }
        tableView.reloadData()
    }
}
