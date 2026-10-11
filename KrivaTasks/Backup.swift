import UIKit

/// Full SQL database backup of the company, saved on the iPhone in
/// Files app → On My iPhone → Kriva Tasks → Kriva Management Backup.
///  - Company admin only: "Backup" tile / menu any time, and automatically when the app is opened and the
///    last backup on this phone is more than 24 hours old.
///  - The zip is downloaded to a temporary file and checked (complete download, opens as a zip, has the
///    database inside); only a complete backup is moved to the folder. Half files are never kept.
///  - Restore is done on the website (Backup page: upload this zip), never from the app.
///  The owner can take the all-companies backup from the panel menu (manual only).
final class Backup: NSObject, URLSessionDownloadDelegate {
    static let folderName = "Kriva Management Backup"
    static let autoEvery: Double = 24 * 3600
    static let retryAfter: Double = 3600
    static let keep = 10
    static var running = false
    static var current: Backup?

    var progress: ((Int64, Int64) -> Void)?
    var finish: ((String, URL?) -> Void)?
    var fileName = ""
    var expected: Int64 = -1
    var session: URLSession?

    static func key(_ k: String) -> String { return k + "_" + Store.userKey }
    static var allowed: Bool { return Store.isAdmin || Store.isOwner }

    static var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let f = docs.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: f, withIntermediateDirectories: true, attributes: nil)
        return f
    }

    /// home screen opened: company admin, last backup older than 24 hours -> backup now (no question)
    static func maybeAuto(_ vc: BaseVC) {
        guard Store.isAdmin, !running else { return }
        let now = Date().timeIntervalSince1970
        if now - Store.getTime(key("backup_done")) < autoEvery { return }
        if now - Store.getTime(key("backup_try")) < retryAfter { return }
        Store.putTime(key("backup_try"), now)
        vc.toast("Auto backup started (last backup is more than 24 hours old)…")
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask(withName: "backup") { UIApplication.shared.endBackgroundTask(bg) }
        run(progress: nil) { msg, _ in
            vc.toast(msg)
            UIApplication.shared.endBackgroundTask(bg)
        }
    }

    /// Backup tile / menu
    static func start(_ vc: BaseVC) {
        if !allowed { vc.toast("Only the company admin can take a backup."); return }
        if running { vc.toast("A backup is already running."); return }
        let pd = UIAlertController(title: "Backup", message: "Making the full database backup on the server…", preferredStyle: .alert)
        vc.present(pd, animated: true)
        var bg = UIBackgroundTaskIdentifier.invalid
        bg = UIApplication.shared.beginBackgroundTask(withName: "backup") { UIApplication.shared.endBackgroundTask(bg) }
        run(progress: { done, _ in pd.message = "Downloading backup… \(done / 1024) KB" }) { msg, file in
            UIApplication.shared.endBackgroundTask(bg)
            pd.dismiss(animated: true) {
                let a = UIAlertController(title: msg.hasPrefix("Backup saved") ? "Backup saved ✓" : "Backup", message: msg, preferredStyle: .alert)
                if let f = file {
                    a.addAction(UIAlertAction(title: "Share / Save to Files", style: .default) { _ in
                        let s = UIActivityViewController(activityItems: [f], applicationActivities: nil)
                        if let p = s.popoverPresentationController { p.sourceView = vc.view; p.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.midY, width: 1, height: 1) }
                        vc.present(s, animated: true)
                    })
                }
                a.addAction(UIAlertAction(title: "OK", style: .cancel))
                vc.present(a, animated: true)
            }
        }
    }

    /// Download, check, save. `done` runs on the main thread with the message for the user.
    static func run(progress: ((Int64, Int64) -> Void)?, done: @escaping (String, URL?) -> Void) {
        if running { done("A backup is already running.", nil); return }
        guard let req = ApiCore.request(Store.isOwner ? "p_backup" : "backup_download", timeout: 900) else { done("Wrong server address.", nil); return }
        running = true
        let b = Backup()
        current = b
        b.progress = { d, t in DispatchQueue.main.async { progress?(d, t) } }
        b.finish = { m, u in
            DispatchQueue.main.async {
                running = false
                current = nil
                done(m, u)
            }
        }
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 900
        cfg.timeoutIntervalForResource = 3600
        b.session = URLSession(configuration: cfg, delegate: b, delegateQueue: nil)
        b.session?.downloadTask(with: req).resume()
    }

    // MARK: URLSessionDownloadDelegate

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress?(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ s: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fm = FileManager.default
        let resp = downloadTask.response as? HTTPURLResponse
        let size = (try? fm.attributesOfItem(atPath: location.path)[.size] as? NSNumber)?.int64Value ?? 0
        do {
            let ct = (resp?.allHeaderFields["Content-Type"] as? String ?? "").lowercased()
            if ct.contains("json") || size < 100 {
                // the server answered an error instead of the zip
                let j = parseJSON(try? Data(contentsOf: location)) ?? [:]
                let m = j.s("error").isEmpty ? j.s("message") : j.s("error")
                throw BackupError(m.isEmpty ? "the server sent an empty file." : m)
            }
            let total = downloadTask.countOfBytesExpectedToReceive
            if total > 0 && size != total { throw BackupError("download stopped in between (\(size / 1024) of \(total / 1024) KB). Try again.") }
            let inside = try Backup.check(location)
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd_HHmm"
            let stamp = f.string(from: Date())
            var name = Backup.fileName(resp) ?? ""
            if name.range(of: "^[A-Za-z0-9._-]+\\.zip$", options: .regularExpression) == nil { name = "backup_" + stamp + ".zip" }
            let dest = Backup.folder.appendingPathComponent(name)
            try? fm.removeItem(at: dest)
            try fm.moveItem(at: location, to: dest)
            Backup.saveNotes(stamp)
            Backup.prune()
            Store.putTime(Backup.key("backup_done"), Date().timeIntervalSince1970)
            finish?("Backup saved ✓ (\(size / 1024) KB, \(inside))\nFiles app → On My iPhone → Kriva Tasks → \(Backup.folderName)/\(name)\n\nTo restore: website → Backup → upload this file.", dest)
        } catch {
            finish?("Backup failed: " + ((error as? BackupError)?.msg ?? error.localizedDescription), nil)
        }
        finish = nil
        s.finishTasksAndInvalidate()
    }

    func urlSession(_ s: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let e = error as NSError? {
            finish?("Backup failed: " + (e.code == NSURLErrorTimedOut ? "the server took too long. Try again." : e.localizedDescription), nil)
            finish = nil
        }
        s.finishTasksAndInvalidate()
    }

    static func fileName(_ r: HTTPURLResponse?) -> String? {
        guard let cd = r?.allHeaderFields["Content-Disposition"] as? String,
              let m = cd.range(of: "filename=\"?([^\";]+)\"?", options: .regularExpression) else { return nil }
        return String(cd[m]).replacingOccurrences(of: "filename=", with: "").replacingOccurrences(of: "\"", with: "")
    }

    /// The zip must open and hold a database file; otherwise it is not a complete backup.
    static func check(_ url: URL) throws -> String {
        guard let d = try? Data(contentsOf: url, options: .mappedIfSafe), d.count >= 22 else { throw BackupError("the server sent an empty file.") }
        let names = try zipNames(d)
        let db = names.filter { n in [".bak", ".db", ".trn", ".mdf"].contains { n.lowercased().hasSuffix($0) } }
        if db.isEmpty { throw BackupError("no database file inside the zip.") }
        return "\(names.count) files, database: " + db[0]
    }

    /// file names from the zip's central directory (a cut-off download has no central directory)
    static func zipNames(_ d: Data) throws -> [String] {
        let bad = BackupError("the file is not complete (not a valid zip). Try again.")
        let n = d.count
        func u16(_ o: Int) -> Int { return Int(d[d.startIndex + o]) | Int(d[d.startIndex + o + 1]) << 8 }
        func u32(_ o: Int) -> Int { return u16(o) | u16(o + 2) << 16 }
        var eocd = -1
        var i = n - 22
        let stop = max(0, n - 22 - 65535)
        while i >= stop {
            if u32(i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        if eocd < 0 { throw bad }
        var count = u16(eocd + 10)
        var off = u32(eocd + 16)
        if (count == 0xFFFF || off == 0xFFFFFFFF) && eocd >= 20 && u32(eocd - 20) == 0x07064b50 {
            // zip64 (very big backup)
            let z = u32(eocd - 20 + 8)
            if z + 56 <= n && u32(z) == 0x06064b50 { count = u32(z + 32); off = u32(z + 48) }
        }
        var out: [String] = []
        var p = off
        for _ in 0..<count {
            if p + 46 > n || u32(p) != 0x02014b50 { throw bad }
            let nl = u16(p + 28), xl = u16(p + 30), cl = u16(p + 32)
            if p + 46 + nl > n { throw bad }
            out.append(String(data: d.subdata(in: (d.startIndex + p + 46)..<(d.startIndex + p + 46 + nl)), encoding: .utf8) ?? "?")
            p += 46 + nl + xl + cl
        }
        return out
    }

    /// personal notes of this login as a small JSON file next to the backup
    static func saveNotes(_ stamp: String) {
        let a = NotesStore.list(withDone: true)
        if a.isEmpty { return }
        let e = JSONEncoder()
        if #available(iOS 11.0, *) { e.outputFormatting = .prettyPrinted }
        if let d = try? e.encode(a) { try? d.write(to: folder.appendingPathComponent("my_notes_" + stamp + ".json"), options: .atomic) }
    }

    /// keep the newest backups so the phone does not fill up
    static func prune() {
        let fm = FileManager.default
        guard let fs = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else { return }
        let zips = fs.filter { $0.pathExtension.lowercased() == "zip" }.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
        for z in zips.dropFirst(keep) { try? fm.removeItem(at: z) }
    }
}

struct BackupError: Error {
    let msg: String
    init(_ m: String) { msg = m }
}
