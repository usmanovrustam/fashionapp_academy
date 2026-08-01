import SwiftUI
import UIKit

/// Sheet shown when the user taps a calendar day.
struct DayPlanSheetView: View {
    enum Step: Equatable {
        case chooseKind
        case knownOutfit
        case eventDetails
        case travelDetails
        case laundry
        case donate
    }

    let date: Date
    let wardrobeItems: [WardrobeItem]
    let imageStorage: ImageStorage
    let onSave: (CalendarEvent, PackingList?, [WardrobeItem]) -> Void
    let onCancel: () -> Void

    @State private var step: Step = .chooseKind
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var eventType: DayEventType = .work
    @State private var customEventNote = ""
    @State private var destination = ""
    @State private var tripEndDate: Date
    @State private var travelPlace: GeocodedPlace?
    @State private var travelAnalysis: TravelPackingAdvisor.Result?
    @State private var packingTips: [String] = []
    @State private var suggestedIDs: Set<UUID> = []
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let weatherClient = OpenMeteoWeatherClient()
    private let calendar = Calendar.current

    init(
        date: Date,
        wardrobeItems: [WardrobeItem],
        imageStorage: ImageStorage,
        onSave: @escaping (CalendarEvent, PackingList?, [WardrobeItem]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.date = date
        self.wardrobeItems = wardrobeItems
        self.imageStorage = imageStorage
        self.onSave = onSave
        self.onCancel = onCancel
        let defaultEnd = Calendar.current.date(byAdding: .day, value: 3, to: date) ?? date
        _tripEndDate = State(initialValue: defaultEnd)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .chooseKind:
                    kindList
                case .knownOutfit:
                    itemPickerForm(
                        title: "Select what you’re wearing",
                        emptyMessage: "Your wardrobe is empty. Scan a piece first, then come back.",
                        items: wardrobeItems.filter(\.isAvailableToWear),
                        saveTitle: "Save to calendar",
                        onSave: saveKnownOutfit
                    )
                case .eventDetails:
                    eventForm
                case .travelDetails:
                    travelForm
                case .laundry:
                    itemPickerForm(
                        title: "Mark what needs a wash",
                        emptyMessage: "Nothing left to mark — everything is already in laundry.",
                        items: wardrobeItems.filter { !$0.isInLaundry },
                        saveTitle: "Mark as need to wash",
                        onSave: saveLaundry
                    )
                case .donate:
                    itemPickerForm(
                        title: "Choose pieces to donate",
                        emptyMessage: "No pieces available to mark for donate right now.",
                        items: wardrobeItems.filter { !$0.isListedForDonate },
                        saveTitle: "Mark for donate",
                        onSave: saveDonate
                    )
                }
            }
            .nookScreenBackground()
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(step == .chooseKind ? "Close" : "Back") {
                        handleBack()
                    }
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var navigationTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }

    private func handleBack() {
        switch step {
        case .chooseKind:
            onCancel()
        case .knownOutfit, .eventDetails, .travelDetails, .laundry, .donate:
            selectedItemIDs = []
            step = .chooseKind
        }
    }

    // MARK: - Kind picker

    private var kindList: some View {
        ScrollView {
            VStack(spacing: AppSpacing.md) {
                Text("What do you have this day?")
                    .font(AppTypography.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, AppSpacing.sm)

                ForEach(DayPlanKind.dayOptions) { kind in
                    Button {
                        open(kind)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: kind.systemImage)
                                .font(.title3)
                                .foregroundStyle(AppColors.olive)
                                .frame(width: 36)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(kind.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(AppColors.textPrimary)
                                Text(kind.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .multilineTextAlignment(.leading)
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
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
    }

    private func open(_ kind: DayPlanKind) {
        selectedItemIDs = []
        switch kind {
        case .knownOutfit: step = .knownOutfit
        case .event: step = .eventDetails
        case .travel: step = .travelDetails
        case .laundry: step = .laundry
        case .donate: step = .donate
        case .mood, .shopping, .note: break
        }
    }

    // MARK: - Shared item picker

    private func itemPickerForm(
        title: String,
        emptyMessage: String,
        items: [WardrobeItem],
        saveTitle: String,
        onSave: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(AppTypography.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

            if items.isEmpty {
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(items) { item in
                            SelectableWardrobeCell(
                                item: item,
                                storage: imageStorage,
                                isSelected: selectedItemIDs.contains(item.id)
                            ) {
                                if selectedItemIDs.contains(item.id) {
                                    selectedItemIDs.remove(item.id)
                                } else {
                                    selectedItemIDs.insert(item.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 100)
                }
            }

            saveBar(title: saveTitle, enabled: !selectedItemIDs.isEmpty, action: onSave)
        }
    }

    private func saveKnownOutfit() {
        let ids = Array(selectedItemIDs)
        let names = wardrobeItems.filter { ids.contains($0.id) }.map(\.name)
        let title = names.isEmpty
            ? "Planned look"
            : names.prefix(2).joined(separator: " · ")

        var updatedItems = wardrobeItems.filter { ids.contains($0.id) }
        for index in updatedItems.indices {
            updatedItems[index].plannedDate = calendar.startOfDay(for: date)
            updatedItems[index].updatedAt = Date()
        }

        let event = CalendarEvent(
            title: title,
            startDate: calendar.startOfDay(for: date),
            endDate: calendar.startOfDay(for: date),
            isAllDay: true,
            kind: .knownOutfit,
            wardrobeItemIDs: ids
        )
        onSave(event, nil, updatedItems)
    }

    private func saveLaundry() {
        let ids = Array(selectedItemIDs)
        var updatedItems = wardrobeItems.filter { ids.contains($0.id) }
        for index in updatedItems.indices {
            updatedItems[index].isInLaundry = true
            updatedItems[index].updatedAt = Date()
        }

        let event = CalendarEvent(
            title: "Laundry",
            startDate: calendar.startOfDay(for: date),
            endDate: calendar.startOfDay(for: date),
            isAllDay: true,
            kind: .laundry,
            wardrobeItemIDs: ids,
            notes: "\(ids.count) piece(s) marked as need to wash"
        )
        onSave(event, nil, updatedItems)
    }

    private func saveDonate() {
        let ids = Array(selectedItemIDs)
        let now = Date()
        var updatedItems = wardrobeItems.filter { ids.contains($0.id) }
        for index in updatedItems.indices {
            updatedItems[index].isListedForDonate = true
            updatedItems[index].listedForDonateAt = calendar.startOfDay(for: date)
            updatedItems[index].isInLaundry = false
            updatedItems[index].updatedAt = now
        }

        let event = CalendarEvent(
            title: "Donate",
            startDate: calendar.startOfDay(for: date),
            endDate: calendar.startOfDay(for: date),
            isAllDay: true,
            kind: .donate,
            wardrobeItemIDs: ids,
            notes: "\(ids.count) piece(s) listed in the giveaway store"
        )
        onSave(event, nil, updatedItems)
    }

    // MARK: - Event

    private var eventForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("What type of event?")
                        .font(AppTypography.headline)

                    ForEach(DayEventType.allCases) { type in
                        Button {
                            eventType = type
                        } label: {
                            HStack {
                                Text(type.displayName)
                                    .foregroundStyle(AppColors.textPrimary)
                                Spacer()
                                if eventType == type {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(AppColors.olive)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                                    .fill(eventType == type ? AppColors.brand.opacity(0.45) : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                                    .stroke(AppColors.olive.opacity(eventType == type ? 0.5 : 0.12), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    TextField("Optional note (dress code, venue…)", text: $customEventNote, axis: .vertical)
                        .lineLimit(2...4)
                        .padding()
                        .liquidGlass(cornerRadius: AppRadius.medium)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                }
                .padding()
                .padding(.bottom, 100)
            }

            saveBar(title: "Save to calendar", enabled: true) {
                saveEvent()
            }
        }
    }

    private func saveEvent() {
        let dress = customEventNote.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? eventType.suggestedDressCode
        let event = CalendarEvent(
            title: eventType.displayName,
            startDate: calendar.startOfDay(for: date),
            endDate: calendar.startOfDay(for: date),
            dressCode: dress,
            isAllDay: true,
            kind: .event,
            eventType: eventType.rawValue,
            notes: customEventNote.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        onSave(event, nil, [])
    }

    // MARK: - Travel

    private var travelForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("Where are you going?")
                        .font(AppTypography.headline)

                    TextField("City or place", text: $destination)
                        .textInputAutocapitalization(.words)
                        .padding()
                        .liquidGlass(cornerRadius: AppRadius.medium)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                    DatePicker(
                        "Trip ends",
                        selection: $tripEndDate,
                        in: date...,
                        displayedComponents: .date
                    )
                    .padding()
                    .liquidGlass(cornerRadius: AppRadius.medium)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                    Button {
                        Task { await analyzeTravel() }
                    } label: {
                        HStack {
                            if isWorking {
                                ProgressView().tint(AppColors.brand)
                            }
                            Text(isWorking ? "Checking weather…" : "Analyze season & weather")
                                .font(.body.weight(.semibold))
                        }
                        .foregroundStyle(AppColors.brand)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppColors.olive)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
                    }
                    .disabled(destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)

                    if let place = travelPlace {
                        Text(place.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.olive)
                    }

                    if let analysis = travelAnalysis {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(analysis.weatherSummary)
                                .font(.subheadline.weight(.semibold))
                            ForEach(analysis.packingTips, id: \.self) { tip in
                                Label(tip, systemImage: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        .padding()
                        .liquidGlass(cornerRadius: AppRadius.medium)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))

                        Text("Suggested outfits to take")
                            .font(AppTypography.headline)
                            .padding(.top, 8)

                        if analysis.suggestedItems.isEmpty {
                            Text("No strong wardrobe matches yet — add more pieces for better packing lists.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(analysis.suggestedItems) { item in
                                    SelectableWardrobeCell(
                                        item: item,
                                        storage: imageStorage,
                                        isSelected: suggestedIDs.contains(item.id)
                                    ) {
                                        if suggestedIDs.contains(item.id) {
                                            suggestedIDs.remove(item.id)
                                        } else {
                                            suggestedIDs.insert(item.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
                .padding(.bottom, 100)
            }

            saveBar(title: "Save to calendar", enabled: travelPlace != nil) {
                saveTravel()
            }
        }
    }

    @MainActor
    private func analyzeTravel() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        do {
            let place = try await weatherClient.geocode(destination: destination)
            travelPlace = place

            let daySpan = max(
                1,
                calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: tripEndDate)).day ?? 1
            ) + 1
            let daysFromNow = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: Date()),
                to: calendar.startOfDay(for: tripEndDate)
            ).day ?? daySpan
            let forecastDays = min(16, max(daySpan, daysFromNow + 1, 3))

            let forecasts = try await weatherClient.fetchDestinationForecast(
                latitude: place.latitude,
                longitude: place.longitude,
                locationName: place.displayName,
                forecastDays: forecastDays
            )

            let analysis = TravelPackingAdvisor.analyze(
                wardrobe: wardrobeItems,
                forecasts: forecasts,
                tripStart: date,
                tripEnd: tripEndDate,
                destinationName: place.displayName
            )
            travelAnalysis = analysis
            packingTips = analysis.packingTips
            suggestedIDs = Set(analysis.suggestedItems.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveTravel() {
        let placeName = travelPlace?.displayName
            ?? destination.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = Array(suggestedIDs)
        let packing = PackingList(
            id: UUID(),
            title: "Trip to \(placeName)",
            destination: placeName,
            startDate: calendar.startOfDay(for: date),
            endDate: calendar.startOfDay(for: tripEndDate),
            itemIDs: ids,
            createdAt: Date()
        )
        let event = CalendarEvent(
            title: "Trip · \(placeName)",
            startDate: calendar.startOfDay(for: date),
            endDate: calendar.startOfDay(for: tripEndDate),
            location: placeName,
            isAllDay: true,
            kind: .travel,
            wardrobeItemIDs: ids,
            suggestedItemIDs: ids,
            weatherSummary: travelAnalysis?.weatherSummary,
            notes: packingTips.joined(separator: "\n"),
            packingListID: packing.id
        )
        onSave(event, packing, [])
    }

    // MARK: - Save bar

    private func saveBar(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(AppColors.brand)
                .frame(maxWidth: .infinity)
                .padding()
                .background(enabled ? AppColors.olive : AppColors.olive.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
        }
        .disabled(!enabled)
        .padding()
        .background(Color.white.opacity(0.95))
    }
}

private struct SelectableWardrobeCell: View {
    let item: WardrobeItem
    let storage: ImageStorage
    let isSelected: Bool
    let onTap: () -> Void

    @State private var image: UIImage?

    var body: some View {
        Button(action: onTap) {
            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    WardrobeItemCard(
                        name: item.name,
                        image: image,
                        width: geo.size.width,
                        height: geo.size.height
                    )

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? AppColors.olive : .white)
                        .shadow(radius: 2)
                        .padding(10)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xLarge, style: .continuous)
                        .stroke(isSelected ? AppColors.olive : Color.clear, lineWidth: 3)
                )
            }
            .frame(height: 180)
        }
        .buttonStyle(.plain)
        .task {
            let path = item.transparentImagePath ?? item.originalImagePath
            image = UIImage(data: (try? await storage.loadImageData(at: path)) ?? Data())
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
