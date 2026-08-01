import SwiftUI
import UIKit

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasPlan: Bool

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 4) {
            Text(Self.dayFormatter.string(from: date))
                .font(.system(.body, design: .rounded).weight(isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: 36, height: 36)
                .background {
                    if isSelected {
                        Circle().fill(AppColors.primaryGradient)
                    } else {
                        Circle().fill(Color.clear)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(AppColors.brand.opacity(isToday && !isSelected ? 1 : 0), lineWidth: 2)
                )

            Circle()
                .fill(AppColors.brand)
                .frame(width: 5, height: 5)
                .opacity(hasPlan ? 1 : 0)
        }
    }
}

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var currentMonth: Date = Date()
    @Published var selectedDate: Date = Date()
    @Published var items: [WardrobeItem] = []
    @Published var events: [CalendarEvent] = []
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?

    private let wardrobeRepository: WardrobeRepository
    private let eventRepository: EventRepository
    private let packingListRepository: PackingListRepository
    let imageStorage: ImageStorage
    private let calendar = Calendar.current

    init(container: AppContainer) {
        self.wardrobeRepository = container.wardrobeRepository
        self.eventRepository = container.eventRepository
        self.packingListRepository = container.packingListRepository
        self.imageStorage = container.imageStorage
    }

    var daysInMonth: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: currentMonth),
              let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth))
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leading = Array(repeating: Date?.none, count: firstWeekday - 1)
        let days: [Date?] = range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
        }
        return leading + days
    }

    func items(on date: Date) -> [WardrobeItem] {
        items.filter { item in
            guard let planned = item.plannedDate else { return false }
            return calendar.isDate(planned, inSameDayAs: date)
        }
    }

    func events(on date: Date) -> [CalendarEvent] {
        events.filter { event in
            let start = calendar.startOfDay(for: event.startDate)
            let end = calendar.startOfDay(for: event.endDate)
            let day = calendar.startOfDay(for: date)
            return day >= start && day <= end
        }
    }

    func hasPlan(on date: Date) -> Bool {
        !items(on: date).isEmpty || !events(on: date).isEmpty
    }

    func shiftMonth(_ value: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: value, to: currentMonth) {
            currentMonth = newMonth
            Task { await loadEventsForVisibleMonth() }
        }
    }

    func load() async {
        isLoading = true
        items = (try? await wardrobeRepository.fetchAll()) ?? []
        await loadEventsForVisibleMonth()
        isLoading = false
    }

    private func loadEventsForVisibleMonth() async {
        guard
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)),
            let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)
        else {
            events = []
            return
        }
        // Widen slightly so multi-day trips that spill across months still show.
        let from = calendar.date(byAdding: .day, value: -7, to: monthStart) ?? monthStart
        let to = calendar.date(byAdding: .day, value: 7, to: monthEnd) ?? monthEnd
        events = (try? await eventRepository.fetchEvents(from: from, to: to)) ?? []
    }

    func saveDayPlan(event: CalendarEvent, packingList: PackingList?, wardrobeUpdates: [WardrobeItem]) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await eventRepository.save(event)
            if let packingList {
                try await packingListRepository.save(packingList)
            }
            for item in wardrobeUpdates {
                try await wardrobeRepository.save(item)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: currentMonth)
    }
}

struct CalendarFeatureView: View {
    private let container: AppContainer
    @StateObject private var viewModel: CalendarViewModel
    @State private var showScanner = false
    @State private var showDayPlanSheet = false

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    init(container: AppContainer) {
        self.container = container
        _viewModel = StateObject(wrappedValue: CalendarViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    monthHeader
                    calendarGrid
                    dayPlansSection
                    plannedLooksSection
                }
                .padding()
                .padding(.bottom, AppSpacing.lg)
            }
            .nookSafeScreenInsets()
            .nookScreenBackground()
            .navigationTitle(NSLocalizedString("Calendar", comment: ""))
            .sheet(isPresented: $showScanner) {
                ScannerFeatureView(container: container, plannedDate: viewModel.selectedDate)
            }
            .sheet(isPresented: $showDayPlanSheet) {
                DayPlanSheetView(
                    date: viewModel.selectedDate,
                    wardrobeItems: viewModel.items,
                    imageStorage: viewModel.imageStorage,
                    onSave: { event, packing, wardrobeUpdates in
                        showDayPlanSheet = false
                        Task {
                            await viewModel.saveDayPlan(
                                event: event,
                                packingList: packing,
                                wardrobeUpdates: wardrobeUpdates
                            )
                        }
                    },
                    onCancel: { showDayPlanSheet = false }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .task { await viewModel.load() }
            .onChange(of: showScanner) { _, isShowing in
                if !isShowing {
                    Task { await viewModel.load() }
                }
            }
            .alert("Couldn’t save", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { viewModel.shiftMonth(-1) } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .foregroundStyle(AppColors.primaryGradient)
                    .font(.title2)
            }
            Spacer()
            Text(viewModel.monthTitle)
                .font(.title3.weight(.semibold))
            Spacer()
            Button { viewModel.shiftMonth(1) } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .foregroundStyle(AppColors.primaryGradient)
                    .font(.title2)
            }
        }
        .padding()
        .liquidGlass(cornerRadius: AppRadius.medium)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
    }

    private var calendarGrid: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(viewModel.daysInMonth.enumerated()), id: \.offset) { _, date in
                    if let date {
                        Button {
                            viewModel.selectedDate = date
                            showDayPlanSheet = true
                        } label: {
                            DayCell(
                                date: date,
                                isSelected: Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate),
                                isToday: Calendar.current.isDateInToday(date),
                                hasPlan: viewModel.hasPlan(on: date)
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 44)
                    }
                }
            }
        }
        .padding()
        .liquidGlass(cornerRadius: AppRadius.medium)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large, style: .continuous))
    }

    private var dayPlansSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("This day")
                    .font(AppTypography.headline)
                Spacer()
                Button {
                    showDayPlanSheet = true
                } label: {
                    Label("Plan", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.brand)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppColors.olive)
                        .clipShape(Capsule())
                }
            }

            let dayEvents = viewModel.events(on: viewModel.selectedDate)
            if dayEvents.isEmpty {
                Text("Tap a date to plan what you’ll wear, an event, or a trip.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .liquidGlass(cornerRadius: AppRadius.medium)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(dayEvents) { event in
                        DayPlanRow(event: event)
                    }
                }
            }
        }
    }

    private var plannedLooksSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Planned Looks")
                    .font(AppTypography.headline)
                Spacer()
                Button {
                    showScanner = true
                } label: {
                    Label("Scan", systemImage: "camera.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(AppColors.primaryGradient)
                        .clipShape(Capsule())
                }
            }

            let planned = viewModel.items(on: viewModel.selectedDate)
            if planned.isEmpty {
                Text("No looks planned for this day.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .liquidGlass(cornerRadius: AppRadius.medium)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(planned) { item in
                            StoredWardrobeCardCompact(item: item, storage: viewModel.imageStorage)
                        }
                    }
                }
            }
        }
    }
}

private struct DayPlanRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind.systemImage)
                .font(.title3)
                .foregroundStyle(AppColors.olive)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                if let summary = event.weatherSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                } else if let dress = event.dressCode, !dress.isEmpty {
                    Text(dress)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                } else if let notes = event.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                } else {
                    Text(event.kind.title)
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            Spacer()
        }
        .padding()
        .liquidGlass(cornerRadius: AppRadius.medium)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}

private struct StoredWardrobeCardCompact: View {
    let item: WardrobeItem
    let storage: ImageStorage
    @State private var image: UIImage?

    var body: some View {
        WardrobeItemCard(name: item.name, image: image, width: 140, height: 180)
            .task {
                let path = item.transparentImagePath ?? item.originalImagePath
                image = UIImage(data: (try? await storage.loadImageData(at: path)) ?? Data())
            }
    }
}
