import SwiftUI

@MainActor
final class AssistantViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = [
        .assistant("Hi — I'm your AI stylist. Ask me what to wear for a meeting, dinner, cold weather, or a black-only look.")
    ]
    @Published var input = ""
    @Published var isThinking = false
    @Published var latestRecommendations: [OutfitRecommendation] = []

    private let askUseCase: AskStylingAssistantUseCase
    private let analytics: AnalyticsTracking
    let imageStorage: ImageStorage

    init(container: AppContainer) {
        self.askUseCase = container.askAssistantUseCase
        self.analytics = container.analytics
        self.imageStorage = container.imageStorage
    }

    func send() async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        messages.append(.user(trimmed))
        input = ""
        isThinking = true
        analytics.track(.assistantAsked, parameters: [
            "message_length": "\(trimmed.count)"
        ])

        do {
            let response = try await askUseCase.execute(message: trimmed, history: messages)
            latestRecommendations = response.recommendations
            messages.append(.assistant(
                response.reply,
                outfitIDs: response.recommendations.map(\.id)
            ))
            analytics.track(.assistantReplied, parameters: [
                "recommendation_count": "\(response.recommendations.count)"
            ])
        } catch {
            messages.append(.assistant("I hit a snag: \(error.localizedDescription)"))
        }

        isThinking = false
    }
}

struct AssistantFeatureView: View {
    @StateObject private var viewModel: AssistantViewModel

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: AssistantViewModel(container: container))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SoftBackground()

                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(viewModel.messages) { message in
                                    ChatBubble(message: message)
                                        .id(message.id)
                                }

                                if viewModel.isThinking {
                                    HStack {
                                        ProgressView()
                                        Text("Styling…")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                }

                                if !viewModel.latestRecommendations.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("Suggested looks")
                                            .font(.headline)
                                            .padding(.horizontal)
                                        ForEach(viewModel.latestRecommendations) { rec in
                                            RecommendationMiniCard(recommendation: rec, storage: viewModel.imageStorage)
                                                .padding(.horizontal)
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                            }
                            .padding(.vertical)
                        }
                        .onChange(of: viewModel.messages.count) { _, _ in
                            if let last = viewModel.messages.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }

                    composer
                }
                .sylyoSafeScreenInsets()
            }
            .navigationTitle("AI Stylist")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var composer: some View {
        SylyoGlassContainer(spacing: 10) {
            HStack(spacing: 10) {
                TextField("What should I wear today?", text: $viewModel.input, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(12)
                    .liquidGlass(cornerRadius: AppRadius.medium, interactive: true)

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.headline.weight(.bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(LiquidGlassButtonStyle(prominent: true))
                .buttonBorderShape(.circle)
                .disabled(viewModel.isThinking || viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .liquidGlass(cornerRadius: AppRadius.large)
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.content)
                .font(.body)
                .foregroundColor(.primary)
                .padding(14)
                .liquidGlass(cornerRadius: 18, interactive: false)
            if message.role != .user { Spacer(minLength: 40) }
        }
        .padding(.horizontal)
    }
}

private struct RecommendationMiniCard: View {
    let recommendation: OutfitRecommendation
    let storage: ImageStorage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recommendation.displayName)
                .font(.headline)
            Text(recommendation.rationale)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
            Text("\(Int(recommendation.confidence * 100))% · \(recommendation.occasion.displayName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppColors.primaryGradient)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.medium)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
    }
}
