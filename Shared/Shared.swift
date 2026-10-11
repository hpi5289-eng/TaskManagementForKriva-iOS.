import Foundation

// Code used by the app and by the home-screen widgets (both read the same App Group storage).

let appGroup = "group.com.kriva.taskmanagement"
typealias JSON = [String: Any]

// MARK: - JSON helpers (the website answers plain JSON objects)

extension Dictionary where Key == String, Value == Any {
    func s(_ k: String) -> String {
        guard let v = self[k], !(v is NSNull) else { return "" }
        if let x = v as? String { return x == "null" ? "" : x }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }
    func i(_ k: String) -> Int {
        if let n = self[k] as? NSNumber { return n.intValue }
        if let x = self[k] as? String { return Int(x) ?? Int(Double(x) ?? 0) }
        return 0
    }
    func d(_ k: String) -> Double? {
        if let n = self[k] as? NSNumber { return n.doubleValue }
        if let x = self[k] as? String { return Double(x) }
        return nil
    }
    func b(_ k: String) -> Bool {
        if let n = self[k] as? NSNumber { return n.boolValue }
        if let x = self[k] as? String { return x == "1" || x == "true" }
        return false
    }
    func o(_ k: String) -> JSON { return self[k] as? JSON ?? [:] }
    func a(_ k: String) -> [JSON] { return self[k] as? [JSON] ?? [] }
    func strings(_ k: String) -> [String] { return (self[k] as? [Any] ?? []).compactMap { $0 as? String } }
    func has(_ k: String) -> Bool { if let v = self[k] { return !(v is NSNull) } else { return false } }
}

func parseJSON(_ data: Data?) -> JSON? {
    guard let data = data, let o = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
    return o as? JSON
}

func jsonString(_ o: Any) -> String {
    guard JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o, options: []) else { return "{}" }
    return String(data: d, encoding: .utf8) ?? "{}"
}

// MARK: - Formatting

/// "2026-10-11 15:30:00" -> "11 Oct, 3:30 PM" (same as the Android app)
func fmtDate(_ dt: String) -> String {
    let c = Array(dt)
    guard c.count >= 10, let m = Int(String(c[5...6])), m >= 1, m <= 12 else { return "" }
    let mon = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    var s = String(c[8...9]) + " " + mon[m - 1]
    if c.count >= 16, let h = Int(String(c[11...12])) {
        s += ", \(h % 12 == 0 ? 12 : h % 12):" + String(c[14...15]) + (h < 12 ? " AM" : " PM")
    }
    return s
}

func money(_ v: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_IN")
    f.minimumFractionDigits = v == v.rounded() ? 0 : 2
    f.maximumFractionDigits = v == v.rounded() ? 0 : 2
    return "₹ " + (f.string(from: NSNumber(value: v)) ?? String(v))
}

func timeShort(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "hh:mm a"
    return f.string(from: d)
}

func dateTimeShort(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "dd MMM, hh:mm a"
    return f.string(from: d)
}

/// +91 98250 12345 / 098250 12345 -> 9825012345
func tenDigits(_ m: String) -> String {
    var d = m.filter { $0.isNumber }
    if d.count == 12 && d.hasPrefix("91") { d = String(d.dropFirst(2)) }
    if d.count == 11 && d.hasPrefix("0") { d = String(d.dropFirst()) }
    if d.count > 10 { d = String(d.suffix(10)) }
    return d
}

// MARK: - Shared storage (login token, user, widget data)

enum Store {
    static let defaultServer = "https://mitalinfosys.info/"
    static var ud: UserDefaults { return UserDefaults(suiteName: appGroup) ?? UserDefaults.standard }

    static func get(_ k: String, _ d: String = "") -> String { return ud.string(forKey: k) ?? d }
    static func put(_ k: String, _ v: String?) { if let v = v { ud.set(v, forKey: k) } else { ud.removeObject(forKey: k) } }
    static func getTime(_ k: String) -> Double { return ud.double(forKey: k) }
    static func putTime(_ k: String, _ v: Double) { ud.set(v, forKey: k) }

    static var server: String {
        var s = get("server", defaultServer).trimmingCharacters(in: .whitespaces)
        if s.isEmpty { s = defaultServer }
        if !s.hasPrefix("http://") && !s.hasPrefix("https://") { s = "https://" + s }
        if !s.hasSuffix("/") { s += "/" }
        return s
    }
    static var token: String { return get("token") }
    /// company | owner | reseller
    static var kind: String { return get("kind") }
    static var loggedIn: Bool { return !token.isEmpty }
    static var isPanel: Bool { return kind == "owner" || kind == "reseller" }
    static var user: JSON { return parseJSON(get("user", "{}").data(using: .utf8)) ?? [:] }
    static var role: String { return user.s("role") }
    static var isAdmin: Bool { return kind == "company" && role == "admin" }
    static var isOwner: Bool { return kind == "owner" }
    /// different person on the same phone = different personal notes
    static var userKey: String {
        let u = user, co = u.o("company")
        let code = co.s("code").isEmpty ? co.s("name") : co.s("code")
        return kind + "_" + code + "_" + String(u.i("id"))
    }

    static func saveLogin(token: String, kind: String, user: JSON) {
        put("token", token); put("kind", kind); put("user", jsonString(user))
        put("widget_json", nil)
    }
    static func logout() {
        for k in ["token", "kind", "user", "widget_json"] { put(k, nil) }
    }

    static var widget: JSON { return parseJSON(get("widget_json", "{}").data(using: .utf8)) ?? [:] }
    static func saveWidget(_ j: JSON) {
        var x = j
        x["fetched"] = Date().timeIntervalSince1970
        put("widget_json", jsonString(x))
    }
}

// MARK: - Small API client (the app has a fuller one; the widget only needs GET)

struct ApiRes {
    var code: Int = 0
    var json: JSON = [:]
    var error: String?
    var ok: Bool { return code >= 200 && code < 300 && (json["ok"] as? Bool ?? true) }
    var message: String {
        if let e = error { return e }
        let m = json.s("error").isEmpty ? json.s("message") : json.s("error")
        return m.isEmpty ? (ok ? "Done" : "Something went wrong (\(code))") : m
    }
}

enum ApiCore {
    static func url(_ route: String, _ query: JSON?) -> URL? {
        var s = Store.server + "kriva_api.php?r=" + route
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        for (k, v) in query ?? [:] {
            let val: String
            if let x = v as? String { val = x } else if let n = v as? NSNumber { val = n.stringValue } else { continue }
            s += "&" + (k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k) + "=" + (val.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }
        return URL(string: s)
    }

    static func request(_ route: String, query: JSON? = nil, body: JSON? = nil, timeout: TimeInterval = 60) -> URLRequest? {
        guard let u = url(route, query) else { return nil }
        var r = URLRequest(url: u, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        r.httpMethod = body == nil ? "GET" : "POST"
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("1", forHTTPHeaderField: "X-Status-In-Body")   // server answers 200 + "status", so IIS error pages never replace the JSON
        let t = Store.token
        if !t.isEmpty {
            r.setValue("Bearer " + t, forHTTPHeaderField: "Authorization")
            r.setValue(t, forHTTPHeaderField: "X-Auth-Token")       // some IIS setups drop the Authorization header
        }
        if let b = body {
            r.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            r.httpBody = jsonString(b).data(using: .utf8)
        }
        return r
    }

    /// Calls the API; `done` runs on a background queue.
    static func call(_ route: String, query: JSON? = nil, body: JSON? = nil, done: @escaping (ApiRes) -> Void) {
        guard let req = request(route, query: query, body: body) else { done(ApiRes(code: 0, json: [:], error: "Wrong server address.")); return }
        URLSession.shared.dataTask(with: req) { data, resp, err in
            var r = ApiRes()
            if let e = err as NSError? {
                r.code = 0
                r.error = e.code == NSURLErrorTimedOut ? "Server is taking too long. Try again."
                    : (e.code == NSURLErrorNotConnectedToInternet || e.code == NSURLErrorCannotFindHost) ? "No internet, or the server address is wrong."
                    : "Could not connect: " + e.localizedDescription
                done(r); return
            }
            r.code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if let j = parseJSON(data) {
                r.json = j
                if j.has("status") { r.code = j.i("status") }
            } else {
                let txt = String(data: data ?? Data(), encoding: .utf8) ?? ""
                var hint = txt.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                if hint.count > 160 { hint = String(hint.prefix(160)) + "…" }
                r.error = (r.code >= 400 ? "Server error \(r.code)" : "Server did not answer properly.") + (hint.isEmpty ? "" : "\n" + hint)
            }
            done(r)
        }.resume()
    }

    /// Widget data for the home-screen widgets (company admin / staff only). `done(true)` when something changed.
    static func fetchWidget(done: @escaping (Bool) -> Void) {
        guard Store.loggedIn, Store.kind == "company" else { done(false); return }
        call("widget", query: ["limit": 50]) { r in
            if r.code == 401 { Store.logout(); done(true); return }
            guard r.ok else { done(false); return }
            Store.saveWidget(r.json)
            done(true)
        }
    }
}

// MARK: - Personal notes (only on this phone, never sent to the website)

struct Note: Codable {
    var id: Int
    var owner: String
    var title: String
    var body: String
    var remindAt: Double   // seconds since 1970, 0 = no reminder
    var done: Bool
    var createdAt: Double
}

enum NotesStore {
    static var fileURL: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
        return base.appendingPathComponent("personal_notes.json")
    }
    static func all() -> [Note] {
        guard let d = try? Data(contentsOf: fileURL), let a = try? JSONDecoder().decode([Note].self, from: d) else { return [] }
        return a
    }
    static func writeAll(_ a: [Note]) {
        if let d = try? JSONEncoder().encode(a) { try? d.write(to: fileURL, options: .atomic) }
    }
    /// this login's notes: open first, then by reminder time, newest first
    static func list(withDone: Bool) -> [Note] {
        let me = Store.userKey
        return all().filter { $0.owner == me && (withDone || !$0.done) }.sorted { a, b in
            if a.done != b.done { return !a.done }
            let ar = a.remindAt > 0, br = b.remindAt > 0
            if ar != br { return ar }
            if ar && a.remindAt != b.remindAt { return a.remindAt < b.remindAt }
            return a.id > b.id
        }
    }
    static func get(_ id: Int) -> Note? { return all().first { $0.id == id && $0.owner == Store.userKey } }
    @discardableResult
    static func save(id: Int, title: String, body: String, remindAt: Double) -> Note {
        var a = all()
        if let i = a.firstIndex(where: { $0.id == id && $0.owner == Store.userKey }) {
            a[i].title = title; a[i].body = body; a[i].remindAt = remindAt
            writeAll(a); return a[i]
        }
        let n = Note(id: (a.map { $0.id }.max() ?? 0) + 1, owner: Store.userKey, title: title, body: body, remindAt: remindAt,
                     done: false, createdAt: Date().timeIntervalSince1970)
        a.append(n)
        writeAll(a)
        return n
    }
    static func setDone(_ id: Int, _ done: Bool) {
        var a = all()
        if let i = a.firstIndex(where: { $0.id == id && $0.owner == Store.userKey }) { a[i].done = done; writeAll(a) }
    }
    static func delete(_ id: Int) {
        writeAll(all().filter { !($0.id == id && $0.owner == Store.userKey) })
    }
}
