import UIKit

/// Owner / reseller: companies (activate expired or suspended, edit), renew payments, support tickets.
/// New companies are made on the website only.
final class PanelVC: BaseVC {
    let stats = UIStackView(), chipsHolder = UIStackView(), list = UIStackView()
    var q: Field!
    var filter = "all"

    override func viewDidLoad() {
        let u = Store.user
        pageTitle = u.s("firm").isEmpty ? "Task Management for Kriva" : u.s("firm")
        pageSub = u.s("name") + " · " + (Store.isOwner ? "Owner" : "Reseller")
        super.viewDidLoad()
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "⋮", style: .plain, target: self, action: #selector(menu)),
            UIBarButtonItem(barButtonSystemItem: .refresh, target: self, action: #selector(load)),
        ]
        stats.axis = .vertical
        stats.spacing = 8
        page.addArrangedSubview(stats)
        page.addArrangedSubview(row([Btn("Renew payments", bg: C.orange) { [weak self] in self?.push(PaymentsVC()) },
                                     Btn("Support tickets", bg: C.brand) { [weak self] in self?.push(TicketsVC()) }], equal: true))
        page.addArrangedSubview(Btn("My notes 🔒", bg: C.card) { [weak self] in self?.push(NotesVC()) })
        page.addArrangedSubview(label("Companies", 17, C.text, bold: true))
        page.addArrangedSubview(chipsHolder)
        q = input("Search company, code, phone")
        q.returnKeyType = .search
        q.clearButtonMode = .whileEditing
        page.addArrangedSubview(q)
        list.axis = .vertical
        list.spacing = 10
        page.addArrangedSubview(list)
        drawChips()
    }

    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); load() }

    override func textFieldShouldReturn(_ tf: UITextField) -> Bool { tf.resignFirstResponder(); loadCompanies(); return true }

    func drawChips() {
        clear(chipsHolder)
        chipsHolder.addArrangedSubview(chipBar([("all", "All"), ("expired", "Expired"), ("expiring", "Ending soon"), ("suspended", "Suspended"), ("active", "Active")],
                                               selected: filter) { [weak self] k in self?.filter = k; self?.drawChips(); self?.loadCompanies() })
    }

    @objc func load() {
        run("p_dashboard") { [weak self] r in
            guard let me = self else { return }
            me.clear(me.stats)
            let s = r.json.o("stats")
            if s.isEmpty { return }
            me.stats.addArrangedSubview(me.row([me.stat(s.i("companies"), "Companies", C.brand, "all"), me.stat(s.i("expired"), "Expired", C.red, "expired"),
                                                me.stat(s.i("expiring"), "Ending soon", C.amber, "expiring")], equal: true))
            me.stats.addArrangedSubview(me.row([me.stat(s.i("suspended"), "Suspended", C.muted, "suspended"), me.stat(s.i("payments"), "Payments to check", C.green, "pay"),
                                                me.stat(s.i("tickets"), "Open tickets", C.violet, "tickets")], equal: true))
        }
        loadCompanies()
    }

    func stat(_ n: Int, _ l: String, _ color: UIColor, _ go: String) -> UIView {
        let (c, s) = card { [weak self] in
            guard let me = self else { return }
            if go == "pay" { me.push(PaymentsVC()) } else if go == "tickets" { me.push(TicketsVC()) } else { me.filter = go; me.drawChips(); me.loadCompanies() }
        }
        s.spacing = 2
        s.addArrangedSubview(label(String(n), 22, color, bold: true))
        let x = label(l, 12, C.muted)
        x.numberOfLines = 1
        x.adjustsFontSizeToFitWidth = true
        x.minimumScaleFactor = 0.7
        s.addArrangedSubview(x)
        return c
    }

    func loadCompanies() {
        clear(list)
        list.addArrangedSubview(loading())
        run("p_companies", query: ["filter": filter, "q": (q.text ?? "").trimmingCharacters(in: .whitespaces)]) { [weak self] r in
            guard let me = self else { return }
            me.clear(me.list)
            let a = r.json.a("companies")
            if a.isEmpty { me.list.addArrangedSubview(me.empty("No companies here.")); return }
            for c in a { me.list.addArrangedSubview(me.companyRow(c)) }
        }
    }

    @objc func menu() {
        if Store.isOwner {
            choose(nil, ["Backup all companies to this phone", "Logout"]) { i in if i == 0 { Backup.start(self) } else { self.logoutAsk() } }
        } else {
            choose(nil, ["Logout"]) { _ in self.logoutAsk() }
        }
    }
}

extension BaseVC {
    func companyRow(_ c: JSON, tap: Bool = true) -> UIView {
        let id = c.i("id")
        var open: (() -> Void)? = nil
        if tap { open = { [weak self] in self?.push(CompanyEditVC(id: id)) } }
        let (k, s) = card(onTap: open)
        let st = c.s("state")
        s.addArrangedSubview(row([label(c.s("name"), 16, C.text, bold: true),
                                  badge(st == "expired" ? "Expired" : st == "expiring" ? "Ending soon" : st == "suspended" ? "Suspended" : "Active",
                                        st == "expired" ? C.red : st == "expiring" ? C.amber : st == "suspended" ? C.muted : C.green)]))
        s.addArrangedSubview(label(c.s("code") + " · " + c.s("phone"), 13, C.muted))
        let till = c.s("valid_till"), left = c.i("days_left")
        let amt = c.d("plan_amount") ?? 0
        s.addArrangedSubview(label((till.isEmpty ? "No end date" : "Valid till " + fmtDate(till) + (left >= 0 ? " (\(left) days left)" : " (ended \(-left) days ago)"))
                                   + " · Users \(c.i("users"))/\(c.i("max_users"))" + (amt > 0 ? " · " + money(amt) : ""), 13))
        return k
    }
}

/// Owner / reseller: change an existing company (activate, suspend, extend plan, amount, users). No new company from the app.
final class CompanyEditVC: BaseVC {
    let id: Int
    let body = UIStackView()
    var name: Field!, phone: Field!, email: Field!, address: Field!, maxUsers: Field!, amount: Field!
    var till: SelectBox!
    var tillVal = ""

    init(id: Int) { self.id = id; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        pageTitle = "Company"
        super.viewDidLoad()
        body.axis = .vertical
        body.spacing = 10
        page.addArrangedSubview(body)
        load()
    }

    func load() {
        clear(body)
        body.addArrangedSubview(loading())
        run("p_company", query: ["id": id], fail: { [weak self] _ in self?.navigationController?.popViewController(animated: true) }) { [weak self] r in self?.show(r.json) }
    }

    func show(_ d: JSON) {
        clear(body)
        let c = d.o("company")
        setHeader(c.s("name"), c.s("code") + " · " + c.s("db_name"))
        body.addArrangedSubview(companyRow(c, tap: false))

        let adm = d.o("admin")
        if !adm.isEmpty {
            let (a, s) = card()
            s.addArrangedSubview(label("Company admin: " + adm.s("name"), 15, C.text, bold: true))
            s.addArrangedSubview(label(adm.s("mobile"), 14, C.muted))
            let m = adm.s("mobile")
            s.addArrangedSubview(row([Btn("📞 Call", bg: C.card) { [weak self] in self?.callPhone(m) },
                                      Btn("WhatsApp", bg: C.card) { [weak self] in self?.whatsapp(m) }], equal: true))
            body.addArrangedSubview(a)
        }

        let active = c.s("status") == "active"
        let (qv, qs) = card()
        qs.spacing = 8
        qs.addArrangedSubview(label("Quick actions", 15, C.text, bold: true))
        qs.addArrangedSubview(row([Btn("+1 year", bg: C.green) { [weak self] in self?.extend(12) }, Btn("+1 month", bg: C.green) { [weak self] in self?.extend(1) }], equal: true))
        if active {
            qs.addArrangedSubview(Btn("Suspend (stop login)", bg: C.card) { [weak self] in
                self?.confirm("Suspend", "Users of this company will not be able to log in. Suspend?") { self?.send(["id": self?.id ?? 0, "action": "suspend"]) }
            })
        } else {
            qs.addArrangedSubview(Btn("Activate", bg: C.green) { [weak self] in self?.send(["id": self?.id ?? 0, "action": "activate"]) })
        }
        body.addArrangedSubview(qv)

        let (fv, f) = card()
        f.addArrangedSubview(label("Edit details", 15, C.text, bold: true))
        f.addArrangedSubview(fieldLabel("Company name"))
        name = input("Name"); name.autocapitalizationType = .words; name.text = c.s("name"); f.addArrangedSubview(name)
        f.addArrangedSubview(fieldLabel("Phone"))
        phone = input("Phone", .phonePad); phone.text = c.s("phone"); f.addArrangedSubview(phone)
        f.addArrangedSubview(fieldLabel("Email"))
        email = input("Email", .emailAddress); email.autocapitalizationType = .none; email.text = c.s("email"); f.addArrangedSubview(email)
        f.addArrangedSubview(fieldLabel("Address"))
        address = input("Address"); address.text = c.s("address"); f.addArrangedSubview(address)
        f.addArrangedSubview(fieldLabel("Max users"))
        maxUsers = input("10", .numberPad); maxUsers.text = String(c.i("max_users")); f.addArrangedSubview(maxUsers)
        f.addArrangedSubview(fieldLabel("Renewal amount (₹) - shown with the UPI QR before expiry"))
        amount = input("Empty = default amount", .decimalPad)
        if let a = c.d("own_amount") { amount.text = a == a.rounded() ? String(Int(a)) : String(a) }
        f.addArrangedSubview(amount)
        f.addArrangedSubview(fieldLabel("Valid till"))
        tillVal = c.s("valid_till")
        till = SelectBox("") { [weak self] _ in self?.pickTill() }
        f.addArrangedSubview(till)
        showTill()
        f.addArrangedSubview(spacer(4))
        f.addArrangedSubview(Btn("Save", bg: C.orange) { [weak self] in self?.save() })
        body.addArrangedSubview(fv)

        let pays = d.a("payments")
        if !pays.isEmpty {
            let (pv, p) = card()
            p.addArrangedSubview(label("Renew payments", 15, C.text, bold: true))
            for x in pays {
                p.addArrangedSubview(label(fmtDate(x.s("created_at")) + " · " + (x.d("amount").map { money($0) } ?? "-") + " · " + x.s("status"), 14))
            }
            body.addArrangedSubview(pv)
        }
    }

    func extend(_ months: Int) {
        confirm("Extend plan", "Extend the plan by " + (months == 12 ? "1 year" : "\(months) month") + " and make it active?") {
            self.send(["id": self.id, "action": "extend", "months": months])
        }
    }

    func send(_ o: JSON) {
        run("p_company_save", body: o) { [weak self] r in self?.toast(r.message); self?.load() }
    }

    func showTill() { till.text = tillVal.isEmpty ? "📅 No end date (tap to set)" : "📅 " + fmtDate(tillVal) + "  (change)" }

    func pickTill() {
        DatePickVC.show(on: self, mode: .date, start: parseDate(tillVal) ?? Date(), allowClear: true) { [weak self] d in
            self?.tillVal = d.map { ymd($0) } ?? ""
            self?.showTill()
        }
    }

    func save() {
        let n = (name.text ?? "").trimmingCharacters(in: .whitespaces)
        if n.isEmpty { toast("Name is required"); return }
        func v(_ f: Field) -> String { return (f.text ?? "").trimmingCharacters(in: .whitespaces) }
        send(["id": id, "action": "save", "name": n, "phone": v(phone), "email": v(email), "address": v(address),
              "max_users": v(maxUsers), "plan_amount": v(amount), "valid_till": tillVal])
    }
}

/// Renewal payment screenshots from companies: approve (new valid till date) or reject.
final class PaymentsVC: BaseVC {
    var status = "pending"
    let chipsHolder = UIStackView(), list = UIStackView()

    override func viewDidLoad() {
        pageTitle = "Renew payments"
        pageSub = "Screenshots sent by companies"
        super.viewDidLoad()
        page.addArrangedSubview(chipsHolder)
        list.axis = .vertical
        list.spacing = 10
        page.addArrangedSubview(list)
        draw()
        load()
    }

    func draw() {
        clear(chipsHolder)
        chipsHolder.addArrangedSubview(chipBar([("pending", "To check"), ("all", "All")], selected: status) { [weak self] k in self?.status = k; self?.draw(); self?.load() })
    }

    func load() {
        clear(list)
        list.addArrangedSubview(loading())
        run("p_payments", query: ["status": status]) { [weak self] r in
            guard let me = self else { return }
            me.clear(me.list)
            let a = r.json.a("payments")
            if a.isEmpty { me.list.addArrangedSubview(me.empty("Nothing to check.")); return }
            for p in a { me.list.addArrangedSubview(me.payRow(p)) }
        }
    }

    func payRow(_ p: JSON) -> UIView {
        let (c, s) = card()
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.backgroundColor = UIColor(hex: 0xF3F4F6)
        iv.layer.cornerRadius = 8
        iv.widthAnchor.constraint(equalToConstant: 70).isActive = true
        iv.heightAnchor.constraint(equalToConstant: 90).isActive = true
        iv.isUserInteractionEnabled = true
        let tap = TapView()
        tap.addSubview(iv)
        iv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([iv.topAnchor.constraint(equalTo: tap.topAnchor), iv.bottomAnchor.constraint(equalTo: tap.bottomAnchor),
                                     iv.leadingAnchor.constraint(equalTo: tap.leadingAnchor), iv.trailingAnchor.constraint(equalTo: tap.trailingAnchor)])
        tap.onTap = { [weak self] in if let im = iv.image { self?.showBig(im) } }
        iv.isUserInteractionEnabled = false
        loadImage(p.i("id"), iv)
        let tx = UIStackView()
        tx.axis = .vertical
        tx.spacing = 3
        tx.addArrangedSubview(label(p.s("company"), 16, C.text, bold: true))
        tx.addArrangedSubview(label((p.d("amount").map { money($0) } ?? "-") + (p.s("note").isEmpty ? "" : " · " + p.s("note")), 14))
        tx.addArrangedSubview(label(fmtDate(p.s("created_at")) + " · " + p.s("sent_by") + " " + p.s("mobile"), 12, C.muted))
        let st = p.s("status")
        tx.addArrangedSubview(label(st == "approved" ? "Approved" : st == "rejected" ? "Rejected" : "To check", 13, st == "approved" ? C.green : st == "rejected" ? C.red : C.amber, bold: true))
        if !p.s("owner_note").isEmpty { tx.addArrangedSubview(label(p.s("owner_note"), 12, C.muted)) }
        let r = row([tap, tx], spacing: 12)
        r.alignment = .top
        s.addArrangedSubview(r)
        if st == "pending" {
            let pid = p.i("id")
            s.addArrangedSubview(row([
                Btn("Approve", bg: C.green) { [weak self] in self?.approve(p) },
                Btn("Reject", bg: C.card) { [weak self] in
                    self?.prompt("Reject payment", "Reason (customer sees it)", required: false) { why in self?.act(["id": pid, "action": "reject", "note": why]) }
                },
            ], equal: true))
        }
        return c
    }

    func loadImage(_ id: Int, _ iv: UIImageView) {
        guard let req = ApiCore.request("p_proof", query: ["id": id]) else { return }
        URLSession.shared.dataTask(with: req) { d, _, _ in
            guard let d = d, let im = UIImage(data: d) else { return }
            DispatchQueue.main.async { iv.image = im }
        }.resume()
    }

    func showBig(_ im: UIImage) {
        let vc = UIViewController()
        vc.view.backgroundColor = .black
        let iv = UIImageView(image: im)
        iv.contentMode = .scaleAspectFit
        iv.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(iv)
        let close = Btn("Close", bg: C.card) { [weak vc] in vc?.dismiss(animated: true) }
        close.translatesAutoresizingMaskIntoConstraints = false
        vc.view.addSubview(close)
        NSLayoutConstraint.activate([
            iv.topAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.topAnchor), iv.bottomAnchor.constraint(equalTo: close.topAnchor, constant: -10),
            iv.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor), iv.trailingAnchor.constraint(equalTo: vc.view.trailingAnchor),
            close.bottomAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            close.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor), close.widthAnchor.constraint(equalToConstant: 160),
        ])
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }

    func approve(_ p: JSON) {
        let pid = p.i("id")
        DatePickVC.show(on: self, mode: .date, start: parseDate(p.s("next_valid_till")) ?? Date()) { [weak self] d in
            guard let d = d else { return }
            self?.act(["id": pid, "action": "approve", "valid_till": ymd(d)])
        }
    }

    func act(_ o: JSON) { run("p_payment_action", body: o) { [weak self] r in self?.toast(r.message); self?.load() } }
}

/// Support tickets from companies (reseller: only own companies).
final class TicketsVC: BaseVC {
    var tab = "open"
    let chipsHolder = UIStackView(), list = UIStackView()

    override func viewDidLoad() {
        pageTitle = "Support tickets"
        pageSub = "Problems sent by companies"
        super.viewDidLoad()
        page.addArrangedSubview(chipsHolder)
        list.axis = .vertical
        list.spacing = 10
        page.addArrangedSubview(list)
        draw()
    }

    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); load() }

    func draw() {
        clear(chipsHolder)
        chipsHolder.addArrangedSubview(chipBar([("open", "Open"), ("answered", "Answered"), ("closed", "Closed"), ("all", "All")], selected: tab) { [weak self] k in
            self?.tab = k; self?.draw(); self?.load()
        })
    }

    func load() {
        clear(list)
        list.addArrangedSubview(loading())
        run("p_tickets", query: ["tab": tab]) { [weak self] r in
            guard let me = self else { return }
            me.clear(me.list)
            let a = r.json.a("tickets")
            if a.isEmpty { me.list.addArrangedSubview(me.empty("No tickets here.")); return }
            for t in a {
                let tid = t.i("id")
                let (c, s) = me.card { [weak me] in me?.push(TicketVC(id: tid)) }
                let st = t.s("status")
                s.addArrangedSubview(me.row([me.label("#\(tid) " + t.s("subject"), 16, C.text, bold: true), me.badge(st, st == "open" ? C.amber : st == "answered" ? C.green : C.muted)]))
                s.addArrangedSubview(me.label((t.s("company").isEmpty ? "Main page visitor" : t.s("company")) + " · " + t.s("name") + " " + t.s("mobile"), 13, C.muted))
                s.addArrangedSubview(me.label(fmtDate(t.s("updated_at").isEmpty ? t.s("created_at") : t.s("updated_at")) + " · \(t.i("messages")) messages", 12, C.muted))
                me.list.addArrangedSubview(c)
            }
        }
    }
}

/// One support ticket: messages, reply, close / reopen.
final class TicketVC: BaseVC {
    let id: Int
    let body = UIStackView()

    init(id: Int) { self.id = id; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        pageTitle = "Ticket #\(id)"
        super.viewDidLoad()
        body.axis = .vertical
        body.spacing = 10
        page.addArrangedSubview(body)
        call("p_ticket", nil)
    }

    func call(_ route: String, _ extra: JSON?) {
        if var o = extra {
            o["id"] = id
            run(route, body: o) { [weak self] r in self?.toast(r.message); self?.show(r.json) }
        } else {
            run(route, query: ["id": id]) { [weak self] r in self?.show(r.json) }
        }
    }

    func show(_ d: JSON) {
        clear(body)
        let t = d.o("ticket")
        setHeader("#\(id) " + t.s("subject"), (t.s("company").isEmpty ? "Main page visitor" : t.s("company")) + " · " + t.s("status"))
        let mob = t.s("mobile")
        if !mob.isEmpty {
            body.addArrangedSubview(row([Btn("📞 " + mob, bg: C.card) { [weak self] in self?.callPhone(mob) },
                                         Btn("WhatsApp", bg: C.card) { [weak self] in self?.whatsapp(mob) }], equal: true))
        }
        for m in d.a("messages") {
            let mine = m.s("from") == "owner"
            let (c, s) = card(mine ? UIColor(hex: 0xEEF2FF) : C.card)
            s.addArrangedSubview(label(m.s("name") + " · " + fmtDate(m.s("at")), 12, C.muted, bold: true))
            s.addArrangedSubview(label(m.s("message"), 15))
            let wrap = UIView()
            c.translatesAutoresizingMaskIntoConstraints = false
            wrap.addSubview(c)
            NSLayoutConstraint.activate([
                c.topAnchor.constraint(equalTo: wrap.topAnchor), c.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
                c.leadingAnchor.constraint(equalTo: wrap.leadingAnchor, constant: mine ? 30 : 0),
                c.trailingAnchor.constraint(equalTo: wrap.trailingAnchor, constant: mine ? 0 : -30),
            ])
            body.addArrangedSubview(wrap)
        }
        let (fv, f) = card()
        f.spacing = 10
        let msg = textArea("Your reply")
        msg.heightAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
        f.addArrangedSubview(msg)
        let close = UISwitch()
        close.onTintColor = C.orange
        f.addArrangedSubview(row([close, label("Close the ticket after this reply", 14)], spacing: 10))
        let closed = t.s("status") == "closed"
        f.addArrangedSubview(row([
            Btn("Send reply", bg: C.orange) { [weak self] in
                let s = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if s.isEmpty { self?.toast("Write a reply"); return }
                self?.call("p_ticket_reply", ["message": s, "close": close.isOn ? 1 : 0])
            },
            Btn(closed ? "Reopen" : "Close", bg: C.card) { [weak self] in self?.call("p_ticket_status", ["action": closed ? "reopen" : "close"]) },
        ], equal: true))
        body.addArrangedSubview(fv)
        DispatchQueue.main.async {
            let y = max(0, self.scroll.contentSize.height - self.scroll.bounds.height + self.scroll.contentInset.bottom)
            self.scroll.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        }
    }
}
