import Foundation

/// Free location-based weather fallback when WeatherKit JWT auth isn’t available.
/// https://open-meteo.com/
actor OpenMeteoWeatherClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchCurrent(
        latitude: Double,
        longitude: Double,
        locationName: String
    ) async throws -> (WeatherSnapshot, [DailyWeatherForecast]) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(
                name: "current",
                value: [
                    "temperature_2m",
                    "relative_humidity_2m",
                    "apparent_temperature",
                    "precipitation_probability",
                    "weather_code",
                    "wind_speed_10m",
                    "uv_index"
                ].joined(separator: ",")
            ),
            URLQueryItem(
                name: "daily",
                value: [
                    "weather_code",
                    "temperature_2m_max",
                    "temperature_2m_min",
                    "precipitation_probability_max"
                ].joined(separator: ",")
            ),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "3"),
            URLQueryItem(name: "wind_speed_unit", value: "kmh")
        ]

        guard let url = components.url else {
            throw DomainError.weatherUnavailable("Invalid weather request.")
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw DomainError.weatherUnavailable("Weather service returned an error.")
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        guard let current = decoded.current else {
            throw DomainError.weatherUnavailable("Weather response was incomplete.")
        }

        let code = current.weatherCode ?? 0
        let mapping = Self.mapWeatherCode(code)
        let humidity = (current.relativeHumidity2m ?? 0) / 100.0
        let rain = (current.precipitationProbability ?? decoded.daily?.precipitationProbabilityMax?.first ?? 0) / 100.0

        let snapshot = WeatherSnapshot(
            temperatureCelsius: current.temperature2m ?? 0,
            apparentTemperatureCelsius: current.apparentTemperature ?? current.temperature2m ?? 0,
            humidity: min(max(humidity, 0), 1),
            windSpeedKmh: current.windSpeed10m ?? 0,
            rainProbability: min(max(rain, 0), 1),
            uvIndex: current.uvIndex ?? 0,
            airQualityIndex: nil,
            conditionSymbol: mapping.symbol,
            conditionDescription: mapping.description,
            locationName: locationName,
            fetchedAt: Date()
        )

        let forecast = Self.makeForecast(from: decoded.daily)
        return (snapshot, forecast)
    }

    private static func makeForecast(from daily: OpenMeteoDaily?) -> [DailyWeatherForecast] {
        guard
            let daily,
            let times = daily.time,
            let highs = daily.temperature2mMax,
            let lows = daily.temperature2mMin
        else { return [] }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"

        return times.indices.compactMap { index -> DailyWeatherForecast? in
            guard
                index < highs.count,
                index < lows.count,
                let date = formatter.date(from: times[index])
            else { return nil }

            let code = daily.weatherCode?[safe: index] ?? 0
            let mapping = mapWeatherCode(code)
            return DailyWeatherForecast(
                date: date,
                highCelsius: highs[index],
                lowCelsius: lows[index],
                symbolName: mapping.symbol,
                conditionDescription: mapping.description
            )
        }
    }

    private static func mapWeatherCode(_ code: Int) -> (symbol: String, description: String) {
        switch code {
        case 0:
            return ("sun.max.fill", "Clear")
        case 1:
            return ("sun.max.fill", "Mainly Clear")
        case 2:
            return ("cloud.sun.fill", "Partly Cloudy")
        case 3:
            return ("cloud.fill", "Overcast")
        case 45, 48:
            return ("cloud.fog.fill", "Fog")
        case 51, 53, 55, 56, 57:
            return ("cloud.drizzle.fill", "Drizzle")
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return ("cloud.rain.fill", "Rain")
        case 71, 73, 75, 77, 85, 86:
            return ("cloud.snow.fill", "Snow")
        case 95, 96, 99:
            return ("cloud.bolt.rain.fill", "Thunderstorm")
        default:
            return ("cloud.fill", "Cloudy")
        }
    }
}

private struct OpenMeteoResponse: Decodable {
    let current: OpenMeteoCurrent?
    let daily: OpenMeteoDaily?
}

private struct OpenMeteoCurrent: Decodable {
    let temperature2m: Double?
    let relativeHumidity2m: Double?
    let apparentTemperature: Double?
    let precipitationProbability: Double?
    let weatherCode: Int?
    let windSpeed10m: Double?
    let uvIndex: Double?

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
        case relativeHumidity2m = "relative_humidity_2m"
        case apparentTemperature = "apparent_temperature"
        case precipitationProbability = "precipitation_probability"
        case weatherCode = "weather_code"
        case windSpeed10m = "wind_speed_10m"
        case uvIndex = "uv_index"
    }
}

private struct OpenMeteoDaily: Decodable {
    let time: [String]?
    let weatherCode: [Int]?
    let temperature2mMax: [Double]?
    let temperature2mMin: [Double]?
    let precipitationProbabilityMax: [Double]?

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperature2mMax = "temperature_2m_max"
        case temperature2mMin = "temperature_2m_min"
        case precipitationProbabilityMax = "precipitation_probability_max"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
