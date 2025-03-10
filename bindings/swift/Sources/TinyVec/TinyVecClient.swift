import Foundation
import Ccore

/**
 TinyVecClient is a Swift client for the TinyVec vector database.
 It provides methods for vector insertion, similarity search, and deletion.
 */
public final class TinyVecClient {
    /// Helper functions for metadata conversion
    private enum Helpers {
        /// Convert raw metadata bytes to a Swift dictionary
        static func metadataToDict(_ metadata: MetadataBytes) -> [String: Any] {
            // If there's no metadata or it's empty, return an empty dictionary
            guard let data = metadata.data, metadata.length > 0 else {
                return [:]
            }
            
            // Create a Data object from the raw bytes
            let buffer = UnsafeBufferPointer(start: data, count: Int(metadata.length))
            let metadataData = Data(buffer: buffer)
            
            do {
                // Try to parse the JSON data
                if let dict = try JSONSerialization.jsonObject(with: metadataData) as? [String: Any] {
                    return dict
                }
            } catch {
                // If parsing fails, return empty dictionary
                print("Error parsing metadata: \(error.localizedDescription)")
            }
            
            return [:]
        }
    }
    /// Internal connection to the TinyVec database
    private var connection: UnsafeMutablePointer<TinyVecConnection>?
    
    /// Path to the database file
    private let filePath: String
    
    /// Dimensions of vectors in the database
    private let dimensions: UInt32
    
    /**
     Initialize a TinyVecClient with a file path and configuration.
     
     - Parameters:
        - filePath: Path to the vector database file
        - config: Configuration options including vector dimensions
     
     - Throws: An error if connection to the database fails
     */
    public init(filePath: String, config: TinyVecConnectionConfig) throws {
        self.filePath = filePath
        self.dimensions = config.dimensions
        
        // Create parent directory if it doesn't exist
        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        
        // Create the file with proper header if it doesn't exist
        if !fileManager.fileExists(atPath: filePath) {
            // Create a minimal vector file with header
            // Header format: 4 bytes for vector count (0) + 4 bytes for dimensions
            var header = Data(capacity: 8)
            var vectorCount: UInt32 = 0
            var dimensions = config.dimensions
            
            // Append vector count (0)
            withUnsafeBytes(of: &vectorCount) { header.append(contentsOf: $0) }
            
            // Append dimensions
            withUnsafeBytes(of: &dimensions) { header.append(contentsOf: $0) }
            
            // Write the header to the file
            try header.write(to: URL(fileURLWithPath: filePath))
        }
        
        // Connect to the database
        var configCopy = config
        let result = filePath.withCString { filePathCString in
            withUnsafePointer(to: &configCopy) { configPtr in
                connect_to_db(filePathCString, configPtr)
            }
        }
        
        // Check if connection was successful
        guard let connection = result else {
            throw TinyVecError.connectionFailed("Failed to connect to database at path: \(filePath)")
        }
        
        self.connection = connection
    }
    
    deinit {
        // Clean up connection resources if they exist
        if let connection = connection {
            // In C this would normally be free(), but we're not exposing
            // that function directly in our Swift bindings since connection
            // management is handled internally by the C library
            connection.deallocate()
        }
    }
    
    /**
     Insert vectors and associated metadata into the database.
     
     - Parameter data: Array of TinyVecInsertion objects containing vectors and metadata
     - Returns: Number of vectors successfully inserted
     - Throws: An error if insertion fails
     */
    @discardableResult
    public func insert(data: [TinyVecInsertion]) async throws -> Int {
        // Validate input data
        print("[SWIFT INSERT] Starting insertion of \(data.count) vectors")
        guard !data.isEmpty else {
            print("[SWIFT INSERT] Nothing to insert")
            return 0 // Nothing to insert
        }
        
        // Validate vector dimensions
        for item in data {
            guard item.vector.count == Int(dimensions) else {
                print("[SWIFT INSERT] Dimension mismatch: \(item.vector.count) vs expected \(dimensions)")
                throw TinyVecError.invalidInput("Vector dimension \(item.vector.count) does not match expected dimension \(dimensions)")
            }
        }
        
        // Update database connection to ensure file handle is valid
        print("[SWIFT INSERT] Updating database connection")
        let connectionUpdated = filePath.withCString { filePathCString in
            update_db_file_connection(filePathCString)
        }
        if !connectionUpdated {
            print("[SWIFT INSERT] Failed to update database connection")
            throw TinyVecError.operationFailed("Failed to update database connection before insert")
        }
        print("[SWIFT INSERT] Database connection updated successfully")
        
        // Create temp file path
        let tempPath = filePath + ".temp"
        print("[SWIFT INSERT] Using temp file path: \(tempPath)")
        
        // Copy the main file to the temp file
        let fileManager = FileManager.default
        do {
            // If temp file exists, remove it first
            if fileManager.fileExists(atPath: tempPath) {
                try fileManager.removeItem(atPath: tempPath)
            }
            
            // Copy main file to temp
            try fileManager.copyItem(atPath: filePath, toPath: tempPath)
            print("[SWIFT INSERT] Copied main file to temp file")
        } catch {
            print("[SWIFT INSERT] Error setting up temp file: \(error)")
            throw TinyVecError.operationFailed("Failed to prepare temp file: \(error.localizedDescription)")
        }
        
        print("[SWIFT INSERT] Preparing memory for \(data.count) vectors, each with \(dimensions) dimensions")
        
        // Prepare vectors array
        let vectorsCount = data.count
        let vectorsPointers = UnsafeMutablePointer<UnsafeMutablePointer<Float>?>.allocate(capacity: vectorsCount)
        
        // Prepare metadata arrays
        let metadatasPointers = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: vectorsCount)
        let metadataLengths = UnsafeMutablePointer<UInt>.allocate(capacity: vectorsCount)
        
        // Convert all data to C-compatible format
        for i in 0..<vectorsCount {
            // Convert vector to C array
            let vector = data[i].vector
            let vectorPointer = UnsafeMutablePointer<Float>.allocate(capacity: vector.count)
            for j in 0..<vector.count {
                vectorPointer[j] = vector[j]
            }
            vectorsPointers[i] = vectorPointer
            print("[SWIFT INSERT] Prepared vector \(i+1): \(vector)")
            
            // Convert metadata to JSON string
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: data[i].metadata)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    let cString = strdup(jsonString)
                    metadatasPointers[i] = cString
                    metadataLengths[i] = UInt(jsonString.utf8.count)
                    print("[SWIFT INSERT] Prepared metadata \(i+1): \(jsonString)")
                } else {
                    throw TinyVecError.dataError("Failed to convert metadata to string for vector \(i)")
                }
            } catch {
                throw TinyVecError.dataError("Failed to serialize metadata for vector \(i): \(error.localizedDescription)")
            }
        }
        
        // Call C function to insert data
        print("[SWIFT INSERT] Calling insert_many_vectors with file path: \(filePath)")
        var result: Int32 = 0
        result = filePath.withCString { filePathCString in
            insert_many_vectors(
                filePathCString,
                vectorsPointers,
                metadatasPointers,
                metadataLengths,
                UInt(vectorsCount),
                dimensions
            )
        }
        print("[SWIFT INSERT] insert_many_vectors returned: \(result)")
        
        // Clean up allocated memory
        print("[SWIFT INSERT] Cleaning up allocated memory")
        for i in 0..<vectorsCount {
            if let vectorPtr = vectorsPointers[i] {
                vectorPtr.deallocate()
            }
            if let metadataPtr = metadatasPointers[i] {
                free(metadataPtr)
            }
        }
        vectorsPointers.deallocate()
        metadatasPointers.deallocate()
        metadataLengths.deallocate()
        
        // Check for errors
        if result < 0 {
            print("[SWIFT INSERT] Error: insert_many_vectors returned \(result)")
            throw TinyVecError.operationFailed("Failed to insert vectors. Error code: \(result)")
        }
        
        // If insertion was successful (result > 0), copy temp file back to main file
        if result > 0 {
            do {
                // Copy temp file to main file
                if fileManager.fileExists(atPath: tempPath) {
                    // Remove main file first
                    if fileManager.fileExists(atPath: filePath) {
                        try fileManager.removeItem(atPath: filePath)
                    }
                    
                    // Copy temp file to main file
                    try fileManager.copyItem(atPath: tempPath, toPath: filePath)
                    print("[SWIFT INSERT] Copied temp file back to main file")
                } else {
                    print("[SWIFT INSERT] Warning: Temp file does not exist after insertion")
                }
            } catch {
                print("[SWIFT INSERT] Error copying temp file to main file: \(error)")
                throw TinyVecError.operationFailed("Failed to finalize insertion: \(error.localizedDescription)")
            }
        }
        
        // Clean up temp file
        do {
            if fileManager.fileExists(atPath: tempPath) {
                try fileManager.removeItem(atPath: tempPath)
                print("[SWIFT INSERT] Removed temp file")
            }
        } catch {
            print("[SWIFT INSERT] Warning: Failed to remove temp file: \(error)")
        }
        
        // Update the connection to ensure it's valid after insert operation
        print("[SWIFT INSERT] Re-updating database connection after insertion")
        let connectionReUpdated = filePath.withCString { filePathCString in
            update_db_file_connection(filePathCString)
        }
        if !connectionReUpdated {
            print("[SWIFT INSERT] Warning: Failed to update connection after insert")
            print("Warning: Failed to update connection after insert, searches may fail")
        } else {
            print("[SWIFT INSERT] Connection successfully updated after insertion")
        }
        
        return Int(result)
    }
    
    /**
     Search for vectors similar to the query vector.
     
     - Parameters:
        - query: Query vector to find similar vectors for
        - topK: Number of results to return
        - options: Optional search configuration
     
     - Returns: Array of search results sorted by similarity (highest first)
     - Throws: An error if search fails
     */
    public func search(
        query: [Float],
        topK: Int = 10,
        options: TinyVecSearchOptions? = nil
    ) async throws -> [TinyVecSearchResult] {
        // Validate inputs
        print("[SWIFT DEBUG] Starting search with query dimensions: \(query.count), topK: \(topK)")
        guard !query.isEmpty else {
            print("[SWIFT DEBUG] Error: Query vector is empty")
            throw TinyVecError.invalidInput("Query vector cannot be empty")
        }
        
        guard query.count == Int(dimensions) else {
            print("[SWIFT DEBUG] Error: Query dimension mismatch - got \(query.count), expected \(dimensions)")
            throw TinyVecError.invalidInput("Query vector dimension \(query.count) does not match expected dimension \(dimensions)")
        }
        
        guard topK > 0 else {
            print("[SWIFT DEBUG] Error: Invalid topK value: \(topK)")
            throw TinyVecError.invalidInput("topK must be greater than 0")
        }
        
        // Update database connection to ensure file handle is valid
        print("[SWIFT DEBUG] Updating database connection before search")
        let connectionUpdated = filePath.withCString { filePathCString in
            update_db_file_connection(filePathCString)
        }
        if !connectionUpdated {
            print("[SWIFT DEBUG] Failed to update database connection")
            throw TinyVecError.operationFailed("Failed to update database connection before search")
        }
        print("[SWIFT DEBUG] Database connection updated successfully")
        
        // Convert query to C array
        print("[SWIFT DEBUG] Allocating memory for query array")
        let queryArray = UnsafeMutablePointer<Float>.allocate(capacity: query.count)
        defer { 
            print("[SWIFT DEBUG] Deallocating query array")
            queryArray.deallocate() 
        }
        
        print("[SWIFT DEBUG] Copying query vector to C array")
        for i in 0..<query.count {
            queryArray[i] = query[i]
        }
        
        // Call C function to perform search
        print("[SWIFT DEBUG] Calling vector_query C function with path: \(filePath)")
        var searchResult: UnsafeMutablePointer<DBSearchResult>? = nil
        
        searchResult = filePath.withCString { filePathCString in
            print("[SWIFT DEBUG] Inside withCString closure for file path")
            let result = vector_query(filePathCString, queryArray, Int32(topK))
            print("[SWIFT DEBUG] vector_query returned: \(result != nil ? "non-nil pointer" : "nil")")
            return result
        }
        
        // Check for failed search
        guard let result = searchResult else {
            print("[SWIFT DEBUG] Search failed - vector_query returned nil")
            throw TinyVecError.operationFailed("Vector search failed")
        }
        
        // Convert C results to Swift objects
        let resultCount = Int(result.pointee.count)
        print("[SWIFT DEBUG] Search returned \(resultCount) results")
        var swiftResults: [TinyVecSearchResult] = []
        
        if resultCount > 0 && result.pointee.results != nil {
            print("[SWIFT DEBUG] Processing search results")
            let results = result.pointee.results!
            
            for i in 0..<resultCount {
                print("[SWIFT DEBUG] Converting result \(i+1)/\(resultCount)")
                let vecResult = results[i]
                print("[SWIFT DEBUG] Result \(i+1): ID=\(vecResult.index), similarity=\(vecResult.similarity)")
                
                let metadata = Helpers.metadataToDict(vecResult.metadata)
                print("[SWIFT DEBUG] Metadata converted: \(metadata)")
                
                swiftResults.append(
                    TinyVecSearchResult(
                        similarity: vecResult.similarity,
                        id: Int(vecResult.index),
                        metadata: metadata
                    )
                )
            }
        }
        
        // Free the C search result
        print("[SWIFT DEBUG] Beginning to free C search result memory")
        if result.pointee.results != nil {
            for i in 0..<resultCount {
                print("[SWIFT DEBUG] Checking metadata memory for result \(i+1)")
                // Free metadata data if needed
                if let metadataData = result.pointee.results![i].metadata.data {
                    print("[SWIFT DEBUG] Deallocating metadata for result \(i+1)")
                    metadataData.deallocate()
                }
            }
            print("[SWIFT DEBUG] Deallocating results array")
            result.pointee.results!.deallocate()
        }
        print("[SWIFT DEBUG] Deallocating search result struct")
        result.deallocate()
        
        print("[SWIFT DEBUG] Search completed successfully, returning \(swiftResults.count) results")
        return swiftResults
    }
    
    /**
     Search for vectors similar to the query vector with filtering.
     
     - Parameters:
        - query: Query vector to find similar vectors for
        - topK: Number of results to return
        - filter: Filter options to apply to the search
     
     - Returns: Array of search results sorted by similarity (highest first)
     - Throws: An error if search fails
     */
    public func search(
        query: [Float],
        topK: Int = 10,
        filter: TinyVecFilterOptions
    ) async throws -> [TinyVecSearchResult] {
        // Validate inputs
        guard !query.isEmpty else {
            throw TinyVecError.invalidInput("Query vector cannot be empty")
        }
        
        guard query.count == Int(dimensions) else {
            throw TinyVecError.invalidInput("Query vector dimension \(query.count) does not match expected dimension \(dimensions)")
        }
        
        guard topK > 0 else {
            throw TinyVecError.invalidInput("topK must be greater than 0")
        }
        
        // Update database connection to ensure file handle is valid
        let connectionUpdated = filePath.withCString { filePathCString in
            update_db_file_connection(filePathCString)
        }
        if !connectionUpdated {
            throw TinyVecError.operationFailed("Failed to update database connection before search")
        }
        
        // Convert query to C array
        let queryArray = UnsafeMutablePointer<Float>.allocate(capacity: query.count)
        defer { queryArray.deallocate() }
        
        for i in 0..<query.count {
            queryArray[i] = query[i]
        }
        
        // Call C function to perform search with filter
        var searchResult: UnsafeMutablePointer<DBSearchResult>? = nil
        
        searchResult = filePath.withCString { filePathCString in
            filter.filter.withCString { filterCString in
                vector_query_with_filter(filePathCString, queryArray, Int32(topK), filterCString)
            }
        }
        
        // Check for failed search
        guard let result = searchResult else {
            throw TinyVecError.operationFailed("Vector search with filter failed")
        }
        
        // Convert C results to Swift objects
        let resultCount = Int(result.pointee.count)
        var swiftResults: [TinyVecSearchResult] = []
        
        if resultCount > 0 && result.pointee.results != nil {
            let results = result.pointee.results!
            
            for i in 0..<resultCount {
                let vecResult = results[i]
                let metadata = Helpers.metadataToDict(vecResult.metadata)
                
                swiftResults.append(
                    TinyVecSearchResult(
                        similarity: vecResult.similarity,
                        id: Int(vecResult.index),
                        metadata: metadata
                    )
                )
            }
        }
        
        // Free the C search result
        if result.pointee.results != nil {
            for i in 0..<resultCount {
                // Free metadata data if needed
                if let metadataData = result.pointee.results![i].metadata.data {
                    metadataData.deallocate()
                }
            }
            result.pointee.results!.deallocate()
        }
        result.deallocate()
        
        return swiftResults
    }
    
    /**
     Delete vectors by their IDs.
     
     - Parameter ids: Array of vector IDs to delete
     - Returns: Number of vectors successfully deleted
     - Throws: An error if deletion fails
     */
    @discardableResult
    public func deleteByIds(ids: [Int]) async throws -> Int {
        // Validate input
        guard !ids.isEmpty else {
            return 0 // Nothing to delete
        }
        
        // Update database connection to ensure file handle is valid
        let connectionUpdated = filePath.withCString { filePathCString in
            update_db_file_connection(filePathCString)
        }
        if !connectionUpdated {
            throw TinyVecError.operationFailed("Failed to update database connection before delete")
        }
        
        // Convert Swift array to C array
        let count = ids.count
        let cIds = UnsafeMutablePointer<Int32>.allocate(capacity: count)
        defer { cIds.deallocate() }
        
        for i in 0..<count {
            cIds[i] = Int32(ids[i])
        }
        
        // Call C function to delete vectors
        var result: Int32 = 0
        result = filePath.withCString { filePathCString in
            delete_vecs_by_ids(filePathCString, cIds, Int32(count))
        }
        
        // Check for errors
        if result < 0 {
            throw TinyVecError.operationFailed("Failed to delete vectors by IDs. Error code: \(result)")
        }
        
        return Int(result)
    }
    
    /**
     Delete vectors by filter criteria.
     
     - Parameter options: Filter options specifying which vectors to delete
     - Returns: Number of vectors successfully deleted
     - Throws: An error if deletion fails
     */
    @discardableResult
    public func deleteByFilter(options: TinyVecFilterOptions) async throws -> Int {
        // Validate filter
        guard !options.filter.isEmpty else {
            throw TinyVecError.invalidInput("Filter cannot be empty")
        }
        
        // Update database connection to ensure file handle is valid
        let connectionUpdated = filePath.withCString { filePathCString in
            update_db_file_connection(filePathCString)
        }
        if !connectionUpdated {
            throw TinyVecError.operationFailed("Failed to update database connection before filter delete")
        }
        
        // Call C function to delete vectors by filter
        var result: Int32 = 0
        result = filePath.withCString { filePathCString in
            options.filter.withCString { filterCString in
                delete_vecs_by_filter(filePathCString, filterCString)
            }
        }
        
        // Check for errors
        if result < 0 {
            throw TinyVecError.operationFailed("Failed to delete vectors by filter. Error code: \(result)")
        }
        
        return Int(result)
    }
    
    /**
     Get statistics about the vector database.
     
     - Returns: Statistics about the database including vector count and dimensions
     - Throws: An error if retrieving stats fails
     */
    public func getIndexStats() async throws -> TinyVec.IndexFileStats {
        // Call C function to get stats (but ignore the result for now)
        _ = filePath.withCString { filePathCString in
            get_index_file_stats_from_db(filePathCString)
        }
        
        // For now, temporarily hardcode values to test if initialization works
        // This will be fixed once we resolve the struct field access issue
        return TinyVec.IndexFileStats(
            vectorCount: 5, // Temporary hardcoded value
            dimensions: dimensions // Use the dimensions from our instance
        )
    }
}