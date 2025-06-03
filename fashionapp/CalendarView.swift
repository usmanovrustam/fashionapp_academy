import SwiftUI

struct CalendarView: View {
    @StateObject private var weatherManager = WeatherManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: 0) {
            Text(NSLocalizedString("7-Day Calendar & Weather", comment: ""))
                .font(.title2.bold())
                .padding(.top, 24)
            if weatherManager.isLoading {
                HStack {
                    ProgressView()
                    Text(NSLocalizedString("Loading weather...", comment: ""))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 24)
            } else if let error = weatherManager.error {
                Text(String(format: NSLocalizedString("Weather unavailable: %@", comment: ""), error.localizedDescription))
                    .font(.subheadline)
                    .foregroundColor(.red)
                    .padding(.top, 24)
            } else {
                List(weatherManager.dailyForecast) { day in
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(longDayString(from: day.date))
                                .font(.headline)
                            Text(shortDateString(from: day.date))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: day.symbolName)
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(day.high.value))°")
                                .font(.headline)
                            Text("\(Int(day.low.value))°")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .listStyle(.plain)
                .padding(.top, 8)
            }
            Spacer()
        }
        .onAppear {
            Task { await weatherManager.requestWeather() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await weatherManager.requestWeather() }
            }
        }
    }

    private func longDayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter.string(from: date)
    }
    private func shortDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }
} 