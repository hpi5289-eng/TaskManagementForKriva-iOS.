import UIKit

/// View works: filter (open, overdue, due today, approval, done, all) + search.
final class WorksVC: BaseVC {
    static let filters = [("open", "Open"), ("overdue", "Overdue"), ("duetoday", "Due today"), ("approval", "Approval"),
                          ("pending", "Pending"), ("assigned", "Assigned"), ("progress", "In progress"), ("done", "Done"), ("all", "All")]
    var status = "open"
    var pageNo = 1, pages = 1
    let chipsHolder = UIStackView(), list = UIStackView()
    var q: Field!
    var more: Btn!

    override func viewDidLoad() {
        pageTitle = "Works"
        pageSub = Store.isAdmin ? "All works of the company" : "Works given to you"
        super.viewDidLoad()
        headButton("＋ Add", #selector(add))
        page.addArrangedSubview(chipsHolder)
        q = input("Search customer, mobile, work, #id")
        q.returnKeyType = .search
        q.clearButtonMode = .whileEditing
        page.addArrangedSubview(q)
        list.axis = .vertical
        list.spacing = 10
        page.addArrangedSubview(list)
        more = Btn("Load more", bg: C.card) { [weak self] in guard let s = self else { return }; s.pageNo += 1; s.load() }
        more.isHidden = true
        page.addArrangedSubview(more)
        drawChips()
    }

    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); reload() }

    @objc func add() { push(AddWorkVC()) }

    override func textFieldShouldReturn(_ tf: UITextField) -> Bool { tf.resignFirstResponder(); reload(); return true }

    func drawChips() {
        clear(chipsHolder)
        chipsHolder.addArrangedSubview(chipBar(WorksVC.filters, selected: status) { [weak self] k in self?.status = k; self?.drawChips(); self?.reload() })
    }

    func reload() { pageNo = 1; clear(list); list.addArrangedSubview(loading()); load() }

    func load() {
        let qs = (q.text ?? "").trimmingCharacters(in: .whitespaces)
        let p = pageNo
        run("works", query: ["status": status, "q": qs, "page": p, "per_page": 30]) { [weak self] r in
            guard let s = self, s.pageNo == p else { return }
            if p == 1 { s.clear(s.list) }
            s.pages = max(1, r.json.i("pages"))
            let ws = r.json.a("works")
            if p == 1 && ws.isEmpty { s.list.addArrangedSubview(s.empty("No works here.")) }
            for w in ws { s.list.addArrangedSubview(s.workRow(w)) }
            s.more.isHidden = p >= s.pages
            s.setHeader("Works", "\(r.json.i("total")) works")
        }
    }
}

/// One work: details, history, and the buttons this user may use (start, done, assign, approve...).
final class WorkVC: BaseVC {
    let id: Int
    var work: JSON = [:]
    let body = UIStackView()

    init(id: Int) { self.id = id; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        pageTitle = "Work #\(id)"
        super.viewDidLoad()
        body.axis = .vertical
        body.spacing = 10
        page.addArrangedSubview(body)
    }

    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); load() }

    func load() {
        if body.arrangedSubviews.isEmpty { body.addArrangedSubview(loading()) }
        run("work", query: ["id": id], fail: { [weak self] r in if r.code == 404 { self?.navigationController?.popViewController(animated: true) } }) { [weak self] r in
            self?.show(r.json.o("work"), r.json.a("notes"))
        }
    }

    func show(_ w: JSON, _ notes: [JSON]) {
        work = w
        clear(body)
        let cu = w.o("customer")
        let (c, s) = card()
        s.addArrangedSubview(row([label(cu.s("name"), 19, C.text, bold: true), badge(w.s("status_label"), C.status(w.s("status")))]))
        if !cu.s("mobile").isEmpty { s.addArrangedSubview(label(cu.s("mobile"), 14, C.muted)) }
        let t = label(w.s("title"), 16)
        s.addArrangedSubview(t)
        s.setCustomSpacing(8, after: t)
        if !w.s("description").isEmpty { s.addArrangedSubview(label(w.s("description"), 14, C.muted)) }
        s.addArrangedSubview(info("Category", w.s("category")))
        s.addArrangedSubview(info("Priority", w.s("priority")))
        s.addArrangedSubview(info("Staff", w.o("staff").s("name").isEmpty ? "Not assigned" : w.o("staff").s("name")))
        s.addArrangedSubview(info("Branch", w.o("branch").s("name")))
        let by = w.o("created_by").s("name")
        s.addArrangedSubview(info("Added", fmtDate(w.s("created_at")) + (by.isEmpty ? "" : " by " + by)))
        s.addArrangedSubview(info(w.b("overdue") ? "Overdue" : "Due", fmtDate(w.s("due_at"))))
        if let amt = w.d("amount") { s.addArrangedSubview(info("Amount", money(amt))) }
        if !w.s("completed_at").isEmpty { s.addArrangedSubview(info("Completed", fmtDate(w.s("completed_at")))) }
        body.addArrangedSubview(c)

        let mob = cu.s("mobile")
        if !mob.isEmpty {
            let wid = id
            body.addArrangedSubview(row([
                Btn("📞 Call", bg: C.card) { [weak self] in self?.callPhone(mob) },
                Btn("WhatsApp", bg: C.card) { [weak self] in self?.whatsapp(mob) },
                Btn("Payment QR", bg: C.card) { [weak self] in self?.push(QrVC(mobile: mob, work: wid, note: "Work #\(wid)")) },
            ], equal: true))
        }

        let acts = w.strings("actions")
        if acts.contains("done") { body.addArrangedSubview(Btn("✓ Mark done", bg: C.green) { [weak self] in self?.markDone() }) }
        if acts.contains("approve") { body.addArrangedSubview(Btn("Approve", bg: C.violet) { [weak self] in self?.action("approve") }) }
        var r1: [UIView] = []
        if acts.contains("start") { r1.append(Btn("Start", bg: C.blue) { [weak self] in self?.action("start") }) }
        if acts.contains("assign") { r1.append(Btn(w.o("staff").s("name").isEmpty ? "Assign" : "Re-assign", bg: C.brand) { [weak self] in self?.assign() }) }
        if !r1.isEmpty { body.addArrangedSubview(row(r1, equal: true)) }
        var r2: [UIView] = []
        if acts.contains("note") {
            r2.append(Btn("Add note", bg: C.card) { [weak self] in
                self?.prompt("Note", "Write a note") { n in self?.action("note", ["note": n]) }
            })
        }
        if acts.contains("edit") { r2.append(Btn("Edit", bg: C.card) { [weak self] in if let s = self { s.push(AddWorkVC(id: s.id)) } }) }
        if !r2.isEmpty { body.addArrangedSubview(row(r2, equal: true)) }
        var r3: [UIView] = []
        if acts.contains("reopen") { r3.append(Btn("Reopen", bg: C.card) { [weak self] in self?.action("reopen") }) }
        if acts.contains("cancel") {
            r3.append(Btn("Cancel work", bg: C.card) { [weak self] in
                guard let s = self else { return }
                s.confirm("Cancel work", "Cancel work #\(s.id)?") { s.action("cancel") }
            })
        }
        if !r3.isEmpty { body.addArrangedSubview(row(r3, equal: true)) }

        body.addArrangedSubview(label("History", 16, C.text, bold: true))
        let (hc, hs) = card()
        if notes.isEmpty { hs.addArrangedSubview(label("No history yet.", 14, C.muted)) }
        for (i, n) in notes.enumerated() {
            if i > 0 { hs.addArrangedSubview(spacer(4)) }
            hs.addArrangedSubview(label(n.s("note"), 14))
            hs.addArrangedSubview(label(n.s("by") + " · " + fmtDate(n.s("at")), 12, C.muted))
        }
        body.addArrangedSubview(hc)
    }

    func action(_ a: String, _ extra: JSON = [:]) {
        var b = extra
        b["id"] = id
        b["action"] = a
        run("work_action", body: b) { [weak self] r in
            self?.toast(r.message)
            AppDelegate.shared?.refreshWidgets()
            self?.load()
        }
    }

    func markDone() {
        let cu = work.o("customer")
        push(DoneVC(id: id, customer: cu.s("name"), mobile: cu.s("mobile"), title: work.s("title")))
    }

    func assign() {
        run("meta") { [weak self] r in
            guard let s = self else { return }
            let st = r.json.a("staff")
            if st.isEmpty { s.toast("Add staff on the website first."); return }
            s.choose("Assign to", st.map { $0.s("name") + ($0.s("role") == "admin" ? " (admin)" : "") }) { i in
                s.action("assign", ["staff_id": st[i].i("id")])
            }
        }
    }
}

/// "Mark done" with a remark (from the work screen and from ✓ on a widget).
final class DoneVC: BaseVC {
    let id: Int
    var customer: String, mobile: String, workTitle: String
    let who = UILabel()
    var remark: UITextView!
    let wa = UISwitch()
    var waRow: UIView!
    var ok: Btn!

    init(id: Int, customer: String, mobile: String, title: String = "") {
        self.id = id; self.customer = customer; self.mobile = mobile; self.workTitle = title
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        pageTitle = "Mark done"
        pageSub = "Work #\(id)"
        super.viewDidLoad()
        let (c, s) = card()
        s.spacing = 10
        s.addArrangedSubview(label("✓ Mark done  ·  #\(id)", 18, C.green, bold: true))
        who.numberOfLines = 0
        who.font = .systemFont(ofSize: 15)
        who.textColor = C.text
        s.addArrangedSubview(who)
        s.addArrangedSubview(fieldLabel("Remark (what was done)"))
        remark = textArea("e.g. Camera fixed, cable changed")
        s.addArrangedSubview(remark)
        let wl = label("Send WhatsApp message to the customer", 14)
        waRow = row([wa, wl], spacing: 10)
        wa.onTintColor = C.green
        s.addArrangedSubview(waRow)
        ok = Btn("Done", bg: C.green) { [weak self] in self?.save() }
        s.addArrangedSubview(row([Btn("Cancel", bg: C.card) { [weak self] in self?.navigationController?.popViewController(animated: true) }, ok], spacing: 10, equal: true))
        page.addArrangedSubview(c)
        fill()
        if customer.isEmpty {
            // opened from a widget: get the customer name and mobile
            run("work", query: ["id": id], quiet: true) { [weak self] r in
                guard let s = self else { return }
                let w = r.json.o("work")
                s.customer = w.o("customer").s("name"); s.mobile = w.o("customer").s("mobile"); s.workTitle = w.s("title")
                s.fill()
                if !w.strings("actions").contains("done") { s.toast("This work cannot be marked done now (" + w.s("status_label") + ").") }
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        remark.becomeFirstResponder()
    }

    func fill() {
        who.text = customer + (workTitle.isEmpty ? "" : "\n" + workTitle)
        waRow.isHidden = mobile.isEmpty
    }

    func save() {
        let rm = remark.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if rm.isEmpty { toast("Please write a remark"); return }
        ok.isEnabled = false
        run("work_action", body: ["id": id, "action": "done", "remark": rm, "send_wa": wa.isOn ? 1 : 0], fail: { [weak self] _ in self?.ok.isEnabled = true }) { [weak self] r in
            self?.toast(r.message)
            AppDelegate.shared?.refreshWidgets()
            self?.navigationController?.popViewController(animated: true)
        }
    }
}
