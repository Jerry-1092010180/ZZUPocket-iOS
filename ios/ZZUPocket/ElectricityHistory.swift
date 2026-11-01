import Foundation

struct EnergySample: Codable, Identifiable, Equatable {
    let date: Date
    let quantity: Double
    var id: Date { date }
}

enum EnergyPeriod: String, CaseIterable, Identifiable {
    case hour = "小时", day = "天", week = "周", month = "月"
    var id: Self { self }
    var title: String {
        switch self {
        case .hour: return "最近 1 小时"
        case .day: return "最近 24 小时"
        case .week: return "最近 7 天"
        case .month: return "最近 1 个月"
        }
    }
    func start(relativeTo now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .hour: return now.addingTimeInterval(-3600)
        case .day: return now.addingTimeInterval(-86400)
        case .week: return now.addingTimeInterval(-7 * 86400)
        case .month: return calendar.date(byAdding: .month, value: -1, to: now) ?? now.addingTimeInterval(-30 * 86400)
        }
    }
    var gapLimit: TimeInterval { self == .hour || self == .day ? 20 * 60 : 4 * 3600 }
    var bucket: TimeInterval {
        switch self {
        case .hour: return 60
        case .day: return 15 * 60
        case .week: return 3600
        case .month: return 6 * 3600
        }
    }
}

struct EnergyPlotPoint: Identifiable {
    let sample: EnergySample
    let segment: Int
    let increase: Bool
    var id: Date { sample.date }
}

enum EnergyHistory {
    static let retention: TimeInterval = 90 * 86400

    // One sample per minute for two days, then one per hour, retained for 90 days.
    static func recording(_ sample: EnergySample, in existing: [EnergySample], now: Date = Date()) -> [EnergySample] {
        guard sample.quantity.isFinite, sample.date <= now, sample.date >= now.addingTimeInterval(-retention) else { return existing }
        var buckets: [String: EnergySample] = [:]
        for item in (existing + [sample]).sorted(by: { $0.date < $1.date }) {
            guard item.quantity.isFinite, item.date >= now.addingTimeInterval(-retention), item.date <= now else { continue }
            let recent = item.date >= now.addingTimeInterval(-2 * 86400)
            let interval: TimeInterval = recent ? 60 : 3600
            let key = "\(recent)-\(Int(floor(item.date.timeIntervalSince1970 / interval)))"
            buckets[key] = item
        }
        return buckets.values.sorted { $0.date < $1.date }
    }

    static func visible(_ samples: [EnergySample], period: EnergyPeriod, now: Date) -> [EnergySample] {
        let start = period.start(relativeTo: now)
        return samples.filter { $0.date >= start && $0.date <= now && $0.quantity.isFinite }.sorted { $0.date < $1.date }
    }

    static func plot(_ samples: [EnergySample], period: EnergyPeriod) -> [EnergyPlotPoint] {
        var segment = 0
        var points: [EnergyPlotPoint] = []
        var previous: EnergySample?
        for sample in samples {
            let increase = previous.map { sample.quantity - $0.quantity > 0.001 } ?? false
            if let previous, sample.date.timeIntervalSince(previous.date) > period.gapLimit || increase { segment += 1 }
            points.append(EnergyPlotPoint(sample: sample, segment: segment, increase: increase))
            previous = sample
        }
        // Preserve endpoints and extrema in each display bucket, without averaging balances.
        let groups = Dictionary(grouping: points) { "\($0.segment)-\(Int(floor($0.sample.date.timeIntervalSince1970 / period.bucket)))" }
        var selected: [Date: EnergyPlotPoint] = [:]
        for group in groups.values {
            for point in [group.first, group.last, group.min(by: { $0.sample.quantity < $1.sample.quantity }), group.max(by: { $0.sample.quantity < $1.sample.quantity })].compactMap({ $0 }) {
                selected[point.sample.date] = point
            }
        }
        return selected.values.sorted { $0.sample.date < $1.sample.date }
    }

    static func recordedDecrease(_ samples: [EnergySample], gapLimit: TimeInterval) -> Double {
        zip(samples, samples.dropFirst()).reduce(0) { total, pair in
            let interval = pair.1.date.timeIntervalSince(pair.0.date)
            guard interval > 0, interval <= gapLimit else { return total }
            return total + max(0, pair.0.quantity - pair.1.quantity)
        }
    }
}
