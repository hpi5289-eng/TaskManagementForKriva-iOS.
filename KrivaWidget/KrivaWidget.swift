import WidgetKit
import SwiftUI

// The 4 home screen widgets (iOS 14+): 1 customers + ✓, 2 category wise, 3 work details, 4 personal notes.
// Tapping a row opens it in the app; ✓ opens the "Mark done" screen (iOS widgets cannot take typing).

enum WKind: Int { case customers = 1, category, details, notes }

struct WEntry: TimelineEntry {
    let date: Date
    let data: JSON
    let notes: [Note]
}

struct WProvider: TimelineProvider {
    let kind: WKind

    func placeholder(in context: Context) -> WEntry { return WEntry(date: Date(), data: [:], notes: []) }

    func current() -> WEntry {
        return WEntry(date: Date(), data: Store.widget, notes: Store.loggedIn ? NotesStore.list(withDone: false) : [])
    }

    func getSnapshot(in context: Context, completion: @escaping (WEntry) -> Void) { completion(current()) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WEntry>) -> Void) {
        let next = Date().addingTimeInterval(15 * 60)
        let age = Date().timeIntervalSince1970 - (Store.widget.d("fetched") ?? 0)
        if kind == .notes || age < 5 * 60 || !Store.loggedIn || Store.kind != "company" {
            completion(Timeline(entries: [current()], policy: .after(next)))
            return
        }
        ApiCore.fetchWidget { _ in completion(Timeline(entries: [self.current()], policy: .after(next))) }
    }
}

// MARK: - look

let wNavy = Color(red: 16 / 255, green: 33 / 255, blue: 79 / 255)
let wOrange = Color(red: 240 / 255, green: 92 / 255, blue: 41 / 255)
let wMuted = Color(red: 107 / 255, green: 114 / 255, blue: 128 / 255)
let wText = Color(red: 17 / 255, green: 24 / 255, blue: 39 / 255)
let wRed = Color(red: 220 / 255, green: 38 / 255, blue: 38 / 255)
let wGreen = Color(red: 22 / 255, green: 163 / 255, blue: 74 / 255)
let wLine = Color(red: 229 / 255, green: 231 / 255, blue: 235 / 255)

func link(_ s: String) -> URL { return URL(string: s) ?? URL(string: "kriva://app")! }

struct WorkWidgetView: View {
    let entry: WEntry
    let kind: WKind
    @Environment(\.widgetFamily) var family

    var admin: Bool { return Store.isAdmin }
    /// iOS 17+ puts a margin around the widget content
    var newLook: Bool { if #available(iOSApplicationExtension 17.0, *) { return true } else { return false } }
    var company: Bool { return Store.loggedIn && Store.kind == "company" }
    var maxRows: Int { return family == .systemLarge ? 8 : 3 }

    var title: String {
        if kind == .notes { return "My notes 🔒" }
        let names = ["", "Customers", "Category wise", "Work details"]
        return (admin ? "All works · " : "My works · ") + names[kind.rawValue]
    }

    var sub: String {
        if !Store.loggedIn { return "Login in the app" }
        if kind == .notes { return "Only on this phone" }
        if !company { return "For company admin and staff" }
        let d = entry.data
        let f = d.d("fetched") ?? 0
        return "\(d.i("pending")) pending" + (d.i("overdue") > 0 ? " · \(d.i("overdue")) overdue" : "")
            + (admin && d.i("approval") > 0 ? " · \(d.i("approval")) to approve" : "")
            + "  ·  " + (f > 0 ? timeShort(Date(timeIntervalSince1970: f)) : "not updated")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image("KrivaLogo").resizable().scaledToFit().frame(width: 22, height: 22).background(Color.white).clipShape(Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 13, weight: .bold)).foregroundColor(.white).lineLimit(1)
                    Text(sub).font(.system(size: 10)).foregroundColor(Color.white.opacity(0.85)).lineLimit(1)
                }
                Spacer(minLength: 2)
                Link(destination: link(kind == .notes ? "kriva://newnote" : "kriva://add")) {
                    Text("＋").font(.system(size: 18, weight: .bold)).foregroundColor(.white).frame(width: 30, height: 30)
                        .background(wOrange).clipShape(Circle())
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(wNavy)
            .cornerRadius(newLook ? 12 : 0)
            content.padding(.horizontal, 10)
            Spacer(minLength: 0)
        }
        .widgetBackground()
        .widgetURL(link(kind == .notes ? "kriva://notes" : "kriva://works"))
    }

    @ViewBuilder var content: some View {
        if !Store.loggedIn {
            emptyText("Open the app and login")
        } else if kind == .notes {
            if entry.notes.isEmpty { emptyText("No notes. Tap ＋ to add.") }
            else { ForEach(Array(entry.notes.prefix(maxRows).enumerated()), id: \.offset) { _, n in noteRow(n) } }
        } else if !company {
            emptyText("Open the app")
        } else {
            let ws = entry.data.a("works")
            if ws.isEmpty { emptyText("Nothing pending ✓") }
            else if kind == .category { categoryRows(ws) }
            else { ForEach(Array(ws.prefix(maxRows).enumerated()), id: \.offset) { _, w in workRow(w) } }
        }
    }

    func emptyText(_ t: String) -> some View {
        Text(t).font(.system(size: 13)).foregroundColor(wMuted).frame(maxWidth: .infinity).padding(.top, 14)
    }

    func dueText(_ w: JSON) -> Text {
        let od = w.b("overdue"), due = w.s("due_at")
        let t: String
        if kind == .details { t = due.isEmpty ? "" : (od ? "⚠ " : "") + fmtDate(due) }
        else { t = od ? "⚠ Overdue " + fmtDate(due) : (due.isEmpty ? "" : "Due " + fmtDate(due)) }
        return Text(t).font(.system(size: 10, weight: od ? .bold : .regular)).foregroundColor(od ? wRed : wMuted)
    }

    func workRow(_ w: JSON) -> some View {
        let cust = w.s("customer"), mob = w.s("mobile"), title = w.s("title"), cat = w.s("category")
        let canDone = admin || w.b("mine")
        return HStack(alignment: .center, spacing: 6) {
            Link(destination: link("kriva://work?id=\(w.i("id"))")) {
                VStack(alignment: .leading, spacing: 1) {
                    if kind == .details {
                        HStack(spacing: 6) {
                            Text(cust).font(.system(size: 13, weight: .bold)).foregroundColor(wText).lineLimit(1)
                            Spacer(minLength: 2)
                            dueText(w)
                        }
                        Text(title).font(.system(size: 12)).foregroundColor(wText).lineLimit(1)
                        Text(detailMeta(w, cat)).font(.system(size: 10)).foregroundColor(wMuted).lineLimit(1)
                    } else {
                        Text(kind == .category ? cust + (mob.isEmpty ? "" : "  " + mob) : cust).font(.system(size: 13, weight: .bold)).foregroundColor(wText).lineLimit(1)
                        Text(kind == .category || mob.isEmpty ? title : mob + "  ·  " + title).font(.system(size: 11)).foregroundColor(wMuted).lineLimit(1)
                        dueText(w)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if canDone {
                Link(destination: link("kriva://done?id=\(w.i("id"))")) {
                    Text("✓").font(.system(size: 14, weight: .bold)).foregroundColor(.white).frame(width: 28, height: 28).background(wGreen).clipShape(Circle())
                }
            }
        }
        .padding(.vertical, 3)
        .overlay(Rectangle().frame(height: 1).foregroundColor(wLine), alignment: .bottom)
    }

    func detailMeta(_ w: JSON, _ cat: String) -> String {
        var parts: [String] = []
        if !cat.isEmpty { parts.append(cat) }
        if admin { parts.append(w.s("staff").isEmpty ? "Not assigned" : w.s("staff")) }
        parts.append(w.s("status_label"))
        return parts.joined(separator: " · ")
    }

    func categoryRows(_ ws: [JSON]) -> some View {
        var order: [String] = []
        var groups: [String: [JSON]] = [:]
        for w in ws {
            let k = w.s("category").isEmpty ? "Other" : w.s("category")
            if groups[k] == nil { order.append(k); groups[k] = [] }
            groups[k]?.append(w)
        }
        // headers + rows, cut to what fits
        var rows: [(String?, JSON?)] = []
        for k in order {
            rows.append(("\(k)  (\(groups[k]?.count ?? 0))", nil))
            for w in groups[k] ?? [] { rows.append((nil, w)) }
        }
        let limit = family == .systemLarge ? 11 : 4
        return ForEach(Array(rows.prefix(limit).enumerated()), id: \.offset) { _, r in
            Group {
                if let h = r.0 {
                    Text(h).font(.system(size: 11, weight: .bold)).foregroundColor(wOrange).padding(.top, 2)
                } else if let w = r.1 {
                    workRow(w)
                }
            }
        }
    }

    func noteRow(_ n: Note) -> some View {
        let rem = n.remindAt > 0 ? "⏰ " + dateTimeShort(Date(timeIntervalSince1970: n.remindAt)) : ""
        let line2 = rem.isEmpty ? n.body : (n.body.isEmpty ? rem : rem + "  ·  " + n.body)
        return Link(destination: link("kriva://note?id=\(n.id)")) {
            VStack(alignment: .leading, spacing: 1) {
                Text(n.title).font(.system(size: 13, weight: .bold)).foregroundColor(wText).lineLimit(1)
                if !line2.isEmpty { Text(line2).font(.system(size: 11)).foregroundColor(wMuted).lineLimit(1) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .overlay(Rectangle().frame(height: 1).foregroundColor(wLine), alignment: .bottom)
        }
    }
}

extension View {
    @ViewBuilder func widgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(Color.white, for: .widget)
        } else {
            self.background(Color.white)
        }
    }
}

// MARK: - the 4 widgets

struct CustomersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KrivaCustomers", provider: WProvider(kind: .customers)) { e in WorkWidgetView(entry: e, kind: .customers) }
            .configurationDisplayName("Customers")
            .description("Customer name + mobile, ✓ to mark done.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CategoryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KrivaCategory", provider: WProvider(kind: .category)) { e in WorkWidgetView(entry: e, kind: .category) }
            .configurationDisplayName("Category wise")
            .description("Pending works grouped by category.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct DetailsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KrivaDetails", provider: WProvider(kind: .details)) { e in WorkWidgetView(entry: e, kind: .details) }
            .configurationDisplayName("Work details")
            .description("Customer, work, category and due date.")
            .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct NotesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KrivaNotes", provider: WProvider(kind: .notes)) { e in WorkWidgetView(entry: e, kind: .notes) }
            .configurationDisplayName("My notes")
            .description("Your personal notes, only on this phone.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct KrivaWidgets: WidgetBundle {
    var body: some Widget {
        CustomersWidget()
        CategoryWidget()
        DetailsWidget()
        NotesWidget()
    }
}
