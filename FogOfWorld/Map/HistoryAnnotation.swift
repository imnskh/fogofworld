import MapKit
import UIKit

final class HistoryAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var timeString: String
    // ビューへ直接ラベル更新を伝播するための弱参照。MapKit は timeString の KVO を見ないため必要。
    weak var view: HistoryAnnotationView?

    init(coordinate: CLLocationCoordinate2D, timeString: String) {
        self.coordinate = coordinate
        self.timeString = timeString
    }

    @MainActor
    func update(coordinate: CLLocationCoordinate2D, timeString: String) {
        // @objc dynamic な coordinate の setter で KVO 通知は自動発火するため
        // 手動の willChangeValue/didChangeValue は不要。二重発火させると MapKit の
        // KVO 登録状態が壊れ、removeAnnotation 時に "not registered as an observer" 例外を出す。
        self.coordinate = coordinate
        self.timeString = timeString
        view?.applyAnnotation()
    }
}

final class HistoryAnnotationView: MKAnnotationView {
    static let reuseIdentifier = "HistoryAnnotationView"

    private let label = UILabel()
    private let dot = UIView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        setup()
        // didSet observer は super.init 中に発火しないため、register 経由で生成された初回ビューには
        // annotation.view が紐付かない。明示的にバインドして update() からのラベル反映経路を担保する。
        if let ann = annotation as? HistoryAnnotation {
            ann.view = self
        }
        applyAnnotation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
        if let ann = annotation as? HistoryAnnotation {
            ann.view = self
        }
        applyAnnotation()
    }

    override var annotation: MKAnnotation? {
        didSet {
            if let ann = annotation as? HistoryAnnotation {
                ann.view = self
            }
            applyAnnotation()
        }
    }

    private func setup() {
        canShowCallout = false
        backgroundColor = .clear
        frame = CGRect(x: 0, y: 0, width: 80, height: 44)
        centerOffset = CGPoint(x: 0, y: -10) // ドット先端を coordinate に合わせる

        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .label
        label.backgroundColor = .clear
        label.textAlignment = .center
        label.layer.shadowColor = UIColor.white.cgColor
        label.layer.shadowOpacity = 1.0
        label.layer.shadowRadius = 2
        label.layer.shadowOffset = .zero
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        dot.backgroundColor = .systemOrange
        dot.layer.cornerRadius = 8
        dot.layer.borderColor = UIColor.white.cgColor
        dot.layer.borderWidth = 2
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.heightAnchor.constraint(equalToConstant: 16),
            dot.centerXAnchor.constraint(equalTo: centerXAnchor),
            dot.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 4),
            dot.widthAnchor.constraint(equalToConstant: 16),
            dot.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    func applyAnnotation() {
        guard let ann = annotation as? HistoryAnnotation else { return }
        label.text = ann.timeString
    }
}
