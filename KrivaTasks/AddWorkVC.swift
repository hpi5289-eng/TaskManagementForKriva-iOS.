import UIKit
import ContactsUI

/// Add / edit work. Pick the customer from the phone contacts; a mobile already in the customer list
/// fills the saved name by itself, and typing a name suggests customers from the list.
/// (iPhone does not let any app read the call log, so there is no "Call log" button here.)
final class AddWorkVC: BaseVC, CNContactPickerDelegate {
    let editId: Int
    let startMobile: String
    var mobile: Field!, name: Field!, amount: Field!
    var title_: UITextView!, desc: UITextView!
    let known = UILabel()
    let suggest = UIStackView()
    var cat: SelectBox!, prio: SelectBox!, staff: SelectBox?, branch: SelectBox!, dueBox: SelectBox!
    var cats: [String] = []
    var staffList: [(Int, String)] = [(0, "- Not now -")]
    var branches: [(Int, String)] = [(0, "Main branch")]
    var due = Date().addingTimeInterval(86400)
    var save: Btn!
    var lastLookup = ""
    var editWork: JSON?
    var suggestTimer: Timer?
    var lastSuggest = ""

    init(id: Int = 0, mobile: String = "") { editId = id; startMobile = mobile; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        pageTitle = editId > 0 ? "Edit work #\(editId)" : "Add work"
        pageSub = Store.isAdmin ? "" : "Admin will approve works you add"
        super.viewDidLoad()

        let pick = Btn("👤 Contacts", bg: C.card) { [weak self] in self?.pickContact() }
        pick.titleLabel?.font = .boldSystemFont(ofSize: 14)
        pick.contentEdgeInsets = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        pick.constraints.forEach { if $0.firstAttribute == .height { $0.isActive = false } }
        pick.heightAnchor.constraint(equalToConstant: 42).isActive = true
        page.addArrangedSubview(row([pick, UIView()], equal: true))

        let (c, s) = card()
        s.spacing = 6
        s.addArrangedSubview(fieldLabel("Customer mobile"))
        mobile = input("10 digit mobile", .phonePad)
        mobile.addTarget(self, action: #selector(mobileChanged), for: .editingChanged)
        s.addArrangedSubview(mobile)
        known.numberOfLines = 0
        known.font = .boldSystemFont(ofSize: 13)
        known.isHidden = true
        s.addArrangedSubview(known)
        s.addArrangedSubview(fieldLabel("Customer name"))
        name = input("Customer / party name")
        name.autocapitalizationType = .words
        name.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        s.addArrangedSubview(name)
        suggest.axis = .vertical
        suggest.spacing = 4
        suggest.isHidden = true
        s.addArrangedSubview(suggest)
        s.addArrangedSubview(fieldLabel("Work details"))
        title_ = textArea("What is the work?")
        title_.autocapitalizationType = .sentences
        s.addArrangedSubview(title_)
        s.addArrangedSubview(fieldLabel("Category"))
        cat = SelectBox("- Select -") { [weak self] b in
            guard let me = self else { return }
            me.choose("Category", ["- Select -"] + me.cats, from: b) { i in b.value = i == 0 ? "" : me.cats[i - 1]; b.text = i == 0 ? "- Select -" : me.cats[i - 1] }
        }
        s.addArrangedSubview(cat)
        s.addArrangedSubview(fieldLabel("Priority"))
        prio = SelectBox("Normal") { [weak self] b in
            let p = ["Normal", "High", "Urgent"]
            self?.choose("Priority", p, from: b) { i in b.text = p[i]; b.value = p[i].lowercased() }
        }
        prio.value = "normal"
        s.addArrangedSubview(prio)
        s.addArrangedSubview(fieldLabel("Finish by"))
        dueBox = SelectBox("") { [weak self] _ in
            guard let me = self else { return }
            DatePickVC.show(on: me, start: me.due) { d in if let d = d { me.due = d; me.showDue() } }
        }
        s.addArrangedSubview(dueBox)
        showDue()
        if Store.isAdmin {
            s.addArrangedSubview(fieldLabel("Give to staff"))
            let sb = SelectBox("- Not now -") { [weak self] b in
                guard let me = self else { return }
                me.choose("Give to staff", me.staffList.map { $0.1 }, from: b) { i in b.text = me.staffList[i].1; b.value = String(me.staffList[i].0) }
            }
            sb.value = "0"
            staff = sb
            s.addArrangedSubview(sb)
        }
        s.addArrangedSubview(fieldLabel("Branch"))
        branch = SelectBox("Main branch") { [weak self] b in
            guard let me = self else { return }
            me.choose("Branch", me.branches.map { $0.1 }, from: b) { i in b.text = me.branches[i].1; b.value = String(me.branches[i].0) }
        }
        branch.value = "0"
        s.addArrangedSubview(branch)
        s.addArrangedSubview(fieldLabel("Amount (optional)"))
        amount = input("₹", .decimalPad)
        s.addArrangedSubview(amount)
        s.addArrangedSubview(fieldLabel("More details (optional)"))
        desc = textArea("Address, notes…")
        s.addArrangedSubview(desc)
        page.addArrangedSubview(c)
        save = Btn(editId > 0 ? "Save work" : "＋ Add work", bg: C.orange) { [weak self] in self?.doSave() }
        page.addArrangedSubview(save)
        if !startMobile.isEmpty { mobile.text = startMobile; lookup() }
        loadMeta()
    }

    // MARK: contacts (the picker needs no permission; only the chosen number comes back)

    func pickContact() {
        let p = CNContactPickerViewController()
        p.delegate = self
        p.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        p.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        present(p, animated: true)
    }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect prop: CNContactProperty) {
        gotContact(prop.contact, (prop.value as? CNPhoneNumber)?.stringValue ?? "")
    }

    func gotContact(_ c: CNContact, _ phone: String) {
        var parts: [String] = []
        for k in [CNContactGivenNameKey, CNContactFamilyNameKey] where c.isKeyAvailable(k) {
            parts.append(k == CNContactGivenNameKey ? c.givenName : c.familyName)
        }
        if parts.joined().isEmpty && c.isKeyAvailable(CNContactOrganizationNameKey) { parts = [c.organizationName] }
        let n = parts.filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { name.text = n }
        if phone.isEmpty {
            DispatchQueue.main.async { self.toast("No mobile number found. Type it."); self.mobile.becomeFirstResponder() }
        } else {
            mobile.text = tenDigits(phone)
        }
        hideSuggest()
        lookup()
    }

    // MARK: saved customer

    @objc func mobileChanged() { lookup() }

    /// 10 digits typed: ask the website for the saved customer name.
    func lookup() {
        let m = tenDigits(mobile.text ?? "")
        if m.count != 10 { known.isHidden = true; lastLookup = ""; return }
        if m == lastLookup { return }
        lastLookup = m
        run("customer_lookup", query: ["mobile": m], quiet: true) { [weak self] r in
            guard let me = self, m == tenDigits(me.mobile.text ?? "") else { return }
            let last = r.json.o("last_work")
            var t: String
            if r.json.b("found") {
                let n = r.json.o("customer").s("name")
                me.name.text = n
                t = "✓ Saved customer: " + n + (r.json.i("works") > 0 ? "  ·  \(r.json.i("works")) works before" : "")
                me.known.textColor = C.green
            } else if !last.isEmpty && !r.json.s("name").isEmpty {
                if (me.name.text ?? "").trimmingCharacters(in: .whitespaces).isEmpty { me.name.text = r.json.s("name") }
                t = "Worked before as " + r.json.s("name")
                me.known.textColor = C.blue
            } else {
                t = "New customer: type the name"
                me.known.textColor = C.muted
            }
            if !last.isEmpty { t += "\nLast: " + last.s("title") + " (" + last.s("status") + ", " + fmtDate(last.s("created_at")) + ")" }
            me.known.text = t
            me.known.isHidden = false
            me.hideSuggest()
        }
    }

    /// name typed: suggest customers from the customer list (a new name stays on this work only)
    @objc func nameChanged() {
        suggestTimer?.invalidate()
        let q = (name.text ?? "").trimmingCharacters(in: .whitespaces)
        if q.count < 2 { hideSuggest(); return }
        suggestTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in self?.loadSuggest(q) }
    }

    func loadSuggest(_ q: String) {
        lastSuggest = q
        run("customers", query: ["q": q, "limit": 6], quiet: true) { [weak self] r in
            guard let me = self, me.lastSuggest == q, me.name.isFirstResponder else { return }
            me.clear(me.suggest)
            let list = r.json.a("customers").filter { $0.s("name").lowercased() != q.lowercased() || !$0.s("mobile").isEmpty }
            for cu in list.prefix(6) {
                let b = Btn("👤 " + cu.s("name") + (cu.s("mobile").isEmpty ? "" : "  ·  " + cu.s("mobile")), bg: C.card) { [weak self] in
                    self?.name.text = cu.s("name")
                    if !cu.s("mobile").isEmpty { self?.mobile.text = cu.s("mobile"); self?.lookup() }
                    self?.hideSuggest()
                    self?.view.endEditing(true)
                }
                b.contentHorizontalAlignment = .left
                b.titleLabel?.font = .systemFont(ofSize: 14)
                b.titleLabel?.textAlignment = .left
                b.contentEdgeInsets = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
                b.constraints.forEach { if $0.firstAttribute == .height { $0.isActive = false } }
                me.suggest.addArrangedSubview(b)
            }
            me.suggest.isHidden = me.suggest.arrangedSubviews.isEmpty
        }
    }

    func hideSuggest() { suggestTimer?.invalidate(); clear(suggest); suggest.isHidden = true }

    @objc func textFieldDidEndEditing(_ tf: UITextField) {
        if tf === name { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.hideSuggest() } }
    }

    // MARK: lists from the website

    func loadMeta() {
        run("meta") { [weak self] r in
            guard let me = self else { return }
            me.cats = r.json.strings("categories")
            if me.staff != nil {
                me.staffList = [(0, "- Not now -")] + r.json.a("staff").map { ($0.i("id"), $0.s("name")) }
            }
            let br = r.json.a("branches")
            if !br.isEmpty {
                me.branches = br.map { ($0.i("id"), $0.s("name")) }
                me.branch.text = me.branches[0].1
                me.branch.value = String(me.branches[0].0)
            }
            let d = r.json.s("default_due_at")
            if me.editId == 0, d.count >= 16, let x = parseDate(d) { me.due = x; me.showDue() }
            if me.editId > 0 { me.loadWork() }
        }
    }

    func loadWork() {
        run("work", query: ["id": editId]) { [weak self] r in
            guard let me = self else { return }
            let w = r.json.o("work")
            me.editWork = w
            let cu = w.o("customer")
            me.lastLookup = cu.s("mobile")
            me.mobile.text = cu.s("mobile")
            me.name.text = cu.s("name")
            me.title_.text = w.s("title")
            me.desc.text = w.s("description")
            if let a = w.d("amount") { me.amount.text = a == a.rounded() ? String(Int(a)) : String(a) }
            if !w.s("category").isEmpty { me.cat.text = w.s("category"); me.cat.value = w.s("category") }
            let p = w.s("priority").isEmpty ? "normal" : w.s("priority")
            me.prio.value = p
            me.prio.text = p.prefix(1).uppercased() + p.dropFirst()
            if let sb = me.staff, let x = me.staffList.first(where: { $0.0 == w.o("staff").i("id") && $0.0 > 0 }) { sb.text = x.1; sb.value = String(x.0) }
            if let x = me.branches.first(where: { $0.0 == w.o("branch").i("id") }) { me.branch.text = x.1; me.branch.value = String(x.0) }
            if w.s("due_at").count >= 16, let d = parseDate(w.s("due_at")) { me.due = d; me.showDue() }
        }
    }

    func showDue() { dueBox.text = "📅 " + fmtDate(ymdhm(due) + ":00") + "   (change)" }

    func doSave() {
        let m = tenDigits(mobile.text ?? "")
        let nm = (name.text ?? "").trimmingCharacters(in: .whitespaces)
        let tt = title_.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !m.isEmpty && m.count != 10 { toast("Mobile must be 10 digits"); mobile.becomeFirstResponder(); return }
        if nm.isEmpty && m.isEmpty { toast("Type the customer name"); name.becomeFirstResponder(); return }
        if tt.isEmpty { toast("Write the work details"); title_.becomeFirstResponder(); return }
        var o: JSON = ["party_mobile": m, "party_name": nm, "title": tt, "description": desc.text.trimmingCharacters(in: .whitespacesAndNewlines),
                       "work_type": cat.value, "priority": prio.value.isEmpty ? "normal" : prio.value, "due_at": ymdhm(due),
                       "amount": (amount.text ?? "").trimmingCharacters(in: .whitespaces)]
        if editId > 0 { o["id"] = editId }
        if let sb = staff {
            let sid = Int(sb.value) ?? 0
            if sid > 0 { o["assigned_to"] = sid } else { o["assigned_to"] = "" }
        }
        if let b = Int(branch.value), b > 0 { o["branch_id"] = b }
        if let w = editWork { let ca = w.s("created_at"); o["work_at"] = ca.count >= 16 ? String(ca.prefix(16)) : "" }
        save.isEnabled = false
        run("work_save", body: o, fail: { [weak self] _ in self?.save.isEnabled = true }) { [weak self] r in
            guard let me = self else { return }
            me.toast(r.message)
            AppDelegate.shared?.refreshWidgets()
            let newId = r.json.o("work").i("id")
            guard let nav = me.navigationController else { return }
            if me.editId == 0 && newId > 0 {
                var vcs = nav.viewControllers
                vcs.removeLast()
                vcs.append(WorkVC(id: newId))
                nav.setViewControllers(vcs, animated: true)
            } else {
                nav.popViewController(animated: true)
            }
        }
    }
}

/// looks like an input; tap to choose (category, priority, staff, date...)
final class SelectBox: UIControl {
    let lbl = UILabel()
    var value = ""
    var onTap: ((SelectBox) -> Void)?
    var text: String { get { return lbl.text ?? "" } set { lbl.text = newValue } }

    convenience init(_ t: String, _ tap: @escaping (SelectBox) -> Void) {
        self.init(frame: .zero)
        onTap = tap
        backgroundColor = .white
        layer.cornerRadius = 10
        layer.borderWidth = 1
        layer.borderColor = UIColor(hex: 0xD1D5DB).cgColor
        lbl.text = t
        lbl.font = .systemFont(ofSize: 16)
        lbl.textColor = C.text
        let arrow = UILabel()
        arrow.text = "▾"
        arrow.textColor = C.muted
        arrow.setContentHuggingPriority(.required, for: .horizontal)
        let st = UIStackView(arrangedSubviews: [lbl, arrow])
        st.isUserInteractionEnabled = false
        st.spacing = 8
        st.translatesAutoresizingMaskIntoConstraints = false
        addSubview(st)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
            st.topAnchor.constraint(equalTo: topAnchor, constant: 12), st.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            st.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), st.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
        addTarget(self, action: #selector(tapped), for: .touchUpInside)
    }
    @objc func tapped() { superview?.endEditing(true); window?.endEditing(true); onTap?(self) }
}
