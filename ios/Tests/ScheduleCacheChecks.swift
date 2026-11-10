import Foundation

final class UserDefaults {
    static let standard = UserDefaults()
    var values: [String: Any] = [:]
    func string(forKey key: String) -> String? { values[key] as? String }
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values.removeValue(forKey: key) }
}
enum TokenStore {
    static var value: String? = {
        let data = try! JSONSerialization.data(withJSONObject: ["exp": Date().timeIntervalSince1970 + 86400])
        return "header." + data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") + ".signature"
    }()
    static func load() -> String? { value }
    static func save(_ token: String?) { value = token }
}
enum PocketError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}
@MainActor enum API {
    static let ecard = "https://example.invalid"
    static var failBalance = false
    static var delayMeter = false
    static func url(_ base: String, _ path: String, query: [URLQueryItem] = []) throws -> URL {
        var parts = URLComponents(string: base + path)!
        parts.queryItems = query.isEmpty ? nil : query
        return parts.url!
    }
    static func request(_ url: URL, method: String = "GET", headers: [String:String] = [:], body: Data? = nil, redirects: Bool = true) async throws -> (Data, HTTPURLResponse) {
        if url.path.contains("get-person-info") && failBalance { throw PocketError.message("offline") }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Location": "https://example.invalid/?tid=test"])!
        return (Data(url.path.utf8), response)
    }
    static func json(_ data: Data, _ response: HTTPURLResponse) throws -> [String:Any] {
        if response.url!.path.contains("getToken") { return ["resultData": ["accessToken":"test"]] }
        return ["data": [["amount":0], ["amount":12.5]]]
    }
    static var scheduleOffline = false
    static func eas(_ path: String, token: String, step: String) async throws -> [String:Any] {
        if scheduleOffline { throw PocketError.message("network unavailable") }
        if path.contains("get-all-semesters") { return ["data": [["id": 1, "nameZh": "Example", "weekIndices": [1,2]]]] }
        if path.contains("current-semester") { return ["data": ["id": 1]] }
        return ["data": [["id": 1, "course": ["nameZh": "Sample"], "schedules": [["weekIndex": 1, "weekday": 1, "startUnit": 1, "endUnit": 2]]]]]
    }
    static func postJSON(_ url: URL, token: String, payload: [String:Any]) async throws -> [String:Any] {
        if url.path == "/server/recharge/config" {
            if failBalance { throw PocketError.message("offline") }
            return ["success": true, "resultData": ["balance": "12.50"]]
        }
        if delayMeter { try await Task.sleep(for: .milliseconds(100)) }
        let room = payload["room"] as? String ?? ""
        return ["success":true,"resultData":["templateList":[["code":"quantity","value":room.hasSuffix("8101") ? 22.0 : 11.0]]]]
    }
}

@main struct ScheduleChecks {
    @MainActor static func main() async throws {
        let model = PocketModel()
        try await model.refreshSchedule()
        precondition(model.lessons.count == 1)
        let date = model.scheduleUpdatedAt
        let restarted = PocketModel()
        precondition(restarted.lessons.map(\.id) == model.lessons.map(\.id))
        precondition(restarted.selectedSemester == 1 && restarted.scheduleUpdatedAt == date)
        API.scheduleOffline = true
        do { try await restarted.refreshSchedule(); fatalError("Expected offline failure") } catch {}
        precondition(restarted.lessons.count == 1 && restarted.scheduleUpdatedAt == date)
        let existing = restarted.token!
        restarted.completeSignIn(account: "different-synthetic-account", token: existing + "different")
        precondition(restarted.lessons.isEmpty)
        model.signOut()
        precondition(UserDefaults.standard.data(forKey: "scheduleCacheV1") == nil)
        precondition(PocketModel().lessons.isEmpty)
        print("PASS: cache survives restart and network failure; new session isolation; logout removes cached schedule")
    }
}
