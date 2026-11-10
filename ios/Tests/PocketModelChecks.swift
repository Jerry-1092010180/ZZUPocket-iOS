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
    static func eas(_ path: String, token: String, step: String) async throws -> [String:Any] { [:] }
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
@main struct Checks {
    @MainActor static func main() async {
        precondition(try! parseCampusCardBalance(["balance": "0.00"]) == 0)
        precondition(try! parseCampusCardBalance(["balance": 12.5]) == 12.5)
        for invalid: [String: Any] in [[:], ["amount": 12.5], ["balance": true], ["balance": "NaN"], ["balance": "1.234"], ["balance": Double.infinity]] {
            do { _ = try parseCampusCardBalance(invalid); fatalError("Invalid balance accepted") } catch {}
        }
        let model = PocketModel()
        model.setRoom("99-1--1-101", for: .lighting)
        model.setRoom("99-1--1-8101", for: .airConditioning)
        await model.refreshCampus()
        precondition(model.balance == 12.5)
        precondition(model.meters[.lighting]?.quantity == 11)
        precondition(model.meters[.airConditioning]?.quantity == 22)
        let restored = PocketModel()
        precondition(restored.balance == nil && restored.meters[.airConditioning]?.quantity == 22)
        model.setRoom("99-1--1-102", for: .lighting)
        precondition(model.meters[.lighting]?.quantity == nil && model.meters[.airConditioning]?.quantity == 22)
        API.failBalance = true
        await model.refreshCampus()
        precondition(model.balance == nil && model.balanceError != nil)
        precondition(model.meters[.lighting]?.quantity == 11 && model.meters[.lighting]?.error == nil)
        API.delayMeter = true
        let task = Task { await model.refreshCampus() }
        try! await Task.sleep(for: .milliseconds(30))
        model.setRoom("99-1--1-103", for: .lighting)
        _ = await task.value
        precondition(model.meters[.lighting]?.quantity == nil, "Old room response leaked")
        let savedToken = model.token!
        model.completeSignIn(account: "history-A", token: savedToken)
        API.delayMeter = false
        await model.refreshCampus()
        precondition(model.meterHistory[.airConditioning]?.isEmpty == false)
        let historyCount = model.meterHistory[.airConditioning]!.count
        let restart = PocketModel()
        precondition(restart.meterHistory[.airConditioning]?.count == historyCount)
        model.completeSignIn(account: "history-B", token: savedToken)
        precondition(model.meterHistory[.airConditioning]?.isEmpty == true)
        model.completeSignIn(account: "history-A", token: savedToken)
        precondition(model.meterHistory[.airConditioning]?.count == historyCount)
        model.setRoom("99-1--1-8102", for: .airConditioning)
        precondition(model.meterHistory[.airConditioning]?.isEmpty == true)
        model.setRoom("99-1--1-8101", for: .airConditioning)
        precondition(model.meterHistory[.airConditioning]?.count == historyCount)
        model.completeSignIn(account: "background-checks", token: savedToken)
        model.setRoom("99-1--1-201", for: .lighting)
        model.setRoom("99-1--1-8201", for: .airConditioning)
        API.delayMeter = true
        API.failBalance = false
        let cancelled = Task { await model.refreshCampus() }
        try! await Task.sleep(for: .milliseconds(30))
        let busy = await model.refreshCampus()
        precondition(busy == .busy)
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        precondition(cancelledResult == .cancelled)
        precondition(!model.campusRefreshing)
        precondition(model.meters[.lighting]?.quantity == nil)
        precondition(model.meters[.lighting]?.error == nil)
        precondition(model.meterHistory[.lighting]?.isEmpty == true)
        API.delayMeter = false
        API.failBalance = true
        let partial = await model.refreshCampus()
        precondition(partial == .partial)
        precondition(model.meterHistory[.lighting]?.isEmpty == false)
        API.failBalance = false
        let complete = await model.refreshCampus()
        precondition(complete == .complete)
        model.signOut()
        let loggedOut = await model.refreshCampus()
        precondition(loggedOut == .loggedOut)
        precondition(model.meterHistory.isEmpty)
        precondition(model.balance == nil && model.meters[.airConditioning]?.quantity == nil)
        precondition(UserDefaults.standard.data(forKey: "campusCacheV1") == nil)
        print("PASS: meter/cache/history isolation, cancellation without false errors or samples, busy guard, partial/complete refresh, logout")
    }
}
