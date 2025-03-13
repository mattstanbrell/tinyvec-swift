import Foundation

class VoyageAIService {
    private let apiKey = Config.voyageAIApiKey // Use Config instead of hardcoded value
    private let apiUrl = Config.voyageAIApiUrl // Use Config instead of hardcoded value
    
    struct EmbeddingRequest: Codable {
        let input: [String]
        let model: String
        let input_type: String
    }
    
    // Updated to match the actual API response format
    struct EmbeddingResponse: Codable {
        let object: String
        let data: [EmbeddingData]
        let model: String
        let usage: UsageInfo
    }
    
    struct EmbeddingData: Codable {
        let object: String
        let embedding: [Float]
        let index: Int
    }
    
    struct UsageInfo: Codable {
        let total_tokens: Int
    }
    
    func getEmbeddings(texts: [String]) async throws -> [[Float]] {
        // Create URL request
        guard let url = URL(string: apiUrl) else {
            throw NSError(domain: "VoyageAIService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        // Prepare request body
        let requestBody = EmbeddingRequest(
            input: texts,
            model: "voyage-3-lite", // Using voyage-3-lite as specified
            input_type: "document"
        )
        
        let jsonData = try JSONEncoder().encode(requestBody)
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        
        // Perform request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Validate response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "VoyageAIService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        guard httpResponse.statusCode == 200 else {
            // Try to extract error message from response
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "VoyageAIService", code: httpResponse.statusCode,
                         userInfo: [NSLocalizedDescriptionKey: "API error: \(errorText)"])
        }
        
        // Parse response
        let decoder = JSONDecoder()
        let embeddingResponse = try decoder.decode(EmbeddingResponse.self, from: data)
        
        // Convert the data structure to our required format
        let embeddings = embeddingResponse.data.sorted(by: { $0.index < $1.index }).map { $0.embedding }
        return embeddings
    }
}
