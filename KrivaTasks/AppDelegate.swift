import UIKit
import UserNotifications
#if canImport(WidgetKit)
import WidgetKit
#endif

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var shared: AppDelegate?
    var window: UIWindow?
    var nav: UINavigationController? { return window?.rootViewController as? UINavigationController }
    /// kriva:// link that came before the home screen was ready
    var pendingLink: URL?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        AppDelegate.shared = self
        UNUserNotificationCenter.current().delegate = self
        application.setMinimumBackgroundFetchInterval(15 * 60)
        let w = UIWindow(frame: UIScreen.main.bounds)
        if #available(iOS 13.0, *) { w.overrideUserInterfaceStyle = .light }
        window = w
        if Store.loggedIn { showHome() } else { showLogin() }
        w.makeKeyAndVisible()
        if let u = launchOptions?[.url] as? URL { pendingLink = u }
        return true
    }

    func showLogin() {
        reloadWidgets()
        let n = UINavigationController(rootViewController: LoginVC())
        n.setNavigationBarHidden(true, animated: false)
        window?.rootViewController = n
    }

    func showHome() {
        let root: UIViewController = Store.isPanel ? PanelVC() : HomeVC()
        window?.rootViewController = UINavigationController(rootViewController: root)
        Notifier.askPermission()
        refreshWidgets()
        if let u = pendingLink { pendingLink = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { _ = self.handle(u) } }
    }

    // MARK: widgets

    func reloadWidgets() {
        #if canImport(WidgetKit)
        if #available(iOS 14.0, *) { WidgetCenter.shared.reloadAllTimelines() }
        #endif
    }
    /// fetch fresh widget data, then redraw the widgets
    func refreshWidgets() {
        ApiCore.fetchWidget { changed in if changed { DispatchQueue.main.async { self.reloadWidgets() } } }
    }

    func applicationDidEnterBackground(_ application: UIApplication) { reloadWidgets() }

    func application(_ application: UIApplication, performFetchWithCompletionHandler done: @escaping (UIBackgroundFetchResult) -> Void) {
        ApiCore.fetchWidget { changed in
            DispatchQueue.main.async {
                if changed { self.reloadWidgets() }
                done(changed ? .newData : .noData)
            }
        }
    }

    // MARK: kriva:// links from the widgets

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return handle(url)
    }

    /// kriva://work?id=5  kriva://done?id=5  kriva://add  kriva://notes  kriva://note?id=3  kriva://newnote  kriva://works
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "kriva" else { return false }
        guard Store.loggedIn, let nav = nav, !(nav.viewControllers.first is LoginVC) else { pendingLink = url; return true }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let id = Int(q.first { $0.name == "id" }?.value ?? "") ?? 0
        nav.presentedViewController?.dismiss(animated: false)
        nav.popToRootViewController(animated: false)
        var vc: UIViewController?
        switch url.host ?? "" {
        case "work" where id > 0: vc = WorkVC(id: id)
        case "done" where id > 0: vc = DoneVC(id: id, customer: "", mobile: "")
        case "add": vc = Store.isPanel ? nil : AddWorkVC()
        case "works": vc = WorksVC()
        case "notes": vc = NotesVC()
        case "note" where id > 0: vc = NoteEditVC(id: id)
        case "newnote": vc = NoteEditVC(id: 0)
        default: break
        }
        if let v = vc { nav.pushViewController(v, animated: true) }
        return true
    }

    // MARK: note reminders

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent n: UNNotification, withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.alert, .sound])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive r: UNNotificationResponse, withCompletionHandler done: @escaping () -> Void) {
        if let id = r.notification.request.content.userInfo["note"] as? Int, let u = URL(string: "kriva://note?id=\(id)") { handle(u) }
        done()
    }
}

/// local reminders for personal notes
enum Notifier {
    static func askPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
    static func schedule(_ n: Note) {
        let c = UNUserNotificationCenter.current()
        c.removePendingNotificationRequests(withIdentifiers: ["note_\(n.id)"])
        guard n.remindAt > Date().timeIntervalSince1970, !n.done else { return }
        let ct = UNMutableNotificationContent()
        ct.title = "⏰ " + (n.title.isEmpty ? "Reminder" : n.title)
        ct.body = n.body.isEmpty ? "Your note reminder" : n.body
        ct.sound = .default
        ct.userInfo = ["note": n.id]
        let d = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date(timeIntervalSince1970: n.remindAt))
        c.add(UNNotificationRequest(identifier: "note_\(n.id)", content: ct, trigger: UNCalendarNotificationTrigger(dateMatching: d, repeats: false)))
    }
    static func cancel(_ id: Int) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["note_\(id)"])
    }
}
