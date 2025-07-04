import SwiftUI

// MARK: - Groq API Models (No changes needed here)

struct GroqMessage: Codable {
    let role: String
    let content: String
}

struct GroqChatRequest: Codable {
    let messages: [GroqMessage]
    let model: String
    let temperature: Double?
    let max_tokens: Int?
    let stream: Bool
    let stop: [String]?
}

struct GroqChatResponse: Codable {
    let choices: [GroqChoice]
    let model: String
}

struct GroqChoice: Codable {
    let message: GroqMessage
    let index: Int
}

// MARK: - PauseView

struct PauseView: View {
    // MARK: - State

    @State private var currentQuestion: String? = nil
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    // MARK: - Constants & API Configuration

    private let groqAPIKey: String

    init() {
        guard let path = Bundle.main.path(forResource: "secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: Any] else {
            fatalError("secrets.plist not found or malformed.")
        }
        guard let key = dict["GROQ_API_KEY"] as? String else {
            fatalError("GROQ_API_KEY not found in secrets.plist. Please add it.")
        }
        self.groqAPIKey = key
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color(red: 240/255, green: 240/255, blue: 250/255), Color(red: 230/255, green: 220/255, blue: 250/255)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                Group {
                    if isLoading {
                        ProgressView("Generating question...")
                            .font(.title2)
                            .foregroundColor(.gray)
                    } else if let error = errorMessage {
                        Text(error) // Display the user-friendly error
                            .font(.headline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    } else if let question = currentQuestion {
                        Text(question)
                            .font(.system(size: 38, weight: .bold))
                            .foregroundColor(Color(red: 153/255, green: 51/255, blue: 204/255))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .transition(.opacity.combined(with: .scale))
                            .id(question)
                    } else {
                        Text("Tap to get a thought-provoking question.")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .transition(.opacity)
                    }
                }
                .frame(minHeight: 180)

                Button {
                    fetchGroqQuestion()
                } label: {
                    Text("Before You Scroll")
                        .font(.title2)
                        .fontWeight(.heavy)
                        .foregroundColor(.white)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 50)
                        .background(Capsule().fill(Color(red: 66/255, green: 133/255, blue: 244/255)))
                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Networking Function

    private func fetchGroqQuestion() {
        isLoading = true
        errorMessage = nil
        currentQuestion = nil

        let userPrompt = "I'm about to open a social media app. Generate a single, concise, thought-provoking question that makes me reconsider if this is the best use of my time right now. The question must be grammatically complete and end with a question mark. Avoid any introductory phrases, conversational fillers, or concluding remarks."

        let messages = [
            GroqMessage(role: "system", content: "You are an AI assistant designed to help users reflect on their screen time. Provide only a single, complete question in response to the user's prompt. Your output must always end with a question mark and contain no other punctuation that would make it appear incomplete."),
            GroqMessage(role: "user", content: userPrompt)
        ]

        let requestBody = GroqChatRequest(
            messages: messages,
            model: "llama3-8b-8192",
            temperature: 0.7,
            max_tokens: 120,
            stream: false,
            // **** THE FIX IS HERE ****
            // Reduced the array to 4 items to comply with the API limit.
            stop: ["?", "\n", "Sure,", "Here's"]
        )

        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            errorMessage = "Invalid API URL."
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(groqAPIKey)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            errorMessage = "Failed to encode request body: \(error.localizedDescription)"
            isLoading = false
            return
        }

        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    // Don't show the full server response to the user, just a friendly message.
                    throw URLError(.badServerResponse, userInfo: [
                        NSLocalizedDescriptionKey: "The server could not process the request (Code: \(statusCode)). Please try again."
                    ])
                }

                let groqResponse = try JSONDecoder().decode(GroqChatResponse.self, from: data)

                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        if let receivedQuestion = groqResponse.choices.first?.message.content {
                            var cleanedQuestion = receivedQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
                            cleanedQuestion = cleanedQuestion.replacingOccurrences(of: "...", with: "")
                            cleanedQuestion = cleanedQuestion.replacingOccurrences(of: "…", with: "")
                            cleanedQuestion = cleanedQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            if cleanedQuestion.hasSuffix(".") || cleanedQuestion.hasSuffix(",") || cleanedQuestion.hasSuffix("!") {
                                cleanedQuestion.removeLast()
                            }
                            
                            if !cleanedQuestion.hasSuffix("?") {
                                cleanedQuestion += "?"
                            }
                            
                            currentQuestion = cleanedQuestion
                        } else {
                            errorMessage = "No question found in Groq response."
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    // Show the user a clean, localized description of the error
                    errorMessage = "Error: \(error.localizedDescription)"
                }
            }
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Preview Provider
struct PauseView_Previews: PreviewProvider {
    static var previews: some View {
        PauseView()
    }
}
