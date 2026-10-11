import UIKit

/// Company admin / staff home: quick tiles and the works that need attention.
final class HomeVC: BaseVC {
    let body = UIStackView()

    override func viewDidLoad() {
        let u = Store.user
        let co = u.o("company")
        pageTitle = co.s("name").isEmpty ? "Task Management for Kriva" : co.s("name")
        pageSub = u.s("name") + " · " + (Store.isAdmin ? "Admin" : "Staff")
        super.viewDidLoad()
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "⋮", style: .plain, target: self, action: #selector(menu)),
            UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(load)),
        ]
        let logo = UIImageView(image: UIImage(named: "KrivaLogo"))
        logo.contentMode = .scaleAspectFit
        logo.backgroundColor = .white
        logo.layer.cornerRadius = 16
        logo.clipsToBounds = true
        logo.frame = CGRect(x: 0, y: 0, width: 32, height: 32)
        logo.widthAnchor.constraint(equalToConstant: 32).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 32).isActive = true
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: logo)

        let h = Calendar.current.component(.hour, from: Date())
        page.addArrangedSubview(label(h < 12 ? "Good Morning ☀️" : h < 17 ? "Good Afternoon 🌤️" : "Good Evening 🌙", 20, C.text, bold: true))
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE, dd MMM yyyy"
        let day = label(f.string(from: Date()) + "  ·  " + (Store.isAdmin ? "Admin Panel" : "Staff Panel"), 13, C.muted)
        page.addArrangedSubview(day)
        page.setCustomSpacing(14, after: day)
        page.addArrangedSubview(row([tile("➕", "Add Work", "नया काम जोड़ें") { [weak self] in self?.push(AddWorkVC()) },
                                     tile("📋", "View Work", Store.isAdmin ? "सभी काम" : "मेरे काम") { [weak self] in self?.push(WorksVC()) }], spacing: 12, equal: true))
        page.addArrangedSubview(row([tile("🔳", "Payment QR", "Payment QR बनाएँ") { [weak self] in self?.push(QrVC()) },
                                     tile("📝", "My Notes", "सिर्फ इस फोन में 🔒") { [weak self] in self?.push(NotesVC()) }], spacing: 12, equal: true))
        if Store.isAdmin {
            page.addArrangedSubview(row([tile("💾", "Backup", "पूरा SQL बैकअप फोन में") { [weak self] in if let s = self { Backup.start(s) } },
                                         tile("🧩", "Widgets", "होम स्क्रीन विजेट") { [weak self] in self?.widgetHelp() }], spacing: 12, equal: true))
        }
        body.axis = .vertical
        body.spacing = 10
        page.addArrangedSubview(body)
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        load()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Backup.maybeAuto(self)
    }

    @objc func becameActive() {
        guard navigationController?.topViewController === self else { return }
        load()
        Backup.maybeAuto(self)
    }

    /// Home tile: icon bubble, title, small line
    func tile(_ icon: String, _ title: String, _ sub: String, _ tap: @escaping () -> Void) -> UIView {
        let (v, s) = card(onTap: tap)
        v.layer.cornerRadius = 16
        v.layer.shadowColor = UIColor.black.cgColor
        v.layer.shadowOpacity = 0.05; v.layer.shadowRadius = 4; v.layer.shadowOffset = CGSize(width: 0, height: 2)
        v.heightAnchor.constraint(equalToConstant: 124).isActive = true
        s.alignment = .leading
        s.spacing = 2
        let ic = label(icon, 22)
        ic.textAlignment = .center
        ic.backgroundColor = UIColor(hex: 0xFFEDE5)
        ic.layer.cornerRadius = 14
        ic.clipsToBounds = true
        ic.widthAnchor.constraint(equalToConstant: 46).isActive = true
        ic.heightAnchor.constraint(equalToConstant: 46).isActive = true
        s.addArrangedSubview(ic)
        let grow = UIView()
        grow.setContentHuggingPriority(.defaultLow, for: .vertical)
        s.addArrangedSubview(grow)
        s.addArrangedSubview(label(title, 15, C.text, bold: true))
        let l2 = label(sub, 12, C.muted)
        l2.numberOfLines = 1
        s.addArrangedSubview(l2)
        return v
    }

    @objc func load() {
        if body.arrangedSubviews.isEmpty { body.addArrangedSubview(loading()) }
        run("dashboard", query: ["limit": 30]) { [weak self] r in self?.show(r.json) }
        AppDelegate.shared?.refreshWidgets()
    }

    func show(_ d: JSON) {
        clear(body)
        let ren = d.o("renewal")
        if ren.b("due") && Store.isAdmin {
            let (c, s) = card(UIColor(hex: 0xFFFAF0))
            c.layer.borderColor = UIColor(hex: 0xF6D9A8).cgColor
            let left = ren.i("days_left")
            s.addArrangedSubview(label(left > 0 ? "Your plan ends in \(left) day" + (left == 1 ? "" : "s") : (left == 0 ? "Your plan ends today" : "Your plan has ended"), 16, UIColor(hex: 0x7C4A03), bold: true))
            let amt = (ren.d("amount") ?? 0) > 0 ? "Pay " + money(ren.d("amount") ?? 0) + " to renew." : "Please renew your plan."
            s.addArrangedSubview(label("Valid till " + fmtDate(ren.s("valid_till")) + ". " + amt, 14))
            var bs: [UIView] = []
            let upi = ren.s("upi_link")
            if !upi.isEmpty { bs.append(Btn("Pay in UPI app", bg: C.orange) { [weak self] in self?.open(upi) }) }
            bs.append(Btn("Upload screenshot", bg: C.card) { [weak self] in self?.open(Store.server + "renew.php") })
            s.addArrangedSubview(row(bs, equal: true))
            body.addArrangedSubview(c)
        }
        body.addArrangedSubview(label("Needs attention", 17, C.text, bold: true))
        let ws = d.a("needs_attention")
        if ws.isEmpty { body.addArrangedSubview(empty("Nothing pending. Great work!")) }
        for w in ws { body.addArrangedSubview(workRow(w)) }
    }

    @objc func menu() {
        var items: [(String, () -> Void)] = []
        if Store.isAdmin { items.append(("Backup to this phone now", { [weak self] in if let s = self { Backup.start(s) } })) }
        items.append(("How to add widgets", { [weak self] in self?.widgetHelp() }))
        items.append(("Change password", { [weak self] in self?.changePassword() }))
        items.append(("Logout", { [weak self] in self?.logoutAsk() }))
        choose(nil, items.map { $0.0 }, from: nil) { i in items[i].1() }
    }

    func widgetHelp() { BaseVC.widgetHelp(self) }

    func changePassword() {
        prompt("Old password", "Old password", secure: true) { old in
            self.prompt("New password", "At least 6 characters", secure: true) { nw in
                self.run("password", body: ["old_password": old, "new_password": nw]) { r in self.toast(r.message) }
            }
        }
    }
}

extension BaseVC {
    static func widgetHelp(_ vc: BaseVC) {
        vc.alert("Home screen widgets",
                 "Press and hold an empty place on the home screen → tap + (top corner) → search \"Kriva\".\n\n"
                 + "1. Customers – name + mobile, tap a work to open it or ✓ to mark it done\n"
                 + "2. Category wise – works grouped by category\n"
                 + "3. Work details – customer, work and category\n"
                 + "4. My notes – your personal notes, only on this phone\n\n"
                 + "Admin sees all works, staff sees the works given to them. Widgets need iOS 14 or newer and refresh about every 15 minutes, and right away when you change something in the app.")
    }

    func logoutAsk() {
        confirm("Logout", "Logout from this phone?") {
            ApiCore.call("logout", body: [:]) { _ in }
            Store.logout()
            AppDelegate.shared?.showLogin()
        }
    }

    /// One work in a list: customer, work, category, status, staff, due. Tap opens it.
    func workRow(_ w: JSON) -> UIView {
        let id = w.i("id")
        let (c, s) = card { [weak self] in self?.push(WorkVC(id: id)) }
        let cu = w.o("customer")
        let name = label("#\(id)  " + cu.s("name"), 16, C.text, bold: true)
        s.addArrangedSubview(row([name, badge(w.s("status_label"), C.status(w.s("status")))]))
        s.addArrangedSubview(label(w.s("title"), 14))
        var meta = ""
        if !w.s("category").isEmpty { meta += w.s("category") + " · " }
        if !cu.s("mobile").isEmpty { meta += cu.s("mobile") + " · " }
        meta += w.o("staff").s("name").isEmpty ? "Not assigned" : w.o("staff").s("name")
        s.addArrangedSubview(label(meta, 12, C.muted))
        if !w.s("due_at").isEmpty && w.s("status") != "done" {
            let od = w.b("overdue")
            s.addArrangedSubview(label((od ? "⚠ Overdue " : "Due ") + fmtDate(w.s("due_at")), 12, od ? C.red : C.muted, bold: od))
        }
        let pr = w.s("priority")
        if pr == "urgent" || pr == "high" { s.addArrangedSubview(row([badge(pr.uppercased(), C.red), UIView()])) }
        return c
    }

    /// "Category    Electrical" line on the details card
    func info(_ k: String, _ v: String) -> UIView {
        let a = label(k, 13, C.muted)
        a.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let b = label(v.isEmpty ? "-" : v, 14)
        let r = row([a, b])
        r.alignment = .firstBaseline
        return r
    }
}
