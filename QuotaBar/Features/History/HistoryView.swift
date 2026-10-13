import Charts
import SwiftUI

struct HistoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var range: HistoryRange = .day
    @State private var samples: [HistorySample] = []

    enum HistoryRange: Int, CaseIterable, Identifiable {
        case day = 1
        case week = 7
        case month = 30
        case quarter = 90

        var id: Int { rawValue }

        var displayName: String {
            switch self {
            case .day: "24 Hours"
            case .week: "7 Days"
            case .month: "30 Days"
            case .quarter: "90 Days"
            }
        }
    }

    private var availableRanges: [HistoryRange] {
        HistoryRange.allCases.filter { $0.rawValue <= max(environment.settings.historyRetention.rawValue, 1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Range", selection: $range) {
                ForEach(availableRanges) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            if samples.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Usage is recorded locally each time QuotaBar refreshes.")
                )
            } else {
                chart
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 320)
        .task(id: range) { await load() }
        .onChange(of: environment.store.lastRefresh) { _, _ in
            Task { await load() }
        }
    }

    private var chart: some View {
        Chart(samples, id: \.identity) { sample in
            LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("Usage", sample.usedPercentage)
            )
            .foregroundStyle(by: .value("Series", sample.seriesName))
            .interpolationMethod(.stepEnd)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 20, 40, 60, 80, 100]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let percent = value.as(Int.self) {
                        Text("\(percent)%")
                    }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .accessibilityLabel("Usage history chart")
    }

    private func load() async {
        let cutoff = Date().addingTimeInterval(-Double(range.rawValue) * 86400)
        samples = await environment.history.samples(since: cutoff)
    }
}

private extension HistorySample {
    var identity: String { "\(seriesName)-\(timestamp.timeIntervalSince1970)" }
}
