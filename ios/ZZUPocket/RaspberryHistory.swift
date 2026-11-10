import SwiftUI

struct RaspberryReading: Codable {
    let timestamp: Double
    let quantity: Double
}
struct RaspberryMeter: Codable {
    let kind: String
    let samples: [RaspberryReading]
    var title: String { kind == "lighting" ? "照明" : "空调" }
    var history: [EnergySample] {
        samples.filter { $0.timestamp.isFinite && $0.quantity.isFinite && $0.timestamp > 0 && $0.timestamp <= Date().timeIntervalSince1970 + 60 }
            .map { EnergySample(date: Date(timeIntervalSince1970: $0.timestamp), quantity: $0.quantity) }
            .sorted { $0.date < $1.date }
    }
}
struct RaspberrySnapshot: Codable {
    let generatedAt: Double
    let meters: [RaspberryMeter]
}

@MainActor
final class RaspberryHistory: ObservableObject {
    @Published var snapshot: RaspberrySnapshot?
    private let cacheKey = "personalRaspberryHistoryV1"

    init() {
        if let cached = UserDefaults.standard.data(forKey: cacheKey) {
            snapshot = try? JSONDecoder().decode(RaspberrySnapshot.self, from: cached)
        }
        if let url = Bundle.main.url(forResource: "PrivateHistorySnapshot", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let imported = try? JSONDecoder().decode(RaspberrySnapshot.self, from: data),
           imported.generatedAt > (snapshot?.generatedAt ?? 0) {
            snapshot = imported
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

}

struct RaspberryHistoryView: View {
    @StateObject private var history = RaspberryHistory()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("树莓派连续采集", systemImage: "externaldrive.connected.to.line.below").font(.headline)
                    Text("树莓派历史快照 · 可离线查看").font(.subheadline).foregroundStyle(.secondary)
                    if let snapshot = history.snapshot {
                        Text("数据打包于 \(Date(timeIntervalSince1970: snapshot.generatedAt).formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("本次更新已导入打包时的记录，之后新增数据可在下次更新时补入。")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding().background(.background, in: RoundedRectangle(cornerRadius: 18))
                if let snapshot = history.snapshot {
                    ForEach(snapshot.meters, id: \.kind) { meter in
                        VStack(alignment: .leading, spacing: 12) {
                            Label(meter.title, systemImage: meter.kind == "lighting" ? "lightbulb.fill" : "snowflake").font(.headline)
                            if let latest = meter.history.last {
                                Text(String(format: "%.2f 度", latest.quantity)).font(.largeTitle.bold()).foregroundStyle(PocketStyle.accent)
                                Text("采样于 \(latest.date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                            }
                            ElectricityTrendView(samples: meter.history, meterName: meter.title)
                        }.padding().background(.background, in: RoundedRectangle(cornerRadius: 18))
                    }
                }

            }.padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("寝室连续记录")
    }
}
