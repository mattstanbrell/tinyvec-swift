import SwiftUI
import TinyVec
import UIKit

// Extension to dismiss keyboard
extension UIApplication {
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct ContentView: View {
    @State private var searchText = ""
    @State private var results: [SearchResult] = []
    @State private var isLoading = false
    @State private var dbPath: String = ""
    @State private var client: TinyVecClient?
    @State private var documents: [Document] = []
    @State private var embeddings: [[Float]] = []
    @State private var useRandomVectors: Bool = false
    @State private var totalVectorsCount: Int = 0
    @State private var randomVectorCount: Int = 0
    
    // Enhanced timing measurements
    @State private var overallTimeMillis: Double = 0
    @State private var embeddingTimeMillis: Double = 0
    @State private var searchTimeMillis: Double = 0
    
    @State private var statusMessage = "Enter a search query above"
    
    var body: some View {
        NavigationView {
            // Add a tap gesture to the whole view to dismiss keyboard
            ScrollView {
                VStack(spacing: 20) {
                    // Status section
                    VStack(alignment: .leading) {
                        Text("Database Status:")
                            .font(.headline)
                        Text(dbPath.isEmpty ? "Not initialized" : "Connected to: \(dbPath)")
                            .font(.subheadline)
                        if totalVectorsCount > 0 {
                            Text("Total vectors: \(totalVectorsCount)")
                                .font(.subheadline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    
                    // Search box with done button
                    HStack {
                        TextField("Search for something...", text: $searchText)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .onChange(of: searchText) { _ in
                                statusMessage = "Type your search and tap Search button"
                            }
                            .submitLabel(.search) // Use search as the keyboard action
                            .onSubmit {
                                // Trigger search when return key is pressed
                                if !searchText.isEmpty && client != nil && !documents.isEmpty {
                                    Task {
                                        await performSearch()
                                    }
                                }
                            }
                        
                        // Clear button
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                                UIApplication.shared.endEditing()
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                            .padding(.trailing, 8)
                        }
                    }
                    
                    // Action buttons
                    HStack(spacing: 20) {
                        Button(action: {
                            Task {
                                await initializeDatabase()
                            }
                        }) {
                            VStack {
                                Image(systemName: "link")
                                    .font(.system(size: 24))
                                Text("Initialize")
                                    .font(.caption)
                            }
                            .frame(width: 80, height: 80)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(10)
                        }
                        .disabled(dbPath.isNotEmpty)
                        
                        VStack(spacing: 10) {
                            Button(action: {
                                Task {
                                    useRandomVectors = false
                                    randomVectorCount = 0
                                    await insertVectors()
                                }
                            }) {
                                VStack {
                                    Image(systemName: "arrow.down.doc")
                                        .font(.system(size: 24))
                                    Text("Insert 10")
                                        .font(.caption)
                                }
                                .frame(width: 80, height: 60)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(10)
                            }
                            .disabled(client == nil)
                            
                            Button(action: {
                                Task {
                                    useRandomVectors = true
                                    randomVectorCount = 990
                                    await insertVectors()
                                }
                            }) {
                                VStack {
                                    Image(systemName: "arrow.down.doc.fill")
                                        .font(.system(size: 24))
                                    Text("Insert 1K")
                                        .font(.caption)
                                }
                                .frame(width: 80, height: 60)
                                .background(Color.green.opacity(0.4))
                                .cornerRadius(10)
                            }
                            .disabled(client == nil)
                            
                            Button(action: {
                                Task {
                                    useRandomVectors = true
                                    randomVectorCount = 99990
                                    await insertVectors()
                                }
                            }) {
                                VStack {
                                    Image(systemName: "arrow.down.doc.fill")
                                        .font(.system(size: 24))
                                    Text("Insert 100K")
                                        .font(.caption)
                                }
                                .frame(width: 80, height: 60)
                                .background(Color.green.opacity(0.6))
                                .cornerRadius(10)
                            }
                            .disabled(client == nil)
                        }
                        
                        Button(action: {
                            UIApplication.shared.endEditing() // Dismiss keyboard before search
                            Task {
                                await performSearch()
                            }
                        }) {
                            VStack {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 24))
                                Text("Search")
                                    .font(.caption)
                            }
                            .frame(width: 80, height: 80)
                            .background(Color.orange.opacity(0.2))
                            .cornerRadius(10)
                        }
                        .disabled(client == nil || documents.isEmpty || searchText.isEmpty)
                    }
                    
                    // Progress indicator
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(1.5)
                            .padding()
                    }
                    
                    // Status message
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 5)
                    
                    // Results section
                    if !results.isEmpty {
                        // Timing information
                        VStack(alignment: .leading, spacing: 4) {
                            Text("⏱️ Timing Information:")
                                .font(.headline)
                            Text("Total time: \(String(format: "%.2f", overallTimeMillis))ms")
                                .font(.caption)
                            Text("Embedding generation: \(String(format: "%.2f", embeddingTimeMillis))ms")
                                .font(.caption)
                            Text("Vector search: \(String(format: "%.2f", searchTimeMillis))ms")
                                .font(.caption)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .padding(.top, 5)
                    }
                    
                    // Results list
                    if !results.isEmpty {
                        ForEach(results) { result in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(result.text)
                                    .font(.body)
                                
                                Text("Similarity: \(String(format: "%.4f", result.similarity))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Vector Search Demo")
            // Add a tap gesture to the whole scroll view to dismiss keyboard
            .onTapGesture {
                UIApplication.shared.endEditing()
            }
        }
    }
    
    // MARK: - TinyVec Operations
    
    private func initializeDatabase() async {
        isLoading = true
        defer { isLoading = false }
        
        statusMessage = "Initializing database..."
        
        do {
            // Create a temporary directory for testing
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("tinyvec-demo-\(UUID().uuidString)")
            
            try FileManager.default.createDirectory(
                at: tempDir,
                withIntermediateDirectories: true
            )
            
            let dbFilePath = tempDir.appendingPathComponent("vectors.db").path
            
            // Initialize TinyVec client
            let config = TinyVecConnectionConfig(dimensions: 512) // voyage-3-lite uses 512 dimensions
            let newClient = try TinyVecClient(filePath: dbFilePath, config: config)
            
            // Initialize sample documents
            documents = sampleDocuments
            
            // Update state
            dbPath = dbFilePath
            client = newClient
            totalVectorsCount = 0
            
            statusMessage = "Database initialized successfully"
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
    
    private func insertVectors() async {
        guard let client = client else {
            statusMessage = "Client not initialized"
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            var vectorData: [TinyVecInsertion] = []
            
            if useRandomVectors {
                // Insert 10 real vectors + random vectors
                statusMessage = "Getting embeddings for 10 real documents..."
                
                // First get embeddings for the real documents
                let voyageService = VoyageAIService()
                let documentTexts = documents.map { $0.text }
                embeddings = try await voyageService.getEmbeddings(texts: documentTexts)
                
                // Create vectors for real documents
                for (index, embedding) in embeddings.enumerated() {
                    let metadata: [String: String] = [
                        "id": "doc\(index+1)",
                        "title": documents[index].title,
                        "text": documents[index].text
                    ]
                    
                    vectorData.append(TinyVecInsertion(
                        vector: embedding,
                        metadata: metadata
                    ))
                }
                
                // Generate random vectors
                let totalVectors = 10 + randomVectorCount
                statusMessage = "Generating \(randomVectorCount) random vectors..."
                
                // For large numbers of vectors, insert in batches to avoid memory issues
                let batchSize = 10000
                let totalBatches = (randomVectorCount + batchSize - 1) / batchSize // Ceiling division
                
                for batchIndex in 0..<totalBatches {
                    let startIndex = batchIndex * batchSize
                    let endIndex = min(startIndex + batchSize, randomVectorCount)
                    let currentBatchSize = endIndex - startIndex
                    
                    statusMessage = "Generating batch \(batchIndex + 1) of \(totalBatches) (\(currentBatchSize) vectors)"
                    
                    var batchVectors: [TinyVecInsertion] = []
                    
                    for i in startIndex..<endIndex {
                        let randomVector = generateRandomVector(dimension: 512)
                        let metadata: [String: String] = [
                            "id": "random\(i+1)",
                            "title": "Random Vector \(i+1)",
                            "text": "This is a randomly generated vector for testing performance."
                        ]
                        
                        batchVectors.append(TinyVecInsertion(
                            vector: randomVector,
                            metadata: metadata
                        ))
                    }
                    
                    // Add batch to main vector data
                    vectorData.append(contentsOf: batchVectors)
                    
                    // For very large datasets, we could insert each batch separately
                    // but for simplicity, we'll collect all vectors and insert at once
                }
                
                statusMessage = "Inserting \(totalVectors) vectors with dimension 512"
            } else {
                // Just insert the 10 real vectors
                statusMessage = "Getting embeddings from Voyage AI API..."
                
                // Get embeddings from VoyageAI
                let voyageService = VoyageAIService()
                let documentTexts = documents.map { $0.text }
                embeddings = try await voyageService.getEmbeddings(texts: documentTexts)
                
                // Create vectors with embeddings
                for (index, embedding) in embeddings.enumerated() {
                    let metadata: [String: String] = [
                        "id": "doc\(index+1)",
                        "title": documents[index].title,
                        "text": documents[index].text
                    ]
                    
                    vectorData.append(TinyVecInsertion(
                        vector: embedding,
                        metadata: metadata
                    ))
                }
                
                statusMessage = "Inserting \(vectorData.count) vectors with dimension 512"
            }
            
            // Insert vectors
            let insertCount = try await client.insert(data: vectorData)
            totalVectorsCount = insertCount
            
            statusMessage = "✅ Inserted \(insertCount) vectors"
            
            // Check file size
            if FileManager.default.fileExists(atPath: dbPath) {
                do {
                    let fileAttributes = try FileManager.default.attributesOfItem(atPath: dbPath)
                    let fileSize = fileAttributes[.size] as? UInt64 ?? 0
                    let fileSizeMB = Double(fileSize) / (1024 * 1024)
                    statusMessage += " | Database file size: \(String(format: "%.2f", fileSizeMB)) MB"
                } catch {
                    statusMessage += " | Error getting file size: \(error.localizedDescription)"
                }
            }
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }
    
    private func performSearch() async {
        guard let client = client else {
            statusMessage = "Client not initialized"
            return
        }
        
        guard !searchText.isEmpty else {
            statusMessage = "Please enter a search query"
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        statusMessage = "Searching for: \(searchText)"
        
        do {
            // Start timing the overall process
            let overallStartTime = Date()
            
            // Get embedding for search query from VoyageAI
            let voyageService = VoyageAIService()
            
            // Time embedding generation
            let embeddingStartTime = Date()
            guard let queryEmbedding = try await voyageService.getEmbeddings(texts: [searchText]).first else {
                statusMessage = "Failed to get embedding for search query"
                return
            }
            embeddingTimeMillis = Date().timeIntervalSince(embeddingStartTime) * 1000
            
            // Time the vector search
            let searchStartTime = Date()
            let searchResults = try await client.search(
                query: queryEmbedding,
                topK: 5
            )
            searchTimeMillis = Date().timeIntervalSince(searchStartTime) * 1000
            
            // Calculate overall time taken
            overallTimeMillis = Date().timeIntervalSince(overallStartTime) * 1000
            
            // Process results
            var processedResults: [SearchResult] = []
            
            for (i, result) in searchResults.enumerated() {
                let text = (result.metadata["text"] as? String) ?? "No text available"
                let title = (result.metadata["title"] as? String) ?? "Untitled"
                
                processedResults.append(SearchResult(
                    id: i,
                    text: text,
                    title: title,
                    similarity: result.similarity
                ))
            }
            
            // Update UI
            results = processedResults
            
            if results.isEmpty {
                statusMessage = "No results found for: \(searchText)"
            } else {
                statusMessage = "Found \(results.count) results for: \(searchText) from \(totalVectorsCount) total vectors"
            }
            
        } catch {
            statusMessage = "Search error: \(error.localizedDescription)"
            results = []
        }
    }
    
    // Generate a random vector of the specified dimension
    private func generateRandomVector(dimension: Int) -> [Float] {
        return (0..<dimension).map { _ in Float.random(in: -1.0...1.0) }
    }
    
    // Sample documents for the demo
    private var sampleDocuments: [Document] {
        return [
            Document(title: "Swift Programming", text: "Swift is a powerful and intuitive programming language developed by Apple for iOS, macOS, watchOS, and tvOS. Swift code is safe by design, yet also produces software that runs lightning-fast."),
            Document(title: "Machine Learning", text: "Machine learning is a field of computer science that gives computers the ability to learn without being explicitly programmed. It focuses on developing programs that can access data and use it to learn for themselves."),
            Document(title: "Climate Change", text: "Climate change refers to long-term shifts in temperatures and weather patterns, mainly caused by human activities, especially the burning of fossil fuels. These activities produce greenhouse gases that wrap around the Earth, trapping the sun's heat."),
            Document(title: "Quantum Computing", text: "Quantum computing utilizes the principles of quantum mechanics to process information. Traditional computers use bits (0s and 1s), while quantum computers use quantum bits or qubits, which can exist in multiple states simultaneously."),
            Document(title: "Artificial Intelligence Ethics", text: "AI ethics concerns the moral issues that arise with the development and deployment of artificial intelligence. Key issues include privacy, bias, transparency, and the potential displacement of human workers."),
            Document(title: "Sustainable Living", text: "Sustainable living is a lifestyle that attempts to reduce an individual's or society's use of the Earth's natural resources. Practitioners of sustainable living often attempt to reduce their carbon footprint through various means."),
            Document(title: "History of the Internet", text: "The Internet was initially developed in the 1960s as ARPANET, a project of the United States Department of Defense. It evolved through the 1980s and 1990s to become the global network we know today, transforming how we communicate, work, and access information."),
            Document(title: "Nutrition Science", text: "Nutrition science investigates the metabolic and physiological responses of the body to diet. It examines the nutrients and other substances in food and how the body processes, uses, and stores them."),
            Document(title: "Space Exploration", text: "Space exploration is the use of astronomy and space technology to explore outer space. Physical exploration is conducted both by human spaceflights and by robotic spacecraft, while astronomical observations are made from Earth or Earth-orbiting observatories."),
            Document(title: "Renewable Energy", text: "Renewable energy comes from sources that are naturally replenishing but flow-limited, such as sunlight, wind, rain, tides, waves, and geothermal heat. These energy resources are renewable, meaning they are naturally replenished on a human timescale.")
        ]
    }
}

// Models
struct Document {
    let title: String
    let text: String
}

struct SearchResult: Identifiable {
    let id: Int
    let text: String
    let title: String
    let similarity: Float
}

// Helper extension for String
extension String {
    var isNotEmpty: Bool {
        !self.isEmpty
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
