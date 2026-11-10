import SwiftUI
import BackgroundTasks
import UIKit

@MainActor
final class CampusBackgroundRefresh: ObservableObject {
    static let identifier = "com.zzupocket.campus.refresh"
    private let model: PocketModel
    private var scheduleGeneration = 0

    @Published private(set) var enabled: Bool
    @Published private(set) var systemStatus = "正在检查"
    @Published private(set) var scheduleStatus = "等待安排"
    @Published private(set) var earliestRefresh: Date?
    @Published private(set) var lastAttempt: Date?
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var lastResult: String

    init(model: PocketModel) {
        self.model = model
        let defaults = UserDefaults.standard
        enabled = defaults.object(forKey: "backgroundRefreshEnabled") as? Bool ?? true
        lastAttempt = defaults.object(forKey: "backgroundRefreshAttempt") as? Date
        lastUpdate = defaults.object(forKey: "backgroundRefreshUpdate") as? Date
        lastResult = defaults.string(forKey: "backgroundRefreshResult") ?? "尚未获得后台运行机会"
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "backgroundRefreshEnabled")
        Task { await schedule() }
    }

    func updateSystemStatus() {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available:
            systemStatus = ProcessInfo.processInfo.isLowPowerModeEnabled ? "低电量模式暂缓" : "系统允许"
        case .denied: systemStatus = "系统已关闭后台刷新"
        case .restricted: systemStatus = "系统限制后台刷新"
        @unknown default: systemStatus = "系统状态未知"
        }
    }

    func schedule() async {
        defer {
            #if DEBUG
            print("Campus background refresh schedule: \(scheduleStatus); system: \(systemStatus)")
            #endif
        }
        scheduleGeneration += 1
        let generation = scheduleGeneration
        updateSystemStatus()
        guard enabled, model.loggedIn else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
            earliestRefresh = nil
            scheduleStatus = enabled ? "等待有效登录" : "已关闭"
            return
        }
        guard UIApplication.shared.backgroundRefreshStatus == .available,
              !ProcessInfo.processInfo.isLowPowerModeEnabled else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.identifier)
            earliestRefresh = nil
            scheduleStatus = "等待系统允许"
            return
        }
        // Preserve an existing request so opening the app doesn't postpone it.
        let pending = await BGTaskScheduler.shared.pendingTaskRequests()
        guard generation == scheduleGeneration, enabled, model.loggedIn else { return }
        if let request = pending.first(where: { $0.identifier == Self.identifier }) {
            earliestRefresh = request.earliestBeginDate
            scheduleStatus = "已申请，等待系统安排"
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            earliestRefresh = request.earliestBeginDate
            scheduleStatus = "已申请，等待系统安排"
        } catch {
            earliestRefresh = nil
            scheduleStatus = "申请未成功，回到 App 后重试"
        }
    }

    func run() async {
        lastAttempt = Date()
        UserDefaults.standard.set(lastAttempt, forKey: "backgroundRefreshAttempt")
        finish("正在后台查询")
        // Chain the next request even when this attempt fails or expires.
        await schedule()
        guard enabled else { finish("后台刷新已关闭"); return }
        guard model.loggedIn else { finish("登录已过期，请重新登录"); return }
        // A foreground request may still be winding down when iOS wakes us.
        for _ in 0..<20 where model.campusRefreshing && !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { break }
        }
        let outcome = await model.refreshCampus()
        switch outcome {
        case .complete, .partial:
            lastUpdate = Date()
            UserDefaults.standard.set(lastUpdate, forKey: "backgroundRefreshUpdate")
            finish(outcome == .complete ? "校园卡和已配置电表已更新" : "部分数据已更新，其他查询失败")
        case .failed: finish("查询未成功，请检查网络或学校服务")
        case .loggedOut: finish("登录已过期，请重新登录")
        case .busy: finish("已有查询进行中，本次未重复查询")
        case .cancelled: finish("后台时间结束，已保留本次成功取得的数据")
        }
    }

    private func finish(_ result: String) {
        lastResult = result
        UserDefaults.standard.set(result, forKey: "backgroundRefreshResult")
        #if DEBUG
        print("Campus background refresh result: \(result)")
        #endif
    }
}

struct BackgroundRefreshSettings: View {
    @EnvironmentObject private var background: CampusBackgroundRefresh

    var body: some View {
        Section {
            Toggle("后台自动更新", isOn: Binding(get: { background.enabled }, set: { background.setEnabled($0) }))
                .tint(PocketStyle.accent)
            LabeledContent("系统状态", value: background.systemStatus)
            if background.enabled {
                Text(background.scheduleStatus).font(.caption).foregroundStyle(.secondary)
                if let date = background.earliestRefresh {
                    timestamp("最早允许刷新", date)
                }
                if let date = background.lastAttempt { timestamp("最近后台尝试", date) }
                if let date = background.lastUpdate { timestamp("最近后台更新", date) }
                Text(background.lastResult).font(.caption).foregroundStyle(.secondary)
            }
            Button("打开系统设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        } header: {
            Text("后台刷新")
        } footer: {
            Text("系统择机刷新，不保证固定间隔。需允许后台 App 刷新并保持学校登录有效；关闭低电量模式有助于获得后台运行机会。")
        }
    }

    private func timestamp(_ title: String, _ date: Date) -> some View {
        LabeledContent(title) {
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .multilineTextAlignment(.trailing)
        }.font(.caption)
    }
}
