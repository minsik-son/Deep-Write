import UIKit

final class KeyboardAppearanceSettingsViewController: UITableViewController {

    private let options = AppConstants.KeyboardAppearanceMode.allCases
    private var selectedMode: AppConstants.KeyboardAppearanceMode = .automatic

    override func viewDidLoad() {
        super.viewDidLoad()
        title = L("settings.keyboard_appearance")
        tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")

        if let raw = AppGroupManager.shared.string(forKey: AppConstants.UserDefaultsKeys.keyboardAppearanceMode),
           let mode = AppConstants.KeyboardAppearanceMode(rawValue: raw) {
            selectedMode = mode
        }
    }

    // MARK: - DataSource

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        options.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let mode = options[indexPath.row]

        switch mode {
        case .automatic: cell.textLabel?.text = L("settings.keyboard_appearance.automatic")
        case .light:     cell.textLabel?.text = L("settings.keyboard_appearance.light")
        case .dark:      cell.textLabel?.text = L("settings.keyboard_appearance.dark")
        }

        cell.accessoryType = mode == selectedMode ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        L("settings.keyboard_appearance.footer")
    }

    // MARK: - Delegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        selectedMode = options[indexPath.row]
        AppGroupManager.shared.set(selectedMode.rawValue, forKey: AppConstants.UserDefaultsKeys.keyboardAppearanceMode)
        tableView.reloadData()
    }
}
