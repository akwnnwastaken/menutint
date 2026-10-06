import AppKit

/// A labelled 0...1 slider that can live inside an NSMenu.
final class SliderMenuView: NSView {
    var onChange: ((Double) -> Void)?

    private let titleLabel: NSTextField
    private let valueLabel: NSTextField
    private let slider: NSSlider

    init(title: String, value: Double) {
        titleLabel = NSTextField(labelWithString: title)
        valueLabel = NSTextField(labelWithString: "")
        slider = NSSlider(value: value, minValue: 0, maxValue: 1, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 48))

        titleLabel.font = NSFont.menuFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 20, y: 26, width: 150, height: 17)

        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: 170, y: 26, width: 62, height: 17)

        slider.frame = NSRect(x: 18, y: 4, width: 216, height: 22)
        slider.controlSize = .small
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)

        addSubview(titleLabel)
        addSubview(valueLabel)
        addSubview(slider)
        updateValueLabel()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func sliderChanged() {
        updateValueLabel()
        onChange?(slider.doubleValue)
    }

    private func updateValueLabel() {
        valueLabel.stringValue = "\(Int((slider.doubleValue * 100).rounded()))%"
    }
}
