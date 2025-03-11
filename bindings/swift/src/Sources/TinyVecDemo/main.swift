import Foundation
import TinyVec

// Function to print a separator line for readability
func printSeparator() {
    print("\n" + String(repeating: "-", count: 50) + "\n")
}

// Simple error handling
func handle(error: Error) {
    print("❌ Error: \(error)")
}

// Create a temporary directory for testing
func createTempDirectory() -> URL {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("tinyvec-test-\(UUID().uuidString)")
    
    try? FileManager.default.createDirectory(
        at: tempDir,
        withIntermediateDirectories: true
    )
    
    print("Created temp directory at: \(tempDir.path)")
    print("FileManager.default.fileExists: \(FileManager.default.fileExists(atPath: tempDir.path))")
    
    return tempDir
}

// MARK: - Main demo

func runDemo() async {
    print("🔍 TinyVec Swift Demo")
    printSeparator()
    
    // Create a temp directory for our test database
    let tempDir = createTempDirectory()
    let dbPath = tempDir.appendingPathComponent("test.db").path
    print("📁 Using database at: \(dbPath)")
    
    // Don't create an empty file - let the C library handle file creation
    
    do {
        // 1. Connect to database
        print("\n🔌 Connecting to database...")
        let config = TinyVecConnectionConfig(dimensions: 4)
        let client = try TinyVecClient(filePath: dbPath, config: config)
        print("✅ Connected successfully")
        
        // 2. Insert test data
        print("\n📥 Inserting test vectors...")
        let testData: [TinyVecInsertion] = [
            TinyVecInsertion(
                vector: [1.0, 0.0, 0.0, 0.0],
                metadata: ["id": "vec1", "category": "test", "name": "First Vector"]
            ),
            TinyVecInsertion(
                vector: [0.0, 1.0, 0.0, 0.0],
                metadata: ["id": "vec2", "category": "test", "name": "Second Vector"]
            ),
            TinyVecInsertion(
                vector: [0.0, 0.0, 1.0, 0.0],
                metadata: ["id": "vec3", "category": "example", "name": "Third Vector"]
            ),
            TinyVecInsertion(
                vector: [0.0, 0.0, 0.0, 1.0],
                metadata: ["id": "vec4", "category": "example", "name": "Fourth Vector"]
            ),
            TinyVecInsertion(
                vector: [0.5, 0.5, 0.5, 0.5],
                metadata: ["id": "vec5", "category": "other", "name": "Fifth Vector"]
            ),
        ]
        
        print("🔧 Preparing to insert \(testData.count) vectors with dimension \(config.dimensions)")
        
        // Verify file exists before insertion
        print("📄 File exists before insertion: \(FileManager.default.fileExists(atPath: dbPath))")
        if FileManager.default.fileExists(atPath: dbPath) {
            do {
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: dbPath)
                let fileSize = fileAttributes[.size] as? UInt64 ?? 0
                print("📄 File size before insertion: \(fileSize) bytes")
            } catch {
                print("⚠️ Error getting file attributes: \(error)")
            }
        }
        
        let insertCount = try await client.insert(data: testData)
        print("✅ Inserted \(insertCount) vectors")
        
        // Verify file after insertion
        print("📄 File exists after insertion: \(FileManager.default.fileExists(atPath: dbPath))")
        if FileManager.default.fileExists(atPath: dbPath) {
            do {
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: dbPath)
                let fileSize = fileAttributes[.size] as? UInt64 ?? 0
                print("📄 File size after insertion: \(fileSize) bytes")
            } catch {
                print("⚠️ Error getting file attributes: \(error)")
            }
        }
        
        // 3. Get database stats
        print("\n📊 Getting database stats...")
        print("✅ Database contains vectors with \(config.dimensions) dimensions")
        
        // 4. IMPORTANT: Instead of skipping search operations, we'll try them to diagnose the segmentation fault
        print("\n🔎 Attempting to perform search operations with logging...")
        
        // 4.1. Basic search
        print("\n    👉 Searching for similar vectors to [1.0, 0.5, 0.3, 0.2]...")
        do {
            print("    📌 Before search function call")
            let results = try await client.search(
                query: [1.0, 0.5, 0.3, 0.2],
                topK: 3
            )
            print("    ✅ Search completed successfully!")
            print("    📊 Found \(results.count) results:")
            for (i, result) in results.enumerated() {
                print("      Result \(i+1): ID=\(result.id), similarity=\(result.similarity)")
                print("      Metadata: \(result.metadata)")
            }
        } catch {
            print("    ❌ SEARCH ERROR: \(error)")
        }
        
        // 4.2. Exact match search - using vector 3 as query
        print("\n    👉 Searching for exact match with vector [0.0, 0.0, 1.0, 0.0] (should match vec3 perfectly)...")
        do {
            print("    📌 Before exact match search")
            let results = try await client.search(
                query: [0.0, 0.0, 1.0, 0.0], // This is exactly vector 3
                topK: 3
            )
            print("    ✅ Exact match search completed successfully!")
            print("    📊 Found \(results.count) results:")
            for (i, result) in results.enumerated() {
                print("      Result \(i+1): ID=\(result.id), similarity=\(result.similarity)")
                print("      Metadata: \(result.metadata)")
            }
        } catch {
            print("    ❌ EXACT MATCH SEARCH ERROR: \(error)")
        }
        
        // 5. Clean up
        print("\n🧹 Cleaning up test directory...")
        try? FileManager.default.removeItem(at: tempDir)
        
        printSeparator()
        print("🎉 Demo completed")
        
    } catch {
        handle(error: error)
    }
}

// Start the demo
Task {
    await runDemo()
    exit(0)
}

// Run the main dispatch loop
dispatchMain()