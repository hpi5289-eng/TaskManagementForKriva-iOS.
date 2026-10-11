import UIKit

// Common look (header, cards, buttons) and helpers for every screen. Same colours as the Android app.

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
    convenience init?(hexString: String) {
        let h = hexString.trimmingCharacters(in: .whitespaces)
        guard h.count == 7, h.hasPrefix("#"), let v = UInt32(h.dropFirst(), radix: 16) else { return nil }
        self.init(hex: v)
    }
}

enum C {
    static let navy = UIColor(hex: 0x10214F), orange = UIColor(hex: 0xF05C29), bg = UIColor(hex: 0xF3F4F8), card = UIColor.white
    static let text = UIColor(hex: 0x111827), muted = UIColor(hex: 0x6B7280), line = UIColor(hex: 0xE5E7EB)
    static let green = UIColor(hex: 0x16A34A), red = UIColor(hex: 0xDC2626), blue = UIColor(hex: 0x2563EB)
    static let violet = UIColor(hex: 0x7C3AED), amber = UIColor(hex: 0xD97706), cyan = UIColor(hex: 0x0891B2)

    /// header colour = company brand colour (website setting), navy for owner / reseller
    static var brand: UIColor { return UIColor(hexString: Store.user.o("company").s("brand_color")) ?? navy }

    static func status(_ st: String) -> UIColor {
        switch st {
        case "done": return green
        case "cancelled": return muted
        case "approval": return violet
        case "progress": return blue
        case "assigned": return cyan
        default: return amber
        }
    }
}

/// UIButton that runs a closure
final class Btn: UIButton {
    var onTap: (() -> Void)?
    convenience init(_ title: String, bg: UIColor, onTap: (() -> Void)? = nil) {
        self.init(type: .system)
        self.onTap = onTap
        setTitle(title, for: .normal)
        let light = bg == C.card
        setTitleColor(light ? C.text : .white, for: .normal)
        titleLabel?.font = .boldSystemFont(ofSize: 15)
        titleLabel?.numberOfLines = 2
        titleLabel?.textAlignment = .center
        backgroundColor = bg
        layer.cornerRadius = 12
        if light { layer.borderWidth = 1; layer.borderColor = UIColor(hex: 0xD1D5DB).cgColor }
        contentEdgeInsets = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }
    @objc func tapped() { onTap?() }
    override var isEnabled: Bool { didSet { alpha = isEnabled ? 1 : 0.5 } }
}

/// a view you can tap
final class TapView: UIView {
    var onTap: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func tapped() { onTap?() }
}

/// text field with padding and a border
final class Field: UITextField {
    let pad = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
    override func textRect(forBounds b: CGRect) -> CGRect { return b.inset(by: pad) }
    override func editingRect(forBounds b: CGRect) -> CGRect { return b.inset(by: pad) }
    override func placeholderRect(forBounds b: CGRect) -> CGRect { return b.inset(by: pad) }
}

class BaseVC: UIViewController, UITextFieldDelegate {
    let scroll = UIScrollView()
    let page = UIStackView()
    let titleLabel = UILabel(), subLabel = UILabel()
    var pageTitle = "", pageSub = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = C.bg
        scroll.alwaysBounceVertical = true
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        page.axis = .vertical
        page.spacing = 10
        page.isLayoutMarginsRelativeArrangement = true
        page.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 28, right: 12)
        page.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(page)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            page.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            page.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            page.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
        ])
        let tv = UIStackView(arrangedSubviews: [titleLabel, subLabel])
        tv.axis = .vertical
        tv.alignment = .center
        titleLabel.font = .boldSystemFont(ofSize: 17); titleLabel.textColor = .white
        subLabel.font = .systemFont(ofSize: 12); subLabel.textColor = UIColor(white: 1, alpha: 0.8)
        navigationItem.titleView = tv
        setHeader(pageTitle, pageSub)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboard(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        styleBar(C.brand)
    }

    func styleBar(_ color: UIColor) {
        guard let nb = navigationController?.navigationBar else { return }
        nb.barTintColor = color
        nb.barStyle = .black
        nb.tintColor = .white
        nb.isTranslucent = false
        nb.titleTextAttributes = [.foregroundColor: UIColor.white]
        if #available(iOS 13.0, *) {
            let a = UINavigationBarAppearance()
            a.configureWithOpaqueBackground()
            a.backgroundColor = color
            a.titleTextAttributes = [.foregroundColor: UIColor.white]
            a.shadowColor = .clear
            nb.standardAppearance = a
            nb.scrollEdgeAppearance = a
            nb.compactAppearance = a
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }

    @objc func keyboard(_ n: Notification) {
        guard let f = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let overlap = max(0, view.bounds.maxY - view.convert(f, from: nil).minY)
        scroll.contentInset.bottom = overlap
        scroll.scrollIndicatorInsets.bottom = overlap
    }

    func setHeader(_ t: String, _ s: String?) {
        titleLabel.text = t
        subLabel.text = s
        subLabel.isHidden = (s ?? "").isEmpty
        navigationItem.titleView?.sizeToFit()
    }

    func headButton(_ title: String, _ action: Selector) {
        let b = UIBarButtonItem(title: title, style: .plain, target: self, action: action)
        navigationItem.rightBarButtonItems = (navigationItem.rightBarButtonItems ?? []) + [b]
    }

    // MARK: views

    func label(_ t: String, _ size: CGFloat = 14, _ color: UIColor = C.text, bold: Bool = false) -> UILabel {
        let l = UILabel()
        l.text = t
        l.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        l.textColor = color
        l.numberOfLines = 0
        return l
    }

    func fieldLabel(_ t: String) -> UILabel {
        let l = label(t, 13, C.muted, bold: true)
        return l
    }

    /// white rounded card; add rows to the returned stack
    func card(_ bg: UIColor = C.card, onTap: (() -> Void)? = nil) -> (UIView, UIStackView) {
        let v = TapView()
        v.onTap = onTap
        v.backgroundColor = bg
        v.layer.cornerRadius = 14
        v.layer.borderWidth = 1
        v.layer.borderColor = C.line.cgColor
        let s = UIStackView()
        s.axis = .vertical
        s.spacing = 6
        s.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(s)
        NSLayoutConstraint.activate([
            s.topAnchor.constraint(equalTo: v.topAnchor, constant: 14),
            s.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -14),
            s.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 14),
            s.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -14),
        ])
        return (v, s)
    }

    func input(_ placeholder: String, _ kb: UIKeyboardType = .default, secure: Bool = false) -> Field {
        let f = Field()
        f.placeholder = placeholder
        f.keyboardType = kb
        f.isSecureTextEntry = secure
        f.font = .systemFont(ofSize: 16)
        f.textColor = C.text
        f.backgroundColor = .white
        f.layer.cornerRadius = 10
        f.layer.borderWidth = 1
        f.layer.borderColor = UIColor(hex: 0xD1D5DB).cgColor
        f.autocorrectionType = .no
        f.delegate = self
        f.heightAnchor.constraint(equalToConstant: 48).isActive = true
        return f
    }

    func textArea(_ placeholder: String) -> UITextView {
        let t = PlaceholderTextView()
        t.placeholder = placeholder
        t.font = .systemFont(ofSize: 16)
        t.textColor = C.text
        t.layer.cornerRadius = 10
        t.layer.borderWidth = 1
        t.layer.borderColor = UIColor(hex: 0xD1D5DB).cgColor
        t.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        t.isScrollEnabled = false
        t.heightAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true
        return t
    }

    func textFieldShouldReturn(_ tf: UITextField) -> Bool { tf.resignFirstResponder(); return true }

    func badge(_ t: String, _ color: UIColor) -> UILabel {
        let l = PadLabel()
        l.text = t
        l.font = .boldSystemFont(ofSize: 12)
        l.textColor = color
        l.backgroundColor = color.withAlphaComponent(0.12)
        l.layer.cornerRadius = 10
        l.clipsToBounds = true
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.setContentCompressionResistancePriority(.required, for: .horizontal)
        return l
    }

    func row(_ views: [UIView], spacing: CGFloat = 8, equal: Bool = false) -> UIStackView {
        let s = UIStackView(arrangedSubviews: views)
        s.axis = .horizontal
        s.spacing = spacing
        s.alignment = equal ? .fill : .center
        if equal { s.distribution = .fillEqually }
        return s
    }

    /// horizontal scrolling chips (filters)
    func chipBar(_ items: [(String, String)], selected: String, onPick: @escaping (String) -> Void) -> UIView {
        let sv = UIScrollView()
        sv.showsHorizontalScrollIndicator = false
        let st = UIStackView()
        st.axis = .horizontal
        st.spacing = 8
        st.translatesAutoresizingMaskIntoConstraints = false
        sv.addSubview(st)
        NSLayoutConstraint.activate([
            st.topAnchor.constraint(equalTo: sv.contentLayoutGuide.topAnchor),
            st.bottomAnchor.constraint(equalTo: sv.contentLayoutGuide.bottomAnchor),
            st.leadingAnchor.constraint(equalTo: sv.contentLayoutGuide.leadingAnchor),
            st.trailingAnchor.constraint(equalTo: sv.contentLayoutGuide.trailingAnchor),
            st.heightAnchor.constraint(equalTo: sv.frameLayoutGuide.heightAnchor),
            sv.heightAnchor.constraint(equalToConstant: 38),
        ])
        for (key, title) in items {
            let on = key == selected
            let b = Btn(title, bg: on ? C.brand : C.card) { onPick(key) }
            b.titleLabel?.font = .boldSystemFont(ofSize: 13)
            b.layer.cornerRadius = 17
            b.contentEdgeInsets = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
            b.constraints.forEach { if $0.firstAttribute == .height { $0.isActive = false } }
            st.addArrangedSubview(b)
        }
        return sv
    }

    func empty(_ t: String) -> UIView {
        let l = label(t, 15, C.muted)
        l.textAlignment = .center
        let (v, s) = card()
        s.addArrangedSubview(l)
        return v
    }

    func loading() -> UIView {
        let a = UIActivityIndicatorView(style: .gray)
        a.startAnimating()
        a.heightAnchor.constraint(equalToConstant: 60).isActive = true
        return a
    }

    func clear(_ s: UIStackView) { s.arrangedSubviews.forEach { $0.removeFromSuperview() } }

    func spacer(_ h: CGFloat) -> UIView { let v = UIView(); v.heightAnchor.constraint(equalToConstant: h).isActive = true; return v }

    // MARK: messages

    func toast(_ msg: String) {
        let l = PadLabel()
        l.text = msg
        l.numberOfLines = 0
        l.textAlignment = .center
        l.font = .systemFont(ofSize: 14)
        l.textColor = .white
        l.backgroundColor = UIColor(white: 0.1, alpha: 0.9)
        l.layer.cornerRadius = 12
        l.clipsToBounds = true
        l.translatesAutoresizingMaskIntoConstraints = false
        let host: UIView = view.window ?? view
        host.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            l.bottomAnchor.constraint(equalTo: host.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            l.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor, constant: -40),
        ])
        l.alpha = 0
        UIView.animate(withDuration: 0.2, animations: { l.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.3, delay: 2.2, options: [], animations: { l.alpha = 0 }) { _ in l.removeFromSuperview() }
        }
    }

    func alert(_ title: String, _ msg: String, ok: (() -> Void)? = nil) {
        let a = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in ok?() })
        present(a, animated: true)
    }

    func confirm(_ title: String, _ msg: String, yes: String = "Yes", _ go: @escaping () -> Void) {
        let a = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "No", style: .cancel))
        a.addAction(UIAlertAction(title: yes, style: .default) { _ in go() })
        present(a, animated: true)
    }

    func prompt(_ title: String, _ hint: String, value: String = "", secure: Bool = false, required: Bool = true, _ go: @escaping (String) -> Void) {
        let a = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        a.addTextField { t in t.placeholder = hint; t.text = value; t.isSecureTextEntry = secure; t.autocapitalizationType = .sentences }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        a.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            let v = (a.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if v.isEmpty && required { return }
            go(v)
        })
        present(a, animated: true)
    }

    /// list to choose from (action sheet; on iPad it points at `from`)
    func choose(_ title: String?, _ items: [String], from: UIView? = nil, _ go: @escaping (Int) -> Void) {
        let a = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for (i, t) in items.enumerated() { a.addAction(UIAlertAction(title: t, style: .default) { _ in go(i) }) }
        a.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let p = a.popoverPresentationController {
            p.sourceView = from ?? view
            p.sourceRect = (from ?? view).bounds
        }
        present(a, animated: true)
    }

    // MARK: API

    /// Calls the API and runs `done` on the main thread when it worked; shows the error otherwise.
    func run(_ route: String, query: JSON? = nil, body: JSON? = nil, quiet: Bool = false, fail: ((ApiRes) -> Void)? = nil, _ done: @escaping (ApiRes) -> Void) {
        ApiCore.call(route, query: query, body: body) { r in
            DispatchQueue.main.async {
                if r.ok { done(r); return }
                if r.code == 401 && Store.loggedIn {
                    Store.logout()
                    AppDelegate.shared?.showLogin()
                    return
                }
                if r.code == 402 {
                    self.alert("Plan expired", r.message + "\n\nOpen the website to renew.") { self.open(Store.server + "renew.php") }
                } else if !quiet {
                    self.toast(r.message)
                }
                fail?(r)
            }
        }
    }

    func open(_ url: String) {
        guard let u = URL(string: url) else { return }
        UIApplication.shared.open(u, options: [:]) { ok in if !ok { self.toast("No app can open this.") } }
    }
    func callPhone(_ m: String) { open("tel:" + tenDigits(m)) }
    func whatsapp(_ m: String, _ text: String? = nil) {
        let t = (text ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        open("https://wa.me/91" + tenDigits(m) + (t.isEmpty ? "" : "?text=" + t))
    }

    func push(_ vc: UIViewController) { navigationController?.pushViewController(vc, animated: true) }
}

/// label with inner padding (badges, toast)
class PadLabel: UILabel {
    var insets = UIEdgeInsets(top: 4, left: 9, bottom: 4, right: 9)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + insets.left + insets.right, height: s.height + insets.top + insets.bottom)
    }
    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines n: Int) -> CGRect {
        let r = super.textRect(forBounds: bounds.inset(by: insets), limitedToNumberOfLines: n)
        return r.inset(by: UIEdgeInsets(top: -insets.top, left: -insets.left, bottom: -insets.bottom, right: -insets.right))
    }
}

/// UITextView with a grey placeholder
final class PlaceholderTextView: UITextView {
    let ph = UILabel()
    var placeholder: String = "" { didSet { ph.text = placeholder } }
    override var text: String! { didSet { ph.isHidden = !(text ?? "").isEmpty } }
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        ph.textColor = UIColor(hex: 0x9CA3AF)
        ph.font = .systemFont(ofSize: 16)
        ph.translatesAutoresizingMaskIntoConstraints = false
        addSubview(ph)
        NSLayoutConstraint.activate([ph.topAnchor.constraint(equalTo: topAnchor, constant: 10), ph.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13)])
        NotificationCenter.default.addObserver(self, selector: #selector(changed), name: UITextView.textDidChangeNotification, object: self)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc func changed() { ph.isHidden = !text.isEmpty }
}

/// date + time picker in a sheet
final class DatePickVC: UIViewController {
    let picker = UIDatePicker()
    var onPick: ((Date?) -> Void)?
    var allowClear = false
    var mode: UIDatePicker.Mode = .dateAndTime
    var start = Date()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        picker.datePickerMode = mode
        picker.date = start
        picker.locale = Locale(identifier: "en_IN")
        if #available(iOS 13.4, *) { picker.preferredDatePickerStyle = .wheels }
        let ok = Btn("OK", bg: C.orange) { [weak self] in self?.dismiss(animated: true) { self?.onPick?(self?.picker.date) } }
        let cancel = Btn(allowClear ? "Remove" : "Cancel", bg: C.card) { [weak self] in
            let clear = self?.allowClear == true
            self?.dismiss(animated: true) { if clear { self?.onPick?(nil) } }
        }
        let st = UIStackView(arrangedSubviews: [picker, UIStackView(arrangedSubviews: [cancel, ok])])
        (st.arrangedSubviews[1] as? UIStackView)?.spacing = 10
        (st.arrangedSubviews[1] as? UIStackView)?.distribution = .fillEqually
        st.axis = .vertical
        st.spacing = 12
        st.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(st)
        NSLayoutConstraint.activate([
            st.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            st.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            st.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
        ])
    }

    static func show(on vc: UIViewController, mode: UIDatePicker.Mode = .dateAndTime, start: Date, allowClear: Bool = false, _ go: @escaping (Date?) -> Void) {
        let p = DatePickVC()
        p.mode = mode
        p.start = start
        p.allowClear = allowClear
        p.onPick = go
        p.modalPresentationStyle = .formSheet
        vc.present(p, animated: true)
    }
}

func ymdhm(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.string(from: d)
}
func ymd(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
}
func parseDate(_ s: String) -> Date? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    for fmt in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
        f.dateFormat = fmt
        if let d = f.date(from: String(s.prefix(fmt.count))) { return d }
    }
    return nil
}
