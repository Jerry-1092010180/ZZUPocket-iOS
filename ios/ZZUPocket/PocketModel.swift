import Foundation
import Combine
import CryptoKit

struct Lesson: Identifiable {
    let id: String
    let name: String
    let week: Int
    let weekday: Int
    let start: Int
    let end: Int
    let date: String?
    let time: String
    let room: String
    let teacher: String
}

struct Semester: Identifiable {
    let id: Int
    let name: String
    let startDate: String?
    let weeks: [Int]
}

struct CardTrade: Identifiable {
    let id: String
    let date: String
    let merchant: String
    let summary: String
    let amount: Double
}

struct RoomNode: Identifiable {
    let id: String
    let name: String
}

enum MeterKind: String, CaseIterable, Identifiable {
    case lighting, airConditioning
    var id: String { rawValue }
    var title: String { self == .lighting ? "照明用电" : "空调用电" }
}

struct MeterReading: Codable {
    var roomID: String
    var quantity: Double?
    var updatedAt: Date?
    var error: String?
}

@MainActor
final class PocketModel: ObservableObject {
    @Published var token: String? = TokenStore.load()
    @Published var semesters: [Semester] = []
    @Published var selectedSemester: Int?
    @Published var lessons: [Lesson] = []
    @Published var week = 1
    @Published var balance: Double?
    @Published var meters: [MeterKind: MeterReading] = [
        .lighting: MeterReading(roomID: UserDefaults.standard.string(forKey: "lightingRoomID") ?? ""),
        .airConditioning: MeterReading(roomID: UserDefaults.standard.string(forKey: "airConditioningRoomID") ?? "")
    ]
    @Published var meterHistory: [MeterKind: [EnergySample]] = [:]
    @Published var activeMeter: MeterKind = .lighting
    @Published var balanceUpdatedAt: Date?
    @Published var balanceError: String?
    @Published var campusRefreshing = false
    @Published var trades: [CardTrade] = []
    @Published var roomNodes: [RoomNode] = []
    @Published var roomLevel = "area"
    @Published var roomNextLevel: String?
    @Published var roomIsLastLevel = false
    @Published var roomScope: [String: String] = [:]
    // The old single room ID is not assigned to either meter without confirmation.
    var legacyRoomID: String { UserDefaults.standard.string(forKey: "roomId") ?? "" }
    @Published var busy = false
    @Published var error: String?

    private struct CampusCache: Codable {
        let session: String
        let balance: Double?
        let balanceUpdatedAt: Date?
        let lighting: MeterReading?
        let airConditioning: MeterReading?
    }

    private var sessionFingerprint: String {
        SHA256.hash(data: Data((token ?? "").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    init() {
        defer { reloadHistory() }
        guard token != nil,
              let data = UserDefaults.standard.data(forKey: "campusCacheV1"),
              let cache = try? JSONDecoder().decode(CampusCache.self, from: data),
              cache.session == sessionFingerprint else { return }
        balance = cache.balance
        balanceUpdatedAt = cache.balanceUpdatedAt
        for (kind, reading) in [(MeterKind.lighting, cache.lighting), (.airConditioning, cache.airConditioning)] {
            if let reading, reading.roomID == meters[kind]?.roomID { meters[kind] = reading }
        }
    }

    private func historyKey(for kind: MeterKind) -> String? {
        guard token != nil, let room = meters[kind]?.roomID.trimmingCharacters(in: .whitespacesAndNewlines), !room.isEmpty else { return nil }
        let owner = UserDefaults.standard.string(forKey: "campusHistoryAccount") ?? sessionFingerprint
        let scope = "\(owner)|\(kind.rawValue)|\(room)"
        let hash = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        return "electricityHistoryV1-" + hash
    }

    private func reloadHistory() {
        for kind in MeterKind.allCases { loadHistory(for: kind) }
    }

    private func loadHistory(for kind: MeterKind) {
        guard let key = historyKey(for: kind),
              let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONDecoder().decode([EnergySample].self, from: data) else {
            meterHistory[kind] = []
            return
        }
        let now = Date()
        meterHistory[kind] = saved.filter { $0.quantity.isFinite && $0.date <= now && $0.date >= now.addingTimeInterval(-EnergyHistory.retention) }.sorted { $0.date < $1.date }
    }

    private func recordHistory(_ quantity: Double, at date: Date, for kind: MeterKind) {
        guard let key = historyKey(for: kind) else { return }
        let samples = EnergyHistory.recording(EnergySample(date: date, quantity: quantity), in: meterHistory[kind] ?? [], now: date)
        meterHistory[kind] = samples
        if let data = try? JSONEncoder().encode(samples) { UserDefaults.standard.set(data, forKey: key) }
    }

    func completeSignIn(account: String, token: String) {
        TokenStore.save(token)
        UserDefaults.standard.set(account.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "campusHistoryAccount")
        self.token = token
        balance = nil
        balanceUpdatedAt = nil
        balanceError = nil
        for kind in MeterKind.allCases {
            meters[kind]?.quantity = nil
            meters[kind]?.updatedAt = nil
            meters[kind]?.error = nil
        }
        reloadHistory()
    }

    private func saveCampusCache() {
        guard loggedIn else { return }
        let cache = CampusCache(session: sessionFingerprint, balance: balance, balanceUpdatedAt: balanceUpdatedAt,
                                lighting: meters[.lighting], airConditioning: meters[.airConditioning])
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: "campusCacheV1")
        }
    }

    var loggedIn: Bool { validToken != nil }

    private var validToken: String? {
        guard let token, let payload = token.split(separator: ".").dropFirst().first,
              let data = Data(base64Encoded: String(payload).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4 - payload.count % 4) % 4)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let expiry = json["exp"] as? TimeInterval, expiry > Date().timeIntervalSince1970 + 900 else { return nil }
        return token
    }

    func signOut() {
        meterHistory = [:]
        UserDefaults.standard.removeObject(forKey: "campusHistoryAccount")
        UserDefaults.standard.removeObject(forKey: "campusCacheV1")
        TokenStore.save(nil)
        token = nil
        semesters = []
        lessons = []
        balance = nil
        balanceUpdatedAt = nil
        balanceError = nil
        for kind in MeterKind.allCases {
            meters[kind]?.quantity = nil
            meters[kind]?.updatedAt = nil
            meters[kind]?.error = nil
        }
        trades = []
    }

    func setRoom(_ id: String, for kind: MeterKind) {
        guard meters[kind]?.roomID != id else { return }
        meters[kind] = MeterReading(roomID: id)
        UserDefaults.standard.set(id, forKey: kind == .lighting ? "lightingRoomID" : "airConditioningRoomID")
        loadHistory(for: kind)
        saveCampusCache()
    }

    func refreshCampus() async {
        guard loggedIn, !campusRefreshing else { return }
        campusRefreshing = true
        defer { campusRefreshing = false; saveCampusCache() }
        let sessionToken = token
        do {
            try await refreshBalance()
            if token == sessionToken { balanceError = nil }
        } catch {
            if token == sessionToken { balanceError = error.localizedDescription }
        }
        for kind in MeterKind.allCases {
            guard !Task.isCancelled, token == sessionToken, loggedIn else { break }
            let room = (meters[kind]?.roomID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !room.isEmpty else { continue }
            do {
                let quantity = try await electricityQuantity(roomID: room)
                guard token == sessionToken, meters[kind]?.roomID.trimmingCharacters(in: .whitespacesAndNewlines) == room else { continue }
                let sampledAt = Date()
                meters[kind]?.quantity = quantity
                meters[kind]?.updatedAt = sampledAt
                recordHistory(quantity, at: sampledAt, for: kind)
                meters[kind]?.error = nil
            } catch {
                if token == sessionToken, meters[kind]?.roomID.trimmingCharacters(in: .whitespacesAndNewlines) == room {
                    meters[kind]?.error = error.localizedDescription
                }
            }
        }
    }

    func perform(_ work: @escaping () async throws -> Void) async {
        busy = true
        error = nil
        defer { busy = false }
        do { try await work() } catch { self.error = error.localizedDescription }
    }

    func refreshSchedule() async throws {
        guard let token = validToken else { throw PocketError.message("登录已过期，请重新登录") }
        let result = try await API.eas("/eams-door/api/v1/calendar/get-all-semesters", token: token, step: "读取学期列表")
        guard let semestersData = result["data"] as? [[String: Any]] else { throw PocketError.message(result["msg"] as? String ?? "学期列表格式有误") }
        semesters = semestersData.compactMap { value in
            guard let id = value["id"] as? Int else { return nil }
            return Semester(id: id, name: value["nameZh"] as? String ?? "学期 \(id)", startDate: value["startDate"] as? String, weeks: value["weekIndices"] as? [Int] ?? [])
        }
        if selectedSemester == nil || !semesters.contains(where: { $0.id == selectedSemester }) {
            let current = try await API.eas("/eams-micro-server/api/v1/semester/current-semester", token: token, step: "读取当前学期")
            let currentID = (current["data"] as? [String: Any])?["id"] as? Int
            selectedSemester = semesters.first(where: { $0.id == currentID })?.id ?? semesters.first?.id
        }
        try await loadSemester()
    }

    func loadSemester() async throws {
        guard let token = validToken, let selectedSemester else { throw PocketError.message("请选择学期") }
        let result = try await API.eas("/eams-micro-server/api/v1/lesson/student/course-table/\(selectedSemester)", token: token, step: "读取课表")
        guard let courses = result["data"] as? [[String: Any]] else { throw PocketError.message(result["msg"] as? String ?? "课表格式有误") }
        lessons = courses.flatMap { entry -> [Lesson] in
            let course = entry["course"] as? [String: Any] ?? [:]
            let schedules = entry["schedules"] as? [[String: Any]] ?? []
            return schedules.enumerated().compactMap { index, slot in
                let week = slot["weekIndex"] as? Int ?? 0
                let weekday = slot["weekday"] as? Int ?? 0
                let date = (slot["date"] as? String).map { String($0.prefix(10)) }
                guard (week > 0 && (1...7).contains(weekday)) || date != nil else { return nil }
                let room = slot["room"] as? [String: Any] ?? [:]
                let building = room["building"] as? [String: Any] ?? [:]
                let roomName = room["nameZh"] as? String ?? ""
                let place = [building["nameZh"] as? String ?? "", roomName].filter { !$0.isEmpty }.joined(separator: " ")
                let start = slot["startUnit"] as? Int ?? 0
                return Lesson(id: "\(entry["id"] ?? "course")-\(index)", name: course["nameZh"] as? String ?? "课程", week: week, weekday: weekday, start: start, end: max(start, slot["endUnit"] as? Int ?? start), date: date, time: [slot["startTime"] as? String, slot["endTime"] as? String].compactMap { $0 }.joined(separator: " - "), room: place.isEmpty ? slot["customPlace"] as? String ?? "" : place, teacher: slot["teacherName"] as? String ?? "")
            }
        }
        if let semester = semesters.first(where: { $0.id == selectedSemester }) {
            let current = semester.startDate.flatMap { ISO8601DateFormatter().date(from: String($0.prefix(10)) + "T00:00:00Z") }.map { Int(Date().timeIntervalSince($0) / (7 * 86400)) + 1 } ?? 1
            week = semester.weeks.contains(current) ? current : semester.weeks.first ?? 1
        }
    }

    func refreshBalance() async throws {
        guard let token = validToken else { throw PocketError.message("登录已过期，请重新登录") }
        let url = try API.url("https://info.s.zzu.edu.cn", "/portal-api/v1/thrid-adapter/get-person-info-card-list")
        let (data, response) = try await API.request(url, headers: ["X-Id-Token": token])
        let result = try API.json(data, response)
        guard let cards = result["data"] as? [[String: Any]] else { throw PocketError.message("余额数据格式有误") }
        func amount(_ card: [String: Any]) -> Double? {
            (card["amount"] as? NSNumber)?.doubleValue ?? Double("\(card["amount"] ?? "")")
        }
        guard let value = (cards.count > 1 ? amount(cards[1]) : nil) ?? cards.reversed().compactMap(amount).first else { throw PocketError.message("未找到校园卡余额") }
        guard self.token == token else { return }
        balance = value
        balanceUpdatedAt = Date()
    }

    private func electricityQuantity(roomID: String) async throws -> Double {
        let access = try await ecardAccessToken()
        let parts = roomID.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 5, parts[2].isEmpty, !parts[0].isEmpty, !parts[1].isEmpty, !parts[3].isEmpty, !parts[4].isEmpty else { throw PocketError.message("房间号格式应为 area-building--level-room") }
        let payload: [String: Any] = ["utilityType": "electric", "bigArea": "", "area": String(parts[0]), "building": String(parts[1]), "unit": "", "level": String(parts[3]), "room": roomID, "subArea": ""]
        let accountURL = try API.url(API.ecard, "/server/utilities/account")
        let result = try await API.postJSON(accountURL, token: access, payload: payload)
        guard result["success"] as? Bool == true else {
            throw PocketError.message("学校未返回有效的电表数据，请确认编号")
        }
        let templates = (result["resultData"] as? [String: Any])?["templateList"] as? [[String: Any]] ?? []
        let amount = templates.first(where: { $0["code"] as? String == "quantity" })?["value"]
        guard let value = (amount as? NSNumber)?.doubleValue ?? Double("\(amount ?? "")") else { throw PocketError.message("未找到剩余电量") }
        guard value.isFinite else { throw PocketError.message("学校返回的电量不是有效数字") }
        return value
    }

    func refreshTrades() async throws {
        let access = try await ecardAccessToken()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let body: [String: Any] = ["pageSize": "50", "pageNo": 0, "tradeType": "1,2,3", "fromDate": formatter.string(from: Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()), "toDate": formatter.string(from: Date())]
        let url = try API.url(API.ecard, "/server/user/tradeList")
        let result = try await API.postJSON(url, token: access, payload: body)
        guard result["success"] as? Bool == true, let rows = result["resultData"] as? [[String: Any]] else { throw PocketError.message(result["message"] as? String ?? "校园卡流水格式有误") }
        trades = rows.enumerated().compactMap { index, row in
            guard let amount = Double("\(row["amt"] ?? "")") else { return nil }
            return CardTrade(id: "\(row["journo"] ?? index)-\(index)", date: row["date"] as? String ?? "", merchant: row["merchantName"] as? String ?? "", summary: row["summary"] as? String ?? "", amount: amount)
        }
    }

    func startRoomPicker() async throws {
        roomScope = [:]
        try await loadRoomLevel("area")
    }

    func pickRoomNode(_ node: RoomNode) async throws {
        if roomIsLastLevel {
            setRoom(node.id, for: activeMeter)
            return
        }
        guard let next = roomNextLevel else { throw PocketError.message("学校没有返回下一层房间类型") }
        roomScope[roomLevel.lowercased()] = node.id
        try await loadRoomLevel(next)
    }

    private func loadRoomLevel(_ level: String) async throws {
        let access = try await ecardAccessToken()
        var body: [String: Any] = ["utilityType": "electric", "locationType": level]
        for key in ["bigArea", "area", "building", "unit", "level", "room", "subArea"] {
            body[key] = roomScope[key.lowercased()] ?? ""
        }
        let url = try API.url(API.ecard, "/server/utilities/location")
        let result = try await API.postJSON(url, token: access, payload: body)
        guard result["success"] as? Bool == true, let value = result["resultData"] as? [String: Any] else { throw PocketError.message(result["message"] as? String ?? "房间列表格式有误") }
        roomLevel = value["locationType"] as? String ?? level
        roomNextLevel = value["nextLocationType"] as? String
        roomIsLastLevel = value["end"] as? Bool ?? false
        roomNodes = (value["locationList"] as? [[String: Any]] ?? []).compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            return RoomNode(id: id, name: item["name"] as? String ?? id)
        }
    }

    private func ecardAccessToken() async throws -> String {
        guard let token = validToken else { throw PocketError.message("登录已过期，请重新登录") }
        let openURL = try API.url(API.ecard, "/server/auth/host/open", query: [.init(name: "host", value: "11"), .init(name: "org", value: "2"), .init(name: "token", value: token)])
        let (_, redirect) = try await API.request(openURL, redirects: false)
        guard let location = redirect.value(forHTTPHeaderField: "Location"), let url = URL(string: location, relativeTo: openURL)?.absoluteURL,
              url.host == URL(string: API.ecard)?.host,
              let tid = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "tid" })?.value else { throw PocketError.message("一卡通未返回登录凭据") }
        let tokenURL = try API.url(API.ecard, "/server/auth/getToken")
        let (tokenData, tokenResponse) = try await API.request(tokenURL, method: "POST", headers: ["Content-Type": "application/json"], body: try JSONSerialization.data(withJSONObject: ["tid": tid]))
        let tokenResult = try API.json(tokenData, tokenResponse)
        guard let access = (tokenResult["resultData"] as? [String: Any])?["accessToken"] as? String else { throw PocketError.message("一卡通认证失败") }
        return access
    }
}
