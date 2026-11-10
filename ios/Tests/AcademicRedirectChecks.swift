import Foundation

@main struct AcademicRedirectChecks {
 static func main() throws {
let source = URL(string: "https://jwxt.zzu.edu.cn/eams-door/api/v1/calendar/get-all-semesters")!
func redirect(_ destination: String) -> HTTPURLResponse {
    HTTPURLResponse(url: source, statusCode: 302, httpVersion: nil, headerFields: ["Location": destination])!
}
let valid = try API.academicRedirect(from: source, response: redirect("/eams-door/api/v1/calendar/get-all-semesters/"))
precondition(valid.host == "jwxt.zzu.edu.cn")
for target in ["https://cas.s.zzu.edu.cn/login", "http://jwxt.zzu.edu.cn/eams-door/api/x", "https://evil.example/eams-door/api/x", "https://jwxt.zzu.edu.cn/login", "https://jwxt.zzu.edu.cn:8443/eams-door/api/x", "https://user:pass@jwxt.zzu.edu.cn/eams-door/api/x"] {
    do { _ = try API.academicRedirect(from: source, response: redirect(target)); fatalError("Unsafe redirect accepted") } catch {}
}
do { _ = try API.json(Data("<html>login</html>".utf8), redirect("https://cas.s.zzu.edu.cn/login")); fatalError("Redirect parsed as JSON") }
catch { precondition(!error.localizedDescription.contains("响应不是 JSON")) }
print("PASS: same-origin API redirect, auth redirect, captive portal, HTTP downgrade, foreign origin and JSON handling")

 }
}
