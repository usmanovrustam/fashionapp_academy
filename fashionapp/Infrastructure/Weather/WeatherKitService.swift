import Foundation
import CoreLocation
import WeatherKit

enum LocationError: LocalizedError {
    case denied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .denied: return "Location permission was denied. Enable it in Settings to see local weather."
        case .unavailable: return "Unable to determine your location."
        }
    }
}

@MainActor
final class CoreLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

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
            if let admin = placemarks.first?.administrativeArea {
                return "\(locality), \(admin)"
            }
            return locality
        }
        if let name = placemarks.first?.name {
            return name
        }
        return "Current Location"
    }

    private func requestLocation() async throws -> CLLocation {
        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await waitForAuthorizationDecision()
        }

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .denied, .restricted:
            throw LocationError.denied
        case .notDetermined:
            throw LocationError.unavailable
        @unknown default:
            throw LocationError.unavailable
        }

        if let cached = manager.location,
           Date().timeIntervalSince(cached.timestamp) < 120 {
            return cached
        }

        return try await withCheckedThrowingContinuation { continuation in
            if let existing = self.locationContinuation {
                existing.resume(throwing: CancellationError())
            }
            self.locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func waitForAuthorizationDecision() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            self.authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            authorizationContinuation?.resume(returning: status)
            authorizationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let continuation = locationContinuation else { return }
            locationContinuation = nil
            guard let location = locations.first else {
                continuation.resume(throwing: LocationError.unavailable)
                return
            }
            continuation.resume(returning: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard let continuation = locationContinuation else { return }
            locationContinuation = nil
            continuation.resume(throwing: error)
        }
    }
}

/// Prefers WeatherKit; falls back to Open-Meteo when JWT/App Services aren’t configured.
@MainActor
final class WeatherKitService: WeatherProviding {
    private let locationProvider: LocationProviding
    private let cache: WeatherCacheRepository
    private let weatherService = WeatherService.shared
    private let openMeteo = OpenMeteoWeatherClient()

    /// Last Open-Meteo forecast kept so Discover can show the 3-day strip after fallback.
    private(set) var lastFallbackForecast: [DailyWeatherForecast] = []

    init(locationProvider: LocationProviding, cache: WeatherCacheRepository) {
        self.locationProvider = locationProvider
        self.cache = cache
    }

    func currentWeather() async throws -> WeatherSnapshot {
        if let cached = await cache.cachedSnapshot(),
           Date().timeIntervalSince(cached.fetchedAt) < 15 * 60 {
            return cached
        }

        let coordinate: (latitude: Double, longitude: Double)
        do {
            coordinate = try await locationProvider.currentCoordinate()
        } catch let locationError as LocationError {
            if let cached = await cache.cachedSnapshot() { return cached }
            throw locationError
        } catch {
            if let cached = await cache.cachedSnapshot() { return cached }
            throw LocationError.unavailable
        }

        let locationName = (try? await locationProvider.reverseGeocode(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )) ?? "Current Location"

        do {
            let snapshot = try await fetchWeatherKitSnapshot(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                locationName: locationName
            )
            lastFallbackForecast = []
            try? await cache.save(snapshot)
            return snapshot
        } catch {
            #if DEBUG
            print("WeatherKit failed (\(error.localizedDescription)); falling back to Open-Meteo.")
            #endif
            do {
                let (snapshot, forecast) = try await openMeteo.fetchCurrent(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    locationName: locationName
                )
                lastFallbackForecast = forecast
                try? await cache.save(snapshot)
                return snapshot
            } catch {
                if let cached = await cache.cachedSnapshot() {
                    return cached
                }
                throw DomainError.weatherUnavailable(
                    "Couldn't load local weather. Check your network connection and try again."
                )
            }
        }
    }

    func dailyForecast(days: Int) async throws -> [DailyWeatherForecast] {
        if !lastFallbackForecast.isEmpty {
            return Array(lastFallbackForecast.prefix(max(days, 1)))
        }

        let coordinate = try await locationProvider.currentCoordinate()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        do {
            let weather = try await weatherService.weather(for: location)
            return weather.dailyForecast.prefix(max(days, 1)).map { day in
                DailyWeatherForecast(
                    date: day.date,
                    highCelsius: day.highTemperature.converted(to: .celsius).value,
                    lowCelsius: day.lowTemperature.converted(to: .celsius).value,
                    symbolName: day.symbolName,
                    conditionDescription: Self.displayName(for: day.condition)
                )
            }
        } catch {
            let locationName = (try? await locationProvider.reverseGeocode(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )) ?? "Current Location"
            let (_, forecast) = try await openMeteo.fetchCurrent(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                locationName: locationName
            )
            lastFallbackForecast = forecast
            return Array(forecast.prefix(max(days, 1)))
        }
    }

    private func fetchWeatherKitSnapshot(
        latitude: Double,
        longitude: Double,
        locationName: String
    ) async throws -> WeatherSnapshot {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let weather = try await weatherService.weather(for: location)
        let current = weather.currentWeather
        let day = weather.dailyForecast.first

        return WeatherSnapshot(
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
    }

    private static func displayName(for condition: WeatherCondition) -> String {
        let raw = String(describing: condition)
        let spaced = raw.unicodeScalars.reduce(into: "") { result, scalar in
            if CharacterSet.uppercaseLetters.contains(scalar), !result.isEmpty {
                result += " "
            }
            result += String(scalar)
        }
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}
