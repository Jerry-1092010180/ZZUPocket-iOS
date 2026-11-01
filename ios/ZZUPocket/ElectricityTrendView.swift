import SwiftUI
import Charts

struct ElectricityTrendView: View {
    let samples: [EnergySample]
    let meterName: String
    @State private var period: EnergyPeriod = .day
    @State private var selectedDate: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            content(now: context.date)
        }
    }

    private func content(now: Date) -> some View {
        let visible = EnergyHistory.visible(samples, period: period, now: now)
        let points = EnergyHistory.plot(visible, period: period)
        let selected = selectedDate.flatMap { date in points.min { abs($0.sample.date.timeIntervalSince(date)) < abs($1.sample.date.timeIntervalSince(date)) } }
        let shown = selected?.sample ?? visible.last
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("剩余电量趋势", systemImage: "chart.xyaxis.line").font(.subheadline.weight(.semibold))
                Spacer()
                Text("度").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                ForEach(EnergyPeriod.allCases) { item in
                    Button {
                        period = item
                        selectedDate = nil
                    } label: {
                        Text(item.rawValue).font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(period == item ? Color.white : Color.secondary)
                            .background(period == item ? PocketStyle.accent : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityValue(period == item ? "已选择" : "未选择")
                }
            }
            .padding(4)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selected == nil ? period.title : "选中采样")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(shown.map { String(format: "%.2f 度", $0.quantity) } ?? "暂无记录")
                        .font(.title3.bold().monospacedDigit()).foregroundStyle(PocketStyle.accent)
                }
                Spacer()
                if let shown {
                    Text(shown.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
            }
            if points.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chart.line.uptrend.xyaxis").font(.title2).foregroundStyle(PocketStyle.accent)
                    Text("这个时段还没有采样").font(.subheadline)
                    Text("成功查询后自动记录，可切换其他时段查看。")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).frame(height: 180)
            } else {
                chart(points: points, selected: selected, now: now)
                if points.count == 1 {
                    Text("已记录首个数据点，下一次采样后开始形成趋势。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(String(format: "记录内下降 %.2f 度 · %d 次采样", EnergyHistory.recordedDecrease(visible, gapLimit: period.gapLimit), visible.count))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            Text("点按或拖动查看 · 断线表示缺少采样 · 橙点表示余额增加（可能充值）。仅统计有记录区间，非完整用电账单。")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(PocketStyle.accent.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(meterName)剩余电量趋势")
    }

    private func chart(points: [EnergyPlotPoint], selected: EnergyPlotPoint?, now: Date) -> some View {
        let values = points.map { $0.sample.quantity }
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let pad = max(0.5, (high - low) * 0.15)
        let lower = low >= 0 ? max(0, low - pad) : low - pad
        let upper = max(lower + 1, high + pad)
        return Chart {
            ForEach(points) { point in
                LineMark(x: .value("时间", point.sample.date), y: .value("剩余电量", point.sample.quantity), series: .value("连续记录", point.segment))
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(PocketStyle.accent)
                PointMark(x: .value("时间", point.sample.date), y: .value("剩余电量", point.sample.quantity))
                    .symbolSize(point.increase ? 35 : points.count == 1 ? 45 : 8)
                    .foregroundStyle(point.increase ? Color.orange : PocketStyle.accent)
                    .accessibilityLabel(point.sample.date.formatted(date: .abbreviated, time: .shortened))
                    .accessibilityValue(String(format: "剩余 %.2f 度", point.sample.quantity))
            }
            if let selected {
                RuleMark(x: .value("选中时间", selected.sample.date))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3])).foregroundStyle(.secondary)
                PointMark(x: .value("时间", selected.sample.date), y: .value("剩余电量", selected.sample.quantity))
                    .symbolSize(65).foregroundStyle(PocketStyle.accent)
            }
        }
        .chartXScale(domain: period.start(relativeTo: now)...now)
        .chartYScale(domain: lower...upper)
        .chartXSelection(value: $selectedDate)
        .chartGesture { proxy in
            DragGesture(minimumDistance: 0)
                .onChanged { value in proxy.selectXValue(at: value.location.x) }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        if period == .hour || period == .day {
                            Text(date, format: .dateTime.hour().minute())
                        } else {
                            Text(date, format: .dateTime.month(.defaultDigits).day())
                        }
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel()
            }
        }
        .frame(height: 190)
    }
}
