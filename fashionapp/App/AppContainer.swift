import Foundation
import SwiftUI

/// Composition root — wires replaceable services for dependency injection.
@MainActor
final class AppContainer: ObservableObject {
    let settings: AppSettingsProviding
    let accountStatus: CloudKitAccountStatusService

    let imageStorage: ImageStorage
    let wardrobeRepository: WardrobeRepository
    let outfitRepository: OutfitRepository
    let profileRepository: UserProfileRepository
    let recommendationRepository: RecommendationRepository
    let weatherCacheRepository: WeatherCacheRepository
    let eventRepository: EventRepository
    let packingListRepository: PackingListRepository

    let locationProvider: LocationProviding
    let weatherProvider: WeatherProviding
    let scanPipeline: ClothingScanPipeline
    let recommender: OutfitRecommending
    let stylingAssistant: StylingAssisting

    let scanAndSaveUseCase: ScanAndSaveClothingUseCase
    let dailyRecommendationsUseCase: GenerateDailyRecommendationsUseCase
    let askAssistantUseCase: AskStylingAssistantUseCase
    let statisticsUseCase: ComputeWardrobeStatisticsUseCase

    init() {
        let store = LocalJSONStore()
        let settings = UserDefaultsAppSettings()
        let imageStorage = FileImageStorage()
        let wardrobeRepository = LocalWardrobeRepository(store: store)
        let outfitRepository = LocalOutfitRepository(store: store)
        let profileRepository = LocalUserProfileRepository(store: store)
        let recommendationRepository = LocalRecommendationRepository(store: store)
        let weatherCacheRepository = LocalWeatherCacheRepository(store: store)
        let eventRepository = LocalEventRepository(store: store)
        let packingListRepository = LocalPackingListRepository(store: store)

        let locationProvider = CoreLocationProvider()
        let weatherProvider = WeatherKitService(
            locationProvider: locationProvider,
            cache: weatherCacheRepository
        )

        let detector = HeuristicClothingDetector()
        let segmenter = U2NetClothingSegmenter()
        let remover = MaskBackgroundRemover()
        let metadata = ColorAwareMetadataExtractor()
        let pipeline = DefaultClothingScanPipeline(
            detector: detector,
            segmenter: segmenter,
            backgroundRemover: remover,
            metadataExtractor: metadata
        )

        let recommender = RuleBasedOutfitRecommender()
        let assistant = LocalStylingAssistant(recommender: recommender)
        let accountStatus = CloudKitAccountStatusService()

        self.settings = settings
        self.accountStatus = accountStatus
        self.imageStorage = imageStorage
        self.wardrobeRepository = wardrobeRepository
        self.outfitRepository = outfitRepository
        self.profileRepository = profileRepository
        self.recommendationRepository = recommendationRepository
        self.weatherCacheRepository = weatherCacheRepository
        self.eventRepository = eventRepository
        self.packingListRepository = packingListRepository
        self.locationProvider = locationProvider
        self.weatherProvider = weatherProvider
        self.scanPipeline = pipeline
        self.recommender = recommender
        self.stylingAssistant = assistant

        self.scanAndSaveUseCase = ScanAndSaveClothingUseCase(
            pipeline: pipeline,
            imageStorage: imageStorage,
            wardrobeRepository: wardrobeRepository
        )
        self.dailyRecommendationsUseCase = GenerateDailyRecommendationsUseCase(
            wardrobeRepository: wardrobeRepository,
            weatherProvider: weatherProvider,
            eventRepository: eventRepository,
            profileRepository: profileRepository,
            recommender: recommender,
            recommendationRepository: recommendationRepository
        )
        self.askAssistantUseCase = AskStylingAssistantUseCase(
            assistant: assistant,
            wardrobeRepository: wardrobeRepository,
            weatherProvider: weatherProvider,
            profileRepository: profileRepository,
            eventRepository: eventRepository
        )
        self.statisticsUseCase = ComputeWardrobeStatisticsUseCase()
    }
}
