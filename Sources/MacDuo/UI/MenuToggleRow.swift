import AppKit

/// A menu row with a switch, the way Control Center does it: title on the
/// left, `NSSwitch` on the right. Flipping it does not close the menu.
final class MenuToggleRow: NSView {

    private let titleLabel = NSTextField(labelWithString: "")
    private let toggle = NSSwitch()
    private let onChange: (Bool) -> Void
    private let emphasised: Bool

    init(title: String, isOn: Bool, emphasised: Bool = false, onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        self.emphasised = emphasised
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: emphasised ? 34 : 28))
        titleLabel.stringValue = title
        titleLabel.font = emphasised ? .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold) : .menuFont(ofSize: 0)
        titleLabel.textColor = .labelColor
        toggle.state = isOn ? .on : .off
        toggle.controlSize = emphasised ? .regular : .small
        toggle.target = self
        toggle.action = #selector(flipped(_:))
        for view in [titleLabel, toggle] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggle.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var isEnabled: Bool {
        get { toggle.isEnabled }
        set {
            toggle.isEnabled = newValue
            titleLabel.textColor = newValue ? .labelColor : .disabledControlTextColor
        }
    }

    func set(isOn: Bool) {
        let state: NSControl.StateValue = isOn ? .on : .off
        if toggle.state != state { toggle.state = state }
    }

    @objc private func flipped(_ sender: NSSwitch) {
        onChange(sender.state == .on)
    }
}
