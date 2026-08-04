import SwiftUI

struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasPlan: Bool
    var compact: Bool = false

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }()

    private var cellSize: CGFloat { compact ? 28 : 30 }
    private var dotSize: CGFloat { compact ? 4 : 5 }

    var body: some View {
        VStack(spacing: compact ? 2 : 3) {
            Text(Self.dayFormatter.string(from: date))
                .font(.system(compact ? .footnote : .subheadline, design: .rounded).weight(isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .frame(width: cellSize, height: cellSize)
                .background {
                    if isSelected {
                        Circle().fill(AppColors.primaryGradient)
                    } else {
                        Circle().fill(Color.clear)
                    }
                }
                .overlay(
                    Circle()
                        .stroke(AppColors.brand.opacity(isToday && !isSelected ? 1 : 0), lineWidth: 1.5)
                )

            Circle()
                .fill(AppColors.brand)
                .frame(width: dotSize, height: dotSize)
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
    @Published var packingListsByID: [UUID: PackingList] = [:]
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

    func events(on date: Date) -> [CalendarEvent] {
        events.filter { event in
            let start = calendar.startOfDay(for: event.startDate)
            let end = calendar.startOfDay(for: event.endDate)
            let day = calendar.startOfDay(for: date)
            return day >= start && day <= end
        }
    }

    func wardrobeItems(for event: CalendarEvent) -> [WardrobeItem] {
        let ids = Set(event.wardrobeItemIDs + event.suggestedItemIDs)
        guard !ids.isEmpty else { return [] }
        return items.filter { ids.contains($0.id) }
    }

    func hasPlan(on date: Date) -> Bool {
        !events(on: date).isEmpty
    }

    /// Sunday-start week containing `date` (matches the S–S grid).
    func weekDays(containing date: Date) -> [Date] {
        let weekday = calendar.component(.weekday, from: date)
        let start = calendar.date(byAdding: .day, value: -(weekday - 1), to: calendar.startOfDay(for: date))
            ?? calendar.startOfDay(for: date)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
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
        let lists = (try? await packingListRepository.fetchAll()) ?? []
        packingListsByID = Dictionary(uniqueKeysWithValues: lists.map { ($0.id, $0) })
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
            if var packingList {
                if let existing = packingListsByID[packingList.id] {
                    packingList.packedItemIDs = existing.packedItemIDs.filter { packingList.itemIDs.contains($0) }
                }
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

    func togglePacked(event: CalendarEvent, itemID: UUID) async {
        guard let listID = event.packingListID, var list = packingListsByID[listID] else { return }
        if list.packedItemIDs.contains(itemID) {
            list.packedItemIDs.removeAll { $0 == itemID }
        } else {
            list.packedItemIDs.append(itemID)
        }
        do {
            try await packingListRepository.save(list)
            packingListsByID[listID] = list
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a plan and undoes linked wardrobe side effects where appropriate.
    func deleteDayPlan(_ event: CalendarEvent) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            var wardrobeUpdates = wardrobeItems(for: event)
            let now = Date()
            for index in wardrobeUpdates.indices {
                switch event.kind {
                case .knownOutfit:
                    if let planned = wardrobeUpdates[index].plannedDate,
                       calendar.isDate(planned, inSameDayAs: event.startDate) {
                        wardrobeUpdates[index].plannedDate = nil
                    }
                case .laundry:
                    wardrobeUpdates[index].isInLaundry = false
                case .donate:
                    wardrobeUpdates[index].isListedForDonate = false
                    wardrobeUpdates[index].listedForDonateAt = nil
                default:
                    break
                }
                wardrobeUpdates[index].updatedAt = now
            }

            for item in wardrobeUpdates {
                try await wardrobeRepository.save(item)
            }
            if let packingID = event.packingListID {
                try? await packingListRepository.delete(id: packingID)
            }
            try await eventRepository.delete(id: event.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Clears need-to-wash on laundry pieces and removes the laundry plan.
    func markLaundryWashed(_ event: CalendarEvent) async {
        guard event.kind == .laundry else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            var wardrobeUpdates = wardrobeItems(for: event)
            let now = Date()
            for index in wardrobeUpdates.indices {
                wardrobeUpdates[index].isInLaundry = false
                wardrobeUpdates[index].updatedAt = now
            }
            for item in wardrobeUpdates {
                try await wardrobeRepository.save(item)
            }
            try await eventRepository.delete(id: event.id)
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

private enum CalendarSheet: Identifiable, Equatable {
    case daySummary
    case addPlan
    case editPlan(CalendarEvent)

    var id: String {
        switch self {
        case .daySummary: return "summary"
        case .addPlan: return "add"
        case .editPlan(let event): return "edit-\(event.id.uuidString)"
        }
    }
}

struct CalendarFeatureView: View {
    private let container: AppContainer
    @StateObject private var viewModel: CalendarViewModel
    @State private var activeSheet: CalendarSheet?
    @State private var showScanner = false
    @State private var isCalendarCollapsed = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let collapseThreshold: CGFloat = 36

    init(container: AppContainer) {
        self.container = container
        _viewModel = StateObject(wrappedValue: CalendarViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.md) {
                    calendarSliver
                    dayPlansSection
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.sm)
                .padding(.bottom, AppSpacing.lg)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: CalendarScrollOffsetKey.self,
                            value: geo.frame(in: .named("calendarScroll")).minY
                        )
                    }
                }
            }
            .coordinateSpace(name: "calendarScroll")
            .onPreferenceChange(CalendarScrollOffsetKey.self) { minY in
                // Scroll down → content moves up (minY decreases) → collapse calendar.
                let shouldCollapse = minY < -collapseThreshold
                if shouldCollapse != isCalendarCollapsed {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        isCalendarCollapsed = shouldCollapse
                    }
                }
            }
            .nookSafeScreenInsets()
            .nookScreenBackground()
            .navigationTitle(NSLocalizedString("Calendar", comment: ""))
            .sheet(isPresented: $showScanner) {
                ScannerFeatureView(container: container)
            }
            .onChange(of: showScanner) { _, isShowing in
                if !isShowing {
                    Task { await viewModel.load() }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .daySummary:
                    DaySummarySheetView(
                        date: viewModel.selectedDate,
                        events: viewModel.events(on: viewModel.selectedDate),
                        wardrobeItems: viewModel.items,
                        packingListsByID: $viewModel.packingListsByID,
                        onAdd: {
                            activeSheet = .addPlan
                        },
                        onEdit: { event in
                            activeSheet = .editPlan(event)
                        },
                        onDelete: { event in
                            activeSheet = nil
                            Task { await viewModel.deleteDayPlan(event) }
                        },
                        onMarkWashed: { event in
                            activeSheet = nil
                            Task { await viewModel.markLaundryWashed(event) }
                        },
                        onTogglePacked: { event, itemID in
                            Task { await viewModel.togglePacked(event: event, itemID: itemID) }
                        },
                        onClose: { activeSheet = nil }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                case .addPlan:
                    DayPlanSheetView(
                        date: viewModel.selectedDate,
                        wardrobeItems: viewModel.items,
                        imageStorage: viewModel.imageStorage,
                        onSave: { event, packing, wardrobeUpdates in
                            activeSheet = nil
                            Task {
                                await viewModel.saveDayPlan(
                                    event: event,
                                    packingList: packing,
                                    wardrobeUpdates: wardrobeUpdates
                                )
                            }
                        },
                        onCancel: {
                            activeSheet = .daySummary
                        },
                        onScanWardrobe: {
                            activeSheet = nil
                            showScanner = true
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                case .editPlan(let event):
                    DayPlanSheetView(
                        date: viewModel.selectedDate,
                        wardrobeItems: viewModel.items,
                        imageStorage: viewModel.imageStorage,
                        existingEvent: event,
                        onSave: { updated, packing, wardrobeUpdates in
                            activeSheet = nil
                            Task {
                                await viewModel.saveDayPlan(
                                    event: updated,
                                    packingList: packing,
                                    wardrobeUpdates: wardrobeUpdates
                                )
                            }
                        },
                        onCancel: { activeSheet = .daySummary },
                        onScanWardrobe: {
                            activeSheet = nil
                            showScanner = true
                        }
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }
            .task { await viewModel.load() }
            .alert(NSLocalizedString("Couldn’t update", comment: ""), isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button(NSLocalizedString("OK", comment: ""), role: .cancel) { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var calendarSliver: some View {
        VStack(spacing: 8) {
            monthHeader
            if isCalendarCollapsed {
                weekStrip
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                calendarGrid
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 10) {
            Button { viewModel.shiftMonth(-1) } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .foregroundStyle(AppColors.primaryGradient)
                    .font(.title3)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isCalendarCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.monthTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Image(systemName: isCalendarCollapsed ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textTertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCalendarCollapsed
                ? NSLocalizedString("Expand calendar", comment: "")
                : NSLocalizedString("Collapse calendar", comment: ""))
            Spacer()
            Button { viewModel.shiftMonth(1) } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .foregroundStyle(AppColors.primaryGradient)
                    .font(.title3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: AppRadius.medium)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    private var weekStrip: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(Calendar.current.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(viewModel.weekDays(containing: viewModel.selectedDate), id: \.self) { date in
                    Button {
                        viewModel.selectedDate = date
                        activeSheet = .daySummary
                    } label: {
                        DayCell(
                            date: date,
                            isSelected: Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate),
                            isToday: Calendar.current.isDateInToday(date),
                            hasPlan: viewModel.hasPlan(on: date),
                            compact: true
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .liquidGlass(cornerRadius: AppRadius.medium)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    private var calendarGrid: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(Calendar.current.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, day in
                    Text(day)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(viewModel.daysInMonth.enumerated()), id: \.offset) { _, date in
                    if let date {
                        Button {
                            viewModel.selectedDate = date
                            activeSheet = .daySummary
                        } label: {
                            DayCell(
                                date: date,
                                isSelected: Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate),
                                isToday: Calendar.current.isDateInToday(date),
                                hasPlan: viewModel.hasPlan(on: date),
                                compact: true
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 36)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: AppRadius.medium)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }

    private var dayPlansSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(NSLocalizedString("This day", comment: ""))
                    .font(AppTypography.headline)
                Spacer()
                Button {
                    activeSheet = .daySummary
                } label: {
                    Label(NSLocalizedString("Open", comment: ""), systemImage: "calendar")
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
                Text(NSLocalizedString("Tap a date to review plans or add an outfit, event, trip, laundry, or donate.", comment: ""))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .liquidGlass(cornerRadius: AppRadius.medium)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(dayEvents) { event in
                        Button {
                            activeSheet = .editPlan(event)
                        } label: {
                            DayPlanRow(
                                event: event,
                                linkedItems: viewModel.wardrobeItems(for: event)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                activeSheet = .editPlan(event)
                            } label: {
                                Label(NSLocalizedString("Edit", comment: ""), systemImage: "pencil")
                            }
                            if event.kind == .laundry {
                                Button {
                                    Task { await viewModel.markLaundryWashed(event) }
                                } label: {
                                    Label(NSLocalizedString("Mark washed", comment: ""), systemImage: "checkmark.circle")
                                }
                            }
                            Button(role: .destructive) {
                                Task { await viewModel.deleteDayPlan(event) }
                            } label: {
                                Label(NSLocalizedString("Delete", comment: ""), systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct CalendarScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct DayPlanRow: View {
    let event: CalendarEvent
    let linkedItems: [WardrobeItem]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: event.kind.systemImage)
                .font(.title3)
                .foregroundStyle(AppColors.olive)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
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

                if !linkedItems.isEmpty {
                    Text(linkedItems.map(\.name).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.textTertiary)
        }
        .padding()
        .liquidGlass(cornerRadius: AppRadius.medium)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}
