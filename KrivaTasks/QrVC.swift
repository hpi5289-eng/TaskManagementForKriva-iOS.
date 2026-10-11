import UIKit
import CoreImage

/// Payment QR with the amount (company UPI accounts from the website). Send by WhatsApp API, share, or open a UPI app.
final class QrVC: BaseVC {
    let startMobile: String, workId: Int, startNote: String
    var amount: Field!, note: Field!, mobile: Field!
    var acc: SelectBox!
    var accIds: [Int] = []
    var accNames: [String] = []
    let img = UIImageView()
    let after = UIStackView()
    var cardImg: UIImage?
    var upiUri = ""
    var info: JSON = [:]
    var apiReady = false

    init(mobile: String = "", work: Int = 0, note: String = "") {
        startMobile = mobile; workId = work; startNote = note
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        pageTitle = "Payment QR"
        pageSub = "Customer scans and pays the exact amount"
        super.viewDidLoad()
        let (c, s) = card()
        s.addArrangedSubview(fieldLabel("Amount (₹)"))
        amount = input("e.g. 500", .decimalPad)
        s.addArrangedSubview(amount)
        s.addArrangedSubview(fieldLabel("For (optional)"))
        note = input("e.g. CCTV service")
        note.autocapitalizationType = .sentences
        note.text = startNote
        s.addArrangedSubview(note)
        s.addArrangedSubview(fieldLabel("Customer WhatsApp number"))
        mobile = input("10 digit mobile", .phonePad)
        mobile.text = startMobile
        s.addArrangedSubview(mobile)
        s.addArrangedSubview(fieldLabel("Pay to (UPI account)"))
        acc = SelectBox("Loading…") { [weak self] b in
            guard let me = self, !me.accIds.isEmpty else { return }
            me.choose("Pay to", me.accNames, from: b) { i in b.text = me.accNames[i]; b.value = String(me.accIds[i]) }
        }
        s.addArrangedSubview(acc)
        s.addArrangedSubview(spacer(4))
        s.addArrangedSubview(Btn("Make QR", bg: C.orange) { [weak self] in self?.make() })
        page.addArrangedSubview(c)
        img.contentMode = .scaleAspectFit
        img.isHidden = true
        img.heightAnchor.constraint(equalTo: img.widthAnchor, multiplier: 1000.0 / 720.0).isActive = true
        img.layer.cornerRadius = 12
        img.clipsToBounds = true
        page.addArrangedSubview(img)
        after.axis = .vertical
        after.spacing = 8
        page.addArrangedSubview(after)
        loadAccounts()
    }

    func loadAccounts() {
        run("payment_info") { [weak self] r in
            guard let me = self else { return }
            me.apiReady = r.json.b("whatsapp_api")
            me.accIds = []; me.accNames = []
            var def = 0
            for (i, x) in r.json.a("accounts").enumerated() {
                me.accNames.append(x.s("name") + " · " + x.s("upi_id"))
                me.accIds.append(x.i("id"))
                if x.b("default") { def = i }
            }
            if me.accIds.isEmpty {
                me.acc.text = "No UPI account yet"
                me.toast(r.json.s("message").isEmpty ? "Add a UPI ID on the website: Settings → Payment accounts." : r.json.s("message"))
            } else {
                me.acc.text = me.accNames[def]
                me.acc.value = String(me.accIds[def])
            }
        }
    }

    func make() {
        let amt = (amount.text ?? "").trimmingCharacters(in: .whitespaces)
        if amt.isEmpty { toast("Enter the amount"); amount.becomeFirstResponder(); return }
        view.endEditing(true)
        let nt = (note.text ?? "").trimmingCharacters(in: .whitespaces)
        run("payment_info", query: ["amount": amt, "note": nt, "upi": Int(acc.value) ?? 0]) { [weak self] r in
            guard let me = self else { return }
            if !r.json.b("ready") { me.toast(r.json.s("message").isEmpty ? "UPI ID not set." : r.json.s("message")); return }
            me.info = r.json
            me.upiUri = r.json.s("upi_uri")
            guard let im = QrVC.drawCard(me.upiUri, r.json.o("upi"), r.json.o("company"), amt, nt) else { me.toast("Could not make QR."); return }
            me.cardImg = im
            me.img.image = im
            me.img.isHidden = false
            me.showButtons(r.json.b("auto_send"))
            DispatchQueue.main.async { me.scroll.scrollRectToVisible(me.img.frame, animated: true) }
        }
    }

    func showButtons(_ auto: Bool) {
        clear(after)
        if apiReady { after.addArrangedSubview(Btn("Send by WhatsApp API", bg: C.green) { [weak self] in self?.sendApi() }) }
        after.addArrangedSubview(row([
            Btn("Share (my WhatsApp)", bg: C.card) { [weak self] in self?.share() },
            Btn("Open UPI app", bg: C.card) { [weak self] in if let u = self?.upiUri { self?.open(u) } },
        ], equal: true))
        if auto && apiReady && tenDigits(mobile.text ?? "").count == 10 { sendApi() }
    }

    func sendApi() {
        let m = tenDigits(mobile.text ?? "")
        if m.count != 10 { toast("Enter the customer's 10 digit WhatsApp number"); mobile.becomeFirstResponder(); return }
        guard let png = cardImg?.pngData() else { return }
        toast("Sending…")
        run("qr_send", body: ["mobile": m, "amount": (amount.text ?? "").trimmingCharacters(in: .whitespaces),
                              "note": (note.text ?? "").trimmingCharacters(in: .whitespaces),
                              "png": "data:image/png;base64," + png.base64EncodedString(), "upi": Int(acc.value) ?? 0, "work": workId]) { [weak self] r in
            self?.toast(r.message)
        }
    }

    func share() {
        guard let im = cardImg, let png = im.pngData() else { return }
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("payment-qr.png")
        try? png.write(to: f, options: .atomic)
        let a = UIActivityViewController(activityItems: [ShareText(msgText()), f], applicationActivities: nil)
        if let p = a.popoverPresentationController { p.sourceView = img; p.sourceRect = img.bounds }
        present(a, animated: true)
    }

    /// WhatsApp text: welcome + amount, no UPI ID or bank details (the QR has everything needed to pay).
    func msgText() -> String {
        let co = info.o("company")
        let amt = (amount.text ?? "").trimmingCharacters(in: .whitespaces), nt = (note.text ?? "").trimmingCharacters(in: .whitespaces)
        return "*Welcome to " + co.s("name") + "* 🙏\n\n"
            + (amt.isEmpty ? "" : "Payment: *Rs " + amt + "*\n")
            + (nt.isEmpty ? "" : "For: " + nt + "\n")
            + "\nPlease scan the QR above and pay with any UPI app (GPay, PhonePe, Paytm).\nThank you! 🙏"
    }

    static func cut(_ s: String, _ n: Int) -> String { return s.count > n ? String(s.prefix(n - 1)) + "…" : s }

    static func qrImage(_ text: String, size: CGFloat) -> UIImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(text.data(using: .utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage else { return nil }
        let scale = size / out.extent.width
        let big = out.samplingNearest().transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = CIContext().createCGImage(big, from: big.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// 720 x 1000 picture: brand header, QR, amount, note, payee name (never the UPI ID)
    static func drawCard(_ uri: String, _ u: JSON, _ co: JSON, _ amt: String, _ nt: String) -> UIImage? {
        guard let qr = qrImage(uri, size: 480) else { return nil }
        let W: CGFloat = 720, H: CGFloat = 1000
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let brand = C.brand
        return UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { ctx in
            UIColor.white.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
            brand.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: W, height: 120))
            func center(_ s: String, _ y: CGFloat, _ font: UIFont, _ color: UIColor) {
                let p = NSMutableParagraphStyle()
                p.alignment = .center
                let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: p]
                let h = (s as NSString).size(withAttributes: a).height
                (s as NSString).draw(in: CGRect(x: 10, y: y - h * 0.8, width: W - 20, height: h + 4), withAttributes: a)
            }
            center(cut(co.s("name"), 34), 58, .boldSystemFont(ofSize: 36), .white)
            center("Scan & pay with any UPI app", 98, .systemFont(ofSize: 22), UIColor(hex: 0xDDDDF0))
            let oy: CGFloat = 140
            let ctxg = ctx.cgContext
            ctxg.interpolationQuality = .none
            qr.draw(in: CGRect(x: (W - 480) / 2, y: oy, width: 480, height: 480))
            center("₹ " + amt, oy + 480 + 70, .boldSystemFont(ofSize: 52), C.text)
            var y = oy + 480 + 115
            if !nt.isEmpty { center(cut(nt, 44), y, .systemFont(ofSize: 26), UIColor(hex: 0x374151)); y += 42 }
            let payee = u.s("upi_name").isEmpty ? co.s("name") : u.s("upi_name")
            if !payee.isEmpty { center(cut("Pay to: " + payee, 44), y, .boldSystemFont(ofSize: 26), brand) }
            center("GPay · PhonePe · Paytm · BHIM · any bank app", H - 24, .systemFont(ofSize: 22), C.muted)
        }
    }
}

/// text that goes with a shared picture (WhatsApp shows it as the caption)
final class ShareText: NSObject, UIActivityItemSource {
    let text: String
    init(_ t: String) { text = t }
    func activityViewControllerPlaceholderItem(_ c: UIActivityViewController) -> Any { return text }
    func activityViewController(_ c: UIActivityViewController, itemForActivityType t: UIActivity.ActivityType?) -> Any? { return text }
}
