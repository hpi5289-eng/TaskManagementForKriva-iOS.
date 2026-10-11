import UIKit

/// Personal notes: only on this phone, never on the website, admin cannot see them.
final class NotesVC: BaseVC {
    let list = UIStackView()

    override func viewDidLoad() {
        pageTitle = "My personal notes 🔒"
        pageSub = "Saved only on this phone. Admin cannot see them."
        super.viewDidLoad()
        headButton("＋ Add", #selector(add))
        list.axis = .vertical
        list.spacing = 10
        page.addArrangedSubview(list)
    }

    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); show() }

    @objc func add() { push(NoteEditVC(id: 0)) }

    func show() {
        clear(list)
        let a = NotesStore.list(withDone: true)
        if a.isEmpty {
            list.addArrangedSubview(empty("No notes yet.\nTap ＋ Add for a personal note or reminder.\nYou can also add the \"My notes\" widget on the home screen."))
            return
        }
        for n in a { list.addArrangedSubview(noteRow(n)) }
    }

    func noteRow(_ n: Note) -> UIView {
        let (c, s) = card { [weak self] in self?.push(NoteEditVC(id: n.id)) }
        let check = Btn(n.done ? "☑︎" : "☐", bg: C.card) { [weak self] in
            NotesStore.setDone(n.id, !n.done)
            if let x = NotesStore.get(n.id) { if x.done { Notifier.cancel(x.id) } else { Notifier.schedule(x) } }
            AppDelegate.shared?.reloadWidgets()
            self?.show()
        }
        check.layer.borderWidth = 0
        check.backgroundColor = .clear
        check.titleLabel?.font = .systemFont(ofSize: 26)
        check.setTitleColor(n.done ? C.green : C.muted, for: .normal)
        check.contentEdgeInsets = .zero
        check.constraints.forEach { if $0.firstAttribute == .height { $0.isActive = false } }
        check.widthAnchor.constraint(equalToConstant: 40).isActive = true
        check.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let tx = UIStackView()
        tx.axis = .vertical
        tx.spacing = 3
        let t = label(n.title, 16, n.done ? C.muted : C.text, bold: true)
        if n.done {
            t.attributedText = NSAttributedString(string: n.title, attributes: [.strikethroughStyle: NSUnderlineStyle.single.rawValue])
        }
        tx.addArrangedSubview(t)
        if !n.body.isEmpty { tx.addArrangedSubview(label(n.body, 14, C.muted)) }
        if n.remindAt > 0 {
            let past = n.remindAt < Date().timeIntervalSince1970
            tx.addArrangedSubview(label("⏰ " + dateTimeShort(Date(timeIntervalSince1970: n.remindAt)), 12, past ? C.muted : C.orange, bold: true))
        }
        let r = row([check, tx], spacing: 8)
        r.alignment = .top
        s.addArrangedSubview(r)
        return c
    }
}

/// Add / edit one personal note (also opens from the "My notes" widget).
final class NoteEditVC: BaseVC {
    let id: Int
    var remindAt: Double = 0
    var titleF: Field!
    var bodyT: UITextView!
    var remindBox: SelectBox!

    init(id: Int) { self.id = id; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        pageTitle = id > 0 ? "My note" : "New personal note"
        pageSub = "Only on this phone"
        super.viewDidLoad()
        let n = id > 0 ? NotesStore.get(id) : nil
        let (c, s) = card()
        s.spacing = 10
        s.addArrangedSubview(label(id > 0 ? "My note" : "New personal note", 18, C.brand, bold: true))
        s.addArrangedSubview(label("Only on this phone. Not on the website, admin cannot see it.", 12, C.muted))
        titleF = input("Title")
        titleF.autocapitalizationType = .sentences
        bodyT = textArea("Details (optional)")
        bodyT.heightAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
        s.addArrangedSubview(titleF)
        s.addArrangedSubview(bodyT)
        remindBox = SelectBox("") { [weak self] _ in self?.pickRemind() }
        s.addArrangedSubview(remindBox)
        if let n = n {
            titleF.text = n.title
            bodyT.text = n.body
            remindAt = n.remindAt
        }
        showRemind()
        let left: Btn
        if id > 0 {
            left = Btn("Delete", bg: C.card) { [weak self] in
                guard let me = self else { return }
                me.confirm("Delete", "Delete this note?") {
                    NotesStore.delete(me.id)
                    Notifier.cancel(me.id)
                    AppDelegate.shared?.reloadWidgets()
                    me.navigationController?.popViewController(animated: true)
                }
            }
        } else {
            left = Btn("Cancel", bg: C.card) { [weak self] in self?.navigationController?.popViewController(animated: true) }
        }
        let ok = Btn("Save", bg: C.orange) { [weak self] in self?.save() }
        s.addArrangedSubview(row([left, ok], spacing: 10, equal: true))
        page.addArrangedSubview(c)
        if id > 0 && n == nil { toast("This note is not on this phone any more.") }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if id == 0 { titleF.becomeFirstResponder() }
    }

    func showRemind() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd MMM yyyy, hh:mm a"
        remindBox.text = remindAt > 0 ? "⏰ Remind me: " + f.string(from: Date(timeIntervalSince1970: remindAt)) + "  (tap to change)" : "⏰ Add a reminder (optional)"
    }

    func pickRemind() {
        let start = remindAt > 0 ? Date(timeIntervalSince1970: remindAt) : Date().addingTimeInterval(3600)
        DatePickVC.show(on: self, start: start, allowClear: remindAt > 0) { [weak self] d in
            guard let me = self else { return }
            if let d = d {
                me.remindAt = (d.timeIntervalSince1970 / 60).rounded(.down) * 60
                Notifier.askPermission()
            } else {
                me.remindAt = 0
            }
            me.showRemind()
        }
    }

    func save() {
        let t = (titleF.text ?? "").trimmingCharacters(in: .whitespaces)
        if t.isEmpty { toast("Write a title"); titleF.becomeFirstResponder(); return }
        let n = NotesStore.save(id: id, title: t, body: bodyT.text.trimmingCharacters(in: .whitespacesAndNewlines), remindAt: remindAt)
        Notifier.schedule(n)
        AppDelegate.shared?.reloadWidgets()
        toast("Saved on this phone.")
        navigationController?.popViewController(animated: true)
    }
}
