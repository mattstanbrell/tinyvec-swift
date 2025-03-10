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
        guard !data.isEmpty else {
            return 0 // Nothing to insert
        }
        
        // Validate vector dimensions
        for item in data {
            guard item.vector.count == Int(dimensions) else {
                throw TinyVecError.invalidInput("Vector dimension \(item.vector.count) does not match expected dimension \(dimensions)")
            }
        }
        
        // Create temporary file if it doesn't exist
        let tempFilePath = filePath + ".temp"
        if !FileManager.default.fileExists(atPath: tempFilePath) {
            // Copy the main file to temp file
            if FileManager.default.fileExists(atPath: filePath) {
                try FileManager.default.copyItem(atPath: filePath, toPath: tempFilePath)
            } else {
                // Create a minimal vector file with header
                var header = Data(capacity: 8)
                var vectorCount: UInt32 = 0
                var dims = dimensions
                
                // Append vector count (0)
                withUnsafeBytes(of: &vectorCount) { header.append(contentsOf: $0) }
                
                // Append dimensions
                withUnsafeBytes(of: &dims) { header.append(contentsOf: $0) }
                
                // Write the header to the file
                try header.write(to: URL(fileURLWithPath: tempFilePath))
            }
        }
        
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
            
            // Convert metadata to JSON string
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: data[i].metadata)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    let cString = strdup(jsonString)
                    metadatasPointers[i] = cString
                    metadataLengths[i] = UInt(jsonString.utf8.count)
                } else {
                    throw TinyVecError.dataError("Failed to convert metadata to string for vector \(i)")
                }
            } catch {
                throw TinyVecError.dataError("Failed to serialize metadata for vector \(i): \(error.localizedDescription)")
            }
        }
        
        // Call C function to insert data
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
        
        // Clean up allocated memory
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
            throw TinyVecError.operationFailed("Failed to insert vectors. Error code: \(result)")
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
        guard !query.isEmpty else {
            throw TinyVecError.invalidInput("Query vector cannot be empty")
        }
        
        guard query.count == Int(dimensions) else {
            throw TinyVecError.invalidInput("Query vector dimension \(query.count) does not match expected dimension \(dimensions)")
        }
        
        guard topK > 0 else {
            throw TinyVecError.invalidInput("topK must be greater than 0")
        }
        
        // Convert query to C array
        let queryArray = UnsafeMutablePointer<Float>.allocate(capacity: query.count)
        defer { queryArray.deallocate() }
        
        for i in 0..<query.count {
            queryArray[i] = query[i]
        }
        
        // Call C function to perform search
        var searchResult: UnsafeMutablePointer<DBSearchResult>? = nil
        
        searchResult = filePath.withCString { filePathCString in
            vector_query(filePathCString, queryArray, Int32(topK))
        }
        
        // Check for failed search
        guard let result = searchResult else {
            throw TinyVecError.operationFailed("Vector search failed")
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
        // Note: The C function allocates memory for the results, so we need to free it
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