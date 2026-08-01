import Foundation

struct DailyRecommendationsResult {
    let recommendations: [OutfitRecommendation]
    let wardrobeItems: [WardrobeItem]
    let weather: WeatherSnapshot?
}

struct GenerateDailyRecommendationsUseCase {
    let wardrobeRepository: WardrobeRepository
    let weatherProvider: WeatherProviding
    let eventRepository: EventRepository
    let profileRepository: UserProfileRepository
    let recommender: OutfitRecommending
    let recommendationRepository: RecommendationRepository

    /// Pass `prefetchedWeather` to avoid a second WeatherKit round-trip from the caller.
    func execute(limit: Int = 6, prefetchedWeather: WeatherSnapshot? = nil) async throws -> DailyRecommendationsResult {
        async let wardrobe = wardrobeRepository.fetchAll()
        async let profile = profileRepository.load()
        async let events = eventRepository.fetchEvents(
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        )

        let weather: WeatherSnapshot?
        if let prefetchedWeather {
            weather = prefetchedWeather
        } else {
            do {
                weather = try await weatherProvider.currentWeather()
            } catch {
                weather = nil
            }
        }

        let items = try await wardrobe
        let user = try await profile
        let dayEvents = try await events
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let isWeekend = weekday == 1 || weekday == 7

        let context = RecommendationContext(
            weather: weather,
            timeOfDay: Date(),
            isWeekend: isWeekend,
            preferredOccasions: isWeekend ? [.casual, .date, .travel] : [.office, .business, .casual],
            events: dayEvents,
            user: user
        )

        let recommendations = try await recommender.recommend(
            from: items,
            context: context,
            limit: limit
        )
        try await recommendationRepository.save(recommendations)
        return DailyRecommendationsResult(
            recommendations: recommendations,
            wardrobeItems: items,
            weather: weather
        )
    }
}

struct AskStylingAssistantUseCase {
    let assistant: StylingAssisting
    let wardrobeRepository: WardrobeRepository
    let weatherProvider: WeatherProviding
    let profileRepository: UserProfileRepository
    let eventRepository: EventRepository

    func execute(message: String, history: [ChatMessage]) async throws -> StylingAssistantResponse {
        async let wardrobe = wardrobeRepository.fetchAll()
        async let profile = profileRepository.load()
        async let events = eventRepository.fetchEvents(
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        )

        var weather: WeatherSnapshot?
        do { weather = try await weatherProvider.currentWeather() } catch { weather = nil }

        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())

        let context = RecommendationContext(
            weather: weather,
            timeOfDay: Date(),
            isWeekend: weekday == 1 || weekday == 7,
            preferredOccasions: [.casual, .office, .date],
            events: try await events,
            user: try await profile
        )

        return try await assistant.respond(
            to: message,
            history: history,
            wardrobe: try await wardrobe,
            context: context
        )
    }
}
