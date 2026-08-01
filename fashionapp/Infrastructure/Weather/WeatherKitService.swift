import Foundation
import CoreLocation
import WeatherKit

enum LocationError: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied: return "Location permission was denied."
        case .unavailable: return "Unable to determine your location."
        }
    }
}

@MainActor
final class CoreLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentCoordinate() async throws -> (latitude: Double, longitude: Double) {
        let location = try await requestLocation()
        return (location.coordinate.latitude, location.coordinate.longitude)
    }

    func reverseGeocode(latitude: Double, longitude: Double) async throws -> String {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        if let locality = placemarks.first?.locality {
            return locality
        }
        if let name = placemarks.first?.name {
            return name
        }
        return "Current Location"
    }

    private func requestLocation() async throws -> CLLocation {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }

        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw LocationError.denied
        default:
            break
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.first else {
                continuation?.resume(throwing: LocationError.unavailable)
                continuation = nil
                return
            }
            continuation?.resume(returning: location)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

@MainActor
final class WeatherKitService: WeatherProviding {
    private let locationProvider: LocationProviding
    private let cache: WeatherCacheRepository
    private let weatherService = WeatherService.shared

    init(locationProvider: LocationProviding, cache: WeatherCacheRepository) {
        self.locationProvider = locationProvider
        self.cache = cache
    }

    func currentWeather() async throws -> WeatherSnapshot {
        if let cached = await cache.cachedSnapshot(),
           Date().timeIntervalSince(cached.fetchedAt) < 15 * 60 {
            return cached
        }

        do {
            let coordinate = try await locationProvider.currentCoordinate()
            let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            let weather = try await weatherService.weather(for: location)
            let current = weather.currentWeather
            let day = weather.dailyForecast.first
            let locationName = (try? await locationProvider.reverseGeocode(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )) ?? "Current Location"

            let snapshot = WeatherSnapshot(
                temperatureCelsius: current.temperature.converted(to: .celsius).value,
                apparentTemperatureCelsius: current.apparentTemperature.converted(to: .celsius).value,
                humidity: current.humidity,
                windSpeedKmh: current.wind.speed.converted(to: .kilometersPerHour).value,
                rainProbability: day?.precipitationChance ?? 0,
                uvIndex: Double(current.uvIndex.value),
                airQualityIndex: nil,
                conditionSymbol: current.symbolName,
                conditionDescription: Self.displayName(for: current.condition),
                locationName: locationName,
                fetchedAt: Date()
            )
            try await cache.save(snapshot)
            return snapshot
        } catch {
            if let cached = await cache.cachedSnapshot() {
                return cached
            }
            throw DomainError.weatherUnavailable(error.localizedDescription)
        }
    }

    func dailyForecast(days: Int) async throws -> [DailyWeatherForecast] {
        let coordinate = try await locationProvider.currentCoordinate()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let weather = try await weatherService.weather(for: location)
        return weather.dailyForecast.prefix(days).map { day in
            DailyWeatherForecast(
                date: day.date,
                highCelsius: day.highTemperature.converted(to: .celsius).value,
                lowCelsius: day.lowTemperature.converted(to: .celsius).value,
                symbolName: day.symbolName,
                conditionDescription: Self.displayName(for: day.condition)
            )
        }
    }

    private static func displayName(for condition: WeatherCondition) -> String {
        let raw = String(describing: condition)
        // Convert camelCase enum name to words: "partlyCloudy" → "Partly Cloudy"
        let spaced = raw.unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar), !result.isEmpty {
                result += " "
            }
            result += String(scalar)
        }
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
