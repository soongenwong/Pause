import SwiftUI

// MARK: - Groq API Models

// Represents a message in the chat conversation
struct GroqMessage: Codable {
    let role: String
    let content: String
}

// Represents the request body for the Groq chat completions API
struct GroqChatRequest: Codable {
    let messages: [GroqMessage]
    let model: String
    let temperature: Double? // Optional: controls randomness
    let max_tokens: Int?     // Optional: limits response length
    let stream: Bool         // Must be false for non-streaming response
}

// Represents the response from the Groq chat completions API
struct GroqChatResponse: Codable {
    let choices: [GroqChoice]
    let model: String
    // Add other fields if needed, like id, object, created, usage, system_fingerprint
}

// Represents a choice within the Groq chat completions response
struct GroqChoice: Codable {
    let message: GroqMessage
    let index: Int
    // Add other fields if needed, like logprobs, finish_reason
}

// MARK: - PauseView

struct PauseView: View {
    // MARK: - State

    @State private var currentQuestion: String? = nil
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil

    // MARK: - Constants & API Configuration

    private let groqAPIKey: String

    // Initialize the API key from secrets.plist
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
            LinearGradient(gradient: Gradient(colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)]), startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // MARK: - Question/Loading/Error Display Area
                Group {
                    if isLoading {
                        ProgressView("Generating question...")
                            .font(.title2)
                            .foregroundColor(.gray)
                    } else if let error = errorMessage {
                        Text("Error: \(error)")
                            .font(.headline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    } else if let question = currentQuestion {
                        Text(question)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.purple)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .transition(.opacity.combined(with: .scale))
                            .id(question) // Key for animation on change
                    } else {
                        Text("Tap to get a thought-provoking question.")
                            .font(.title2)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .transition(.opacity)
                    }
                }
                .frame(minHeight: 120) // Consistent height for display area

                // MARK: - "Before You Scroll" Button
                Button {
                    // Start the asynchronous task to fetch the question
                    fetchGroqQuestion()
                } label: {
                    Text("Before You Scroll")
                        .font(.title2)
                        .fontWeight(.heavy)
                        .foregroundColor(.white)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 50)
                        .background(Capsule().fill(Color.blue))
                        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
                .disabled(isLoading) // Disable button while loading

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Networking Function

    private func fetchGroqQuestion() {
        // Reset states
        isLoading = true
        errorMessage = nil
        currentQuestion = nil // Clear previous question when fetching new one

        // Define the prompt for Groq API
        let prompt = "I'm about to open a social media app. Give me one concise, thought-provoking question that makes me reconsider if this is the best use of my time right now. Do not include any introductory or concluding phrases, just the question itself."

        // Construct the API request body
        let messages = [
            GroqMessage(role: "system", content: "You are a helpful assistant specialized in self-reflection prompts."),
            GroqMessage(role: "user", content: prompt)
        ]
        let requestBody = GroqChatRequest(
            messages: messages,
            model: "llama3-8b-8192", // The specified Groq model
            temperature: 0.7,      // A bit of creativity, not too deterministic
            max_tokens: 60,        // Limit token generation for concise questions
            stream: false
        )

        // Create the URL and URLRequest
        guard let url = URL(string: "https://api.groq.com/openai/v1/chat/completions") else {
            errorMessage = "Invalid API URL."
            isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(groqAPIKey)", forHTTPHeaderField: "Authorization")

        // Encode the request body to JSON
        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            errorMessage = "Failed to encode request body: \(error.localizedDescription)"
            isLoading = false
            return
        }

        // Perform the network request asynchronously
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                // Check for HTTP errors
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let responseString = String(data: data, encoding: .utf8) ?? "No response data"
                    throw URLError(.badServerResponse, userInfo: [
                        NSLocalizedDescriptionKey: "Server error: Status \(statusCode). Response: \(responseString)"
                    ])
                }

                // Decode the JSON response
                let groqResponse = try JSONDecoder().decode(GroqChatResponse.self, from: data)

                // Update UI on the main actor
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        if let question = groqResponse.choices.first?.message.content {
                            currentQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                            errorMessage = "No question found in Groq response."
                        }
                    }
                }
            } catch {
                // Update UI with error on the main actor
                await MainActor.run {
                    errorMessage = "Network or decoding error: \(error.localizedDescription)"
                }
            }
            // Ensure loading state is reset regardless of success or failure
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
