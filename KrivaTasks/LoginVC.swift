import UIKit

/// One login for everybody: company admin / staff (mobile), reseller (mobile), owner (user name).
final class LoginVC: BaseVC {
    var login: Field!, pass: Field!
    var go: Btn!

    override func viewDidLoad() {
        super.viewDidLoad()
        navigationController?.setNavigationBarHidden(true, animated: false)
        page.layoutMargins = .zero
        page.spacing = 0
        // status bar strip in the header colour
        let strip = UIView()
        strip.backgroundColor = UIColor(hex: 0x16306B)
        strip.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: view.topAnchor), strip.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            strip.leadingAnchor.constraint(equalTo: view.leadingAnchor), strip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // brand header: logo in a white circle, name, tagline
        let head = GradientView(top: UIColor(hex: 0x16306B), bottom: C.navy)
        head.layer.cornerRadius = 28
        if #available(iOS 11.0, *) { head.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] }
        let hs = UIStackView()
        hs.axis = .vertical
        hs.alignment = .center
        hs.spacing = 4
        hs.translatesAutoresizingMaskIntoConstraints = false
        head.addSubview(hs)
        NSLayoutConstraint.activate([
            hs.topAnchor.constraint(equalTo: head.topAnchor, constant: 36),
            hs.bottomAnchor.constraint(equalTo: head.bottomAnchor, constant: -74),
            hs.leadingAnchor.constraint(equalTo: head.leadingAnchor, constant: 20),
            hs.trailingAnchor.constraint(equalTo: head.trailingAnchor, constant: -20),
        ])
        let circle = UIView()
        circle.backgroundColor = .white
        circle.layer.cornerRadius = 52
        circle.layer.shadowOpacity = 0.25; circle.layer.shadowRadius = 6; circle.layer.shadowOffset = CGSize(width: 0, height: 3)
        let logo = UIImageView(image: UIImage(named: "KrivaLogo"))
        logo.contentMode = .scaleAspectFit
        logo.translatesAutoresizingMaskIntoConstraints = false
        circle.addSubview(logo)
        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: 104), circle.heightAnchor.constraint(equalToConstant: 104),
            logo.topAnchor.constraint(equalTo: circle.topAnchor, constant: 12), logo.bottomAnchor.constraint(equalTo: circle.bottomAnchor, constant: -12),
            logo.leadingAnchor.constraint(equalTo: circle.leadingAnchor, constant: 12), logo.trailingAnchor.constraint(equalTo: circle.trailingAnchor, constant: -12),
        ])
        hs.addArrangedSubview(circle)
        hs.setCustomSpacing(14, after: circle)
        let t = label("Task Management for Kriva", 23, .white, bold: true)
        t.textAlignment = .center
        hs.addArrangedSubview(t)
        let st = label("Work · Staff · Payments", 13, UIColor(hex: 0xFFC4A8))
        st.textAlignment = .center
        hs.addArrangedSubview(st)
        page.addArrangedSubview(head)

        // login card, overlapping the header
        let (c, cs) = card()
        c.layer.cornerRadius = 18
        c.layer.shadowOpacity = 0.12; c.layer.shadowRadius = 10; c.layer.shadowOffset = CGSize(width: 0, height: 4)
        cs.spacing = 12
        cs.addArrangedSubview(label("Welcome back 👋", 20, C.text, bold: true))
        let sub = label("Mobile number और password डालें", 13, C.muted)
        cs.addArrangedSubview(sub)
        cs.setCustomSpacing(4, after: cs.arrangedSubviews[0])
        login = input("📱  Mobile / Username", .asciiCapable)
        login.autocapitalizationType = .none
        login.text = Store.get("last_login")
        login.returnKeyType = .next
        pass = input("🔒  Password", secure: true)
        pass.returnKeyType = .go
        cs.addArrangedSubview(login)
        cs.addArrangedSubview(pass)
        go = Btn("Login", bg: C.orange) { [weak self] in self?.doLogin() }
        go.heightAnchor.constraint(equalToConstant: 52).isActive = true
        cs.addArrangedSubview(go)
        let help = label("Admin, staff, reseller और owner सब यहीं से login करें (website वाला mobile / username और password)।", 12, C.muted)
        help.textAlignment = .center
        cs.addArrangedSubview(help)
        let wrap = UIView()
        c.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(c)
        NSLayoutConstraint.activate([
            c.topAnchor.constraint(equalTo: wrap.topAnchor), c.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            c.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: 20), c.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: -20),
            c.widthAnchor.constraint(lessThanOrEqualToConstant: 520),
        ])
        page.addArrangedSubview(wrap)
        page.setCustomSpacing(-48, after: head)
        let by = label("Kriva Infosys, Surat", 12, C.muted)
        by.textAlignment = .center
        page.addArrangedSubview(spacer(28))
        page.addArrangedSubview(by)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func textFieldShouldReturn(_ tf: UITextField) -> Bool {
        if tf === login { pass.becomeFirstResponder() } else { doLogin() }
        return true
    }

    func doLogin() {
        let l = (login.text ?? "").trimmingCharacters(in: .whitespaces)
        let p = pass.text ?? ""
        if l.isEmpty { toast("Enter your mobile number"); login.becomeFirstResponder(); return }
        if p.isEmpty { toast("Enter password"); pass.becomeFirstResponder(); return }
        view.endEditing(true)
        go.isEnabled = false
        go.setTitle("Please wait…", for: .normal)
        let device = "Apple " + UIDevice.current.model + " (iOS " + UIDevice.current.systemVersion + ")"
        ApiCore.call("login", body: ["mobile": l, "password": p, "device": device]) { r in
            DispatchQueue.main.async {
                self.go.isEnabled = true
                self.go.setTitle("Login", for: .normal)
                if r.ok && !r.json.s("token").isEmpty {
                    let kind = r.json.s("kind").isEmpty ? "company" : r.json.s("kind")
                    Store.saveLogin(token: r.json.s("token"), kind: kind, user: r.json.o("user"))
                    Store.put("last_login", l)
                    AppDelegate.shared?.showHome()
                    return
                }
                if r.code == 0 || r.code >= 500 || r.json.isEmpty {
                    self.alert("Login nahi hua", r.message + "\n\nWebsite: " + Store.server + "kriva_api.php\nCode: \(r.code)\n\nIs screen ka screenshot Kriva Infosys ko bhejein.")
                } else {
                    self.toast(r.message)
                }
                self.checkServer()
            }
        }
    }

    /// After a failed login: tell the owner if the website still runs the version without the app login.
    func checkServer() {
        ApiCore.call("ping") { r in
            let v = r.json.s("version")
            guard r.ok, !v.isEmpty, v.compare("1.1", options: .numeric) == .orderedAscending else { return }
            DispatchQueue.main.async {
                self.alert("Website needs the update", "The website runs an older version (API \(v)). Upload wwwroot-update.zip on the server, then log in again.")
            }
        }
    }
}

/// view with a top-to-bottom colour gradient
final class GradientView: UIView {
    override class var layerClass: AnyClass { return CAGradientLayer.self }
    convenience init(top: UIColor, bottom: UIColor) {
        self.init(frame: .zero)
        (layer as? CAGradientLayer)?.colors = [top.cgColor, bottom.cgColor]
    }
}
