import SwiftUI
import TinyVec
import UIKit
import Combine

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
    @State private var totalVectorsCount: Int = 0
    @State private var searchCancellable: AnyCancellable?
    @State private var cachedEmbedding: [Float]? = nil
    @State private var isGeneratingEmbedding = false
    
    // Enhanced timing measurements
    @State private var overallTimeMillis: Double = 0
    @State private var searchTimeMillis: Double = 0
    @State private var displayedTimeMillis: Double = 0
    @State private var timerCancellable: AnyCancellable?
    @State private var searchStartTime: Date?
    
    @State private var statusMessage = "Ready to search 100,000 vectors"
    @State private var isInitialized = false
    
    @State private var insertionProgress: Double = 0
    @State private var currentBatchNumber: Int = 0
    @State private var totalBatches: Int = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Add extra space below the title
                Spacer()
                    .frame(height: 10)
                
                // Search box with done button
                HStack {
                    TextField("Search across 100K vectors...", text: $searchText)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                        .submitLabel(.search) // Use search as the keyboard action
                        .onSubmit {
                            if !searchText.isEmpty && client != nil {
                                Task {
                                    await performSearch()
                                }
                            }
                        }
                        .onChange(of: searchText) { newValue in
                            // Cancel previous debounce timer
                            searchCancellable?.cancel()
                            
                            // Reset cached embedding when text changes
                            cachedEmbedding = nil
                            
                            // Only trigger embedding generation if text is not empty
                            if !newValue.isEmpty {
                                // Set up new debounce timer for embedding generation
                                searchCancellable = Just(newValue)
                                    .delay(for: .seconds(0.3), scheduler: RunLoop.main)
                                    .sink { value in
                                        guard !value.isEmpty else { return }
                                        Task {
                                            await generateEmbedding(for: value)
                                        }
                                    }
                            }
                        }
                }
                .padding(.horizontal)
                
                // Search button
                Button(action: {
                    UIApplication.shared.endEditing() // Dismiss keyboard before search
                    Task {
                        await performSearch()
                    }
                }) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Search")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(searchText.isEmpty || client == nil)
                .padding(.horizontal)
                
                // Live timer display during search
                VStack(spacing: 15) {
                    // Permanent search text
                    Text("Searched 100,000 vectors in...")
                        .font(.system(.body))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                    
                    // Animated timer display
                    Text("\(String(format: "%.1f", displayedTimeMillis))ms")
                        .font(.system(size: 48, weight: .bold, design: .monospaced))
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    
                    if isLoading {
                        VStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(1.5)
                                .padding()
                            
                            if totalBatches > 0 {
                                // Progress bar
                                ProgressView(value: insertionProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .padding(.horizontal)
                                
                                // Progress text
                                Text("\(Int(insertionProgress * 100))% - Batch \(currentBatchNumber) of \(totalBatches)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(12)
                .padding(.horizontal)
                
                if !isLoading {
                    // Status message
                    Text(statusMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.top, 5)
                }
                
                // Results section in a ScrollView that takes remaining space
                ScrollView {
                    if !results.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(results) { result in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(result.title)
                                        .font(.headline)
                                    
                                    Text(result.text)
                                        .font(.body)
                                        .lineLimit(3)
                                    
                                    HStack {
                                        Spacer()
                                        Text("Similarity: \(String(format: "%.4f", result.similarity))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .navigationTitle("TinyVec Local Search")
            .navigationBarTitleDisplayMode(.large) // Use large title for more prominence
            // Add a tap gesture to the whole view to dismiss keyboard
            .onTapGesture {
                UIApplication.shared.endEditing()
            }
            .onAppear {
                // Clean up old vector databases first
                Task {
                    await cleanupOldDatabases()
                    
                    // Then initialize database if needed
                    if !isInitialized {
                        await initializeAndPopulateDatabase()
                    }
                }
            }
        }
    }
    
    // MARK: - Cleanup and Initialization
    
    private func cleanupOldDatabases() async {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        
        do {
            // Get all items in the temporary directory
            let tempContents = try fileManager.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.fileSizeKey],
                options: []
            )
            
            // Find tinyvec demo directories
            let tinyvecDirs = tempContents.filter { $0.lastPathComponent.hasPrefix("tinyvec-demo-") }
            
            // Try to find a valid database first
            for dir in tinyvecDirs {
                let dbPath = dir.appendingPathComponent("vectors.db").path
                if FileManager.default.fileExists(atPath: dbPath) {
                    do {
                        // Get file size
                        let attributes = try FileManager.default.attributesOfItem(atPath: dbPath)
                        let fileSize = attributes[.size] as? Int64 ?? 0
                        
                        // Check if file is at least 2GB (typical size for 1M vectors)
                        if fileSize > 200_000_000 { // Adjust to ~200MB for 100K vectors
                            // Try to open the database
                            let config = TinyVecConnectionConfig(dimensions: 512)
                            let existingClient = try TinyVecClient(filePath: dbPath, config: config)
                            
                            // We found a valid database, use it
                            self.dbPath = dbPath
                            self.client = existingClient
                            self.totalVectorsCount = 100_000 // We know it's 100K vectors
                            self.statusMessage = "Ready to search 100,000 vectors"
                            self.isInitialized = true
                            return
                        }
                    } catch {
                        // If we can't open this database, we'll delete it
                        print("Found invalid database at \(dbPath), will remove it")
                    }
                }
            }
            
            // If we get here, we didn't find a valid database
            // Clean up all old directories
            var removedCount = 0
            for dir in tinyvecDirs {
                try fileManager.removeItem(at: dir)
                removedCount += 1
            }
            
            if removedCount > 0 {
                print("Cleaned up \(removedCount) old TinyVec database directories")
            }
        } catch {
            print("Error cleaning up old databases: \(error.localizedDescription)")
        }
    }
    
    // MARK: - TinyVec Operations
    
    private func initializeAndPopulateDatabase() async {
        // If we already have a valid database from cleanup, we're done
        if isInitialized && client != nil {
            return
        }
        
        isLoading = true
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
            let config = TinyVecConnectionConfig(dimensions: 512)
            let newClient = try TinyVecClient(filePath: dbFilePath, config: config)
            
            // Initialize sample documents
            documents = sampleDocuments
            
            // Update state
            dbPath = dbFilePath
            client = newClient
            
            // Insert 1,000,000 vectors
            await insertVectors(client: newClient)
            
            // Perform a silent initial search to warm up the system
            await performSilentSearch(client: newClient)
            
            isInitialized = true
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    private func insertVectors(client: TinyVecClient) async {
        statusMessage = "Requesting embeddings for 20 documents (single batch)..."
        insertionProgress = 0
        currentBatchNumber = 0
        
        do {
            // First get embeddings for the real documents
            let voyageService = VoyageAIService()
            let documentTexts = documents.map { $0.text }
            embeddings = try await voyageService.getEmbeddings(texts: documentTexts)
            
            statusMessage = "Processing document embeddings..."
            
            // Insert real document vectors
            var vectorData: [TinyVecInsertion] = []
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
            
            // Insert real documents
            _ = try await client.insert(data: vectorData)
            insertionProgress = 0.01 // Show small progress for real documents
            
            // Generate and insert random vectors in larger batches
            let randomVectorCount = 99980
            let totalVectors = 20 + randomVectorCount
            statusMessage = "Generating \(randomVectorCount) random vectors..."
            
            // Use larger batch size for better performance
            let batchSize = 50000
            self.totalBatches = (randomVectorCount + batchSize - 1) / batchSize
            var insertedCount = 20 // Start from 20 since we already inserted real documents
            
            for batchIndex in 0..<self.totalBatches {
                currentBatchNumber = batchIndex + 1
                let startIndex = batchIndex * batchSize
                let endIndex = min(startIndex + batchSize, randomVectorCount)
                let currentBatchSize = endIndex - startIndex
                
                statusMessage = "Inserting batch \(currentBatchNumber) of \(totalBatches) (\(currentBatchSize) vectors)"
                
                // Create and insert batch directly
                var batchData: [TinyVecInsertion] = []
                batchData.reserveCapacity(currentBatchSize) // Pre-allocate capacity
                
                for i in startIndex..<endIndex {
                    let randomVector = generateRandomVector(dimension: 512)
                    let metadata: [String: String] = [
                        "id": "random\(i+1)",
                        "title": "Random Vector \(i+1)",
                        "text": "This is a randomly generated vector for testing performance."
                    ]
                    
                    batchData.append(TinyVecInsertion(
                        vector: randomVector,
                        metadata: metadata
                    ))
                }
                
                // Insert batch
                let batchInsertCount = try await client.insert(data: batchData)
                insertedCount += batchInsertCount
                
                // Update progress
                insertionProgress = Double(insertedCount) / Double(totalVectors)
                statusMessage = "Inserted \(insertedCount) of \(totalVectors) vectors..."
            }
            
            totalVectorsCount = insertedCount
            statusMessage = "Ready to search \(totalVectorsCount) vectors"
            isLoading = false
            
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            isLoading = false
        }
    }
    
    // Perform a silent search to warm up the system
    private func performSilentSearch(client: TinyVecClient) async {
        do {
            // Use a simple query for the silent search
            let warmupQuery = "test"
            
            // Get embedding for search query from VoyageAI
            let voyageService = VoyageAIService()
            if let queryEmbedding = try? await voyageService.getEmbeddings(texts: [warmupQuery]).first {
                // Perform search but ignore results
                _ = try? await client.search(
                    query: queryEmbedding,
                    topK: 3
                )
            }
        } catch {
            // Silently ignore any errors during warmup
        }
    }
    
    // Generate embedding for a query but don't perform search
    private func generateEmbedding(for query: String) async {
        guard !query.isEmpty else { return }
        
        // Don't generate if we already have this embedding
        if cachedEmbedding != nil { return }
        
        isGeneratingEmbedding = true
        
        do {
            let voyageService = VoyageAIService()
            if let embedding = try await voyageService.getEmbeddings(texts: [query]).first {
                cachedEmbedding = embedding
            }
        } catch {
            // Silently fail, we'll generate the embedding during search if needed
        }
        
        isGeneratingEmbedding = false
    }
    
    private func startTimerAnimation() {
        // Reset displayed time
        displayedTimeMillis = 0
        searchStartTime = Date()
        
        // Cancel any existing timer
        timerCancellable?.cancel()
        
        // Create a timer that updates at 120fps
        timerCancellable = Timer.publish(every: 1.0/120.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if let startTime = searchStartTime {
                    // During search, show live timing
                    displayedTimeMillis = Date().timeIntervalSince(startTime) * 1000
                }
            }
    }
    
    private func stopTimerAnimation() {
        timerCancellable?.cancel()
        timerCancellable = nil
        searchStartTime = nil
        // Set the final time to the actual search time
        displayedTimeMillis = searchTimeMillis
    }
    
    private func performSearch() async {
        guard let client = client else {
            statusMessage = "Database not initialized"
            return
        }
        
        guard !searchText.isEmpty else {
            statusMessage = "Please enter a search query"
            return
        }
        
        isLoading = true
        statusMessage = "Searching for: \(searchText)"
        
        // Start the timer animation
        startTimerAnimation()
        
        do {
            // Start timing the overall process
            let overallStartTime = Date()
            
            // Use cached embedding if available, otherwise generate a new one
            var queryEmbedding: [Float]
            
            if let cached = cachedEmbedding {
                queryEmbedding = cached
            } else {
                let voyageService = VoyageAIService()
                guard let newEmbedding = try await voyageService.getEmbeddings(texts: [searchText]).first else {
                    statusMessage = "Failed to get embedding for search query"
                    isLoading = false
                    stopTimerAnimation()
                    return
                }
                queryEmbedding = newEmbedding
                cachedEmbedding = newEmbedding
            }
            
            // Time the vector search
            let searchStartTime = Date()
            let searchResults = try await client.search(
                query: queryEmbedding,
                topK: 10
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
            
            // Stop the timer animation
            stopTimerAnimation()
            
            // Update UI
            results = processedResults
            
            if results.isEmpty {
                statusMessage = "No results found for: \(searchText)"
            } else {
                statusMessage = "Found \(results.count) results from \(totalVectorsCount) vectors"
            }
            
            isLoading = false
            
        } catch {
            stopTimerAnimation()
            statusMessage = "Search error: \(error.localizedDescription)"
            results = []
            isLoading = false
        }
    }
    
    // Generate a random vector of the specified dimension
    private func generateRandomVector(dimension: Int) -> [Float] {
        return (0..<dimension).map { _ in Float.random(in: -1.0...1.0) }
    }
    
    // Sample documents for the demo - updated with more interesting topics and 3 related examples
    private var sampleDocuments: [Document] {
        return [
            Document(title: "Typography Test", text: "The quick brown fox jumps over the lazy dog, a phrase commonly used to test typography and fonts because it contains every letter of the English alphabet."),
            Document(title: "Quantum Computing", text: "Quantum computing represents a paradigm shift in computing technology, utilizing principles of quantum mechanics like superposition and entanglement to solve complex problems faster than classical computers."),
            Document(title: "Mount Everest", text: "Mount Everest, standing at 8,848 meters above sea level, remains the highest point on Earth's surface and attracts hundreds of climbers annually seeking to reach its summit."),
            Document(title: "Leonardo da Vinci", text: "Leonardo da Vinci was a polymath of the Italian Renaissance, excelling as a painter, inventor, scientist, and engineer, best known for masterpieces like the Mona Lisa and The Last Supper."),
            Document(title: "AI and NLP", text: "Artificial intelligence systems have significantly advanced natural language processing, enabling technology such as chatbots and virtual assistants to understand human speech with remarkable accuracy."),
            Document(title: "Espresso Coffee", text: "Espresso coffee, characterized by its intense flavor and creamy layer of foam called crema, originated in Italy in the late 19th century and quickly became a global beverage favorite."),
            Document(title: "Photosynthesis", text: "Photosynthesis is the biological process through which green plants convert sunlight, carbon dioxide, and water into oxygen and glucose, sustaining most life on Earth."),
            Document(title: "Hamlet", text: "Shakespeare's play Hamlet explores complex themes of revenge, madness, mortality, and betrayal through its protagonist's introspective monologues and moral dilemmas."),
            Document(title: "Great Barrier Reef", text: "The Great Barrier Reef, located off the coast of Queensland, Australia, is the world's largest coral reef system, home to thousands of species of marine life and stretching over 2,300 kilometers."),
            Document(title: "Cryptocurrency", text: "Cryptocurrency, notably Bitcoin and Ethereum, leverages blockchain technology to enable decentralized digital transactions, significantly altering the landscape of finance and investment."),
            Document(title: "Theory of Relativity", text: "The theory of relativity, proposed by Albert Einstein in the early 20th century, fundamentally changed our understanding of space, time, gravity, and the universe itself."),
            Document(title: "Chess", text: "Chess, an ancient game originating from India around the 6th century, requires strategic foresight and critical thinking, making it a timeless mental challenge."),
            Document(title: "Luke's Training", text: "Luke Skywalker trained under the guidance of Yoda, mastering the Force to ultimately confront the dark side and redeem his father, Anakin Skywalker."),
            Document(title: "Renewable Energy", text: "Renewable energy sources, including wind, solar, and hydroelectric power, offer sustainable alternatives to fossil fuels, essential for reducing greenhouse gas emissions and combating climate change."),
            Document(title: "Harry Potter", text: "J.K. Rowling's Harry Potter series has captivated readers worldwide with its imaginative storytelling, compelling characters, and exploration of good versus evil in a magical world."),
            Document(title: "Mars Exploration", text: "Mars, often called the red planet due to iron oxide on its surface, is currently a major focus for space exploration, with ongoing missions aimed at determining its potential habitability."),
            Document(title: "Darth Vader's Fall", text: "Darth Vader, once a promising Jedi knight named Anakin Skywalker, succumbed to the lure of power and fell to the dark side, becoming a powerful Sith Lord."),
            Document(title: "Classical Music", text: "Classical music composers like Beethoven and Mozart have profoundly influenced Western music traditions, creating works celebrated for their emotional depth and technical brilliance."),
            Document(title: "Deep Learning", text: "Deep learning, a subfield of machine learning, uses artificial neural networks modeled loosely after human brains to identify patterns and perform tasks previously thought impossible for computers."),
            Document(title: "Millennium Falcon", text: "The Millennium Falcon, piloted by Han Solo and Chewbacca, famously completed the Kessel Run in less than twelve parsecs, becoming legendary throughout the galaxy.")
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


