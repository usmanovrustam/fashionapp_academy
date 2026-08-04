import Foundation

struct WeatherSnapshot: Codable, Equatable, Hashable {
    var temperatureCelsius: Double
    var apparentTemperatureCelsius: Double
    var humidity: Double
    var windSpeedKmh: Double
    var rainProbability: Double
    var uvIndex: Double
    var airQualityIndex: Double?
    var conditionSymbol: String
    var conditionDescription: String
    var locationName: String
    var fetchedAt: Date

    var temperatureBand: TemperatureBand {
        TemperatureBand.from(celsius: temperatureCelsius)
    }

    var isRainy: Bool { rainProbability >= 0.45 || conditionDescription.lowercased().contains("rain") }
    var isSnowy: Bool { conditionDescription.lowercased().contains("snow") }
}

struct DailyWeatherForecast: Identifiable, Codable, Equatable, Hashable {
    var id: Date { date }
    var date: Date
    var highCelsius: Double
    var lowCelsius: Double
    var symbolName: String
    var conditionDescription: String
}

/// What the user is planning on a calendar day.
enum DayPlanKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case knownOutfit
    case event
    case travel
    case laundry
    /// Legacy values kept for decoding older saved plans (not shown in UI).
    case donate
    case mood
    case shopping
    case note

    var id: String { rawValue }

    /// Choices shown when a day is tapped.
    static var dayOptions: [DayPlanKind] {
        [.knownOutfit, .event, .travel, .laundry, .donate]
    }

    var title: String {
        switch self {
        case .knownOutfit: return NSLocalizedString("Plan set of outfits", comment: "Day plan option")
        case .event: return NSLocalizedString("I have an event", comment: "Day plan option")
        case .travel: return NSLocalizedString("I'm going on a trip", comment: "Day plan option")
        case .laundry: return NSLocalizedString("Laundry", comment: "Day plan option")
        case .donate: return NSLocalizedString("Donate", comment: "Day plan option")
        case .mood: return NSLocalizedString("Mood", comment: "Legacy day plan")
        case .shopping: return NSLocalizedString("Shopping", comment: "Legacy day plan")
        case .note: return NSLocalizedString("Note", comment: "Legacy day plan")
        }
    }

    var subtitle: String {
        switch self {
        case .knownOutfit: return NSLocalizedString("Select wears for a full look — top, bottom, and shoes (or a dress + shoes).", comment: "")
        case .event: return NSLocalizedString("Tell us the occasion so Nook can dress for it.", comment: "")
        case .travel: return NSLocalizedString("Destination, season, and packing suggestions.", comment: "")
        case .laundry: return NSLocalizedString("Mark pieces that need a wash.", comment: "")
        case .donate: return NSLocalizedString("Choose pieces you’re ready to give away.", comment: "")
        case .mood, .shopping, .note: return ""
        }
    }

    var systemImage: String {
        switch self {
        case .knownOutfit: return "tshirt.fill"
        case .event: return "calendar.badge.clock"
        case .travel: return "airplane"
        case .laundry: return "washer.fill"
        case .donate: return "gift.fill"
        case .mood: return "heart.text.square"
        case .shopping: return "bag.fill"
        case .note: return "note.text"
        }
    }
}

/// Common event types when the user picks “I have an event”.
enum DayEventType: String, Codable, CaseIterable, Identifiable, Hashable {
    case wedding
    case work
    case dinner
    case party
    case interview
    case religious
    case family
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wedding: return NSLocalizedString("Wedding", comment: "Event type")
        case .work: return NSLocalizedString("Work / meeting", comment: "Event type")
        case .dinner: return NSLocalizedString("Dinner out", comment: "Event type")
        case .party: return NSLocalizedString("Party", comment: "Event type")
        case .interview: return NSLocalizedString("Interview", comment: "Event type")
        case .religious: return NSLocalizedString("Religious gathering", comment: "Event type")
        case .family: return NSLocalizedString("Family gathering", comment: "Event type")
        case .other: return NSLocalizedString("Other", comment: "Event type")
        }
    }

    var suggestedDressCode: String? {
        switch self {
        case .wedding: return NSLocalizedString("Formal / elegant", comment: "Dress code")
        case .work, .interview: return NSLocalizedString("Smart / business", comment: "Dress code")
        case .dinner: return NSLocalizedString("Smart casual", comment: "Dress code")
        case .party: return NSLocalizedString("Evening out", comment: "Dress code")
        case .religious, .family: return NSLocalizedString("Modest & polished", comment: "Dress code")
        case .other: return nil
        }
    }
}

struct CalendarEvent: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var location: String?
    var dressCode: String?
    var isAllDay: Bool
    /// Day-plan kind. Defaults to `.event` when decoding older documents.
    var kind: DayPlanKind
    var eventType: String?
    var wardrobeItemIDs: [UUID]
    var suggestedItemIDs: [UUID]
    var weatherSummary: String?
    var notes: String?
    var packingListID: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        startDate: Date,
        endDate: Date,
        location: String? = nil,
        dressCode: String? = nil,
        isAllDay: Bool = true,
        kind: DayPlanKind = .event,
        eventType: String? = nil,
        wardrobeItemIDs: [UUID] = [],
        suggestedItemIDs: [UUID] = [],
        weatherSummary: String? = nil,
        notes: String? = nil,
        packingListID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.dressCode = dressCode
        self.isAllDay = isAllDay
        self.kind = kind
        self.eventType = eventType
        self.wardrobeItemIDs = wardrobeItemIDs
        self.suggestedItemIDs = suggestedItemIDs
        self.weatherSummary = weatherSummary
        self.notes = notes
        self.packingListID = packingListID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        dressCode = try container.decodeIfPresent(String.self, forKey: .dressCode)
        isAllDay = try container.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? true
        kind = try container.decodeIfPresent(DayPlanKind.self, forKey: .kind) ?? .event
        eventType = try container.decodeIfPresent(String.self, forKey: .eventType)
        wardrobeItemIDs = try container.decodeIfPresent([UUID].self, forKey: .wardrobeItemIDs) ?? []
        suggestedItemIDs = try container.decodeIfPresent([UUID].self, forKey: .suggestedItemIDs) ?? []
        weatherSummary = try container.decodeIfPresent(String.self, forKey: .weatherSummary)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        packingListID = try container.decodeIfPresent(UUID.self, forKey: .packingListID)
    }
}

struct WardrobeStatistics: Codable, Equatable, Hashable {
    var totalItems: Int
    var favoritesCount: Int
    var wornThisWeek: Int
    var categoryCounts: [ClothingCategory: Int]
    var mostWornItemID: UUID?
    var leastWornItemID: UUID?
    var averageFormality: Double
}
