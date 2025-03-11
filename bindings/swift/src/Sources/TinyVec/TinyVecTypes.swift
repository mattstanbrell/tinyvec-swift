import Foundation
import Ccore

// MARK: - Core C-compatible Structures

/// Represents metadata information as a byte array
public struct MetadataBytes {
    /// Raw metadata bytes
    public var data: UnsafeMutablePointer<UInt8>?
    /// Length of the metadata in bytes
    public var length: UInt32
    
    public init(data: UnsafeMutablePointer<UInt8>? = nil, length: UInt32 = 0) {
        self.data = data
        self.length = length
    }
}

/// Represents a single vector search result
public struct VecResult {
    /// Similarity score (higher is more similar)
    public var similarity: Float
    /// Index of the vector in the database
    public var index: Int32
    /// Associated metadata for the vector
    public var metadata: MetadataBytes
    
    public init(similarity: Float = 0, index: Int32 = 0, metadata: MetadataBytes = MetadataBytes()) {
        self.similarity = similarity
        self.index = index
        self.metadata = metadata
    }
}

/// Represents a collection of vector search results
public struct DBSearchResult {
    /// Array of vector results
    public var results: UnsafeMutablePointer<VecResult>?
    /// Number of results
    public var count: Int32
    
    public init(results: UnsafeMutablePointer<VecResult>? = nil, count: Int32 = 0) {
        self.results = results
        self.count = count
    }
}

/// Configuration for TinyVec connection
public struct TinyVecConnectionConfig {
    /// Number of dimensions for the vector database
    public var dimensions: UInt32
    
    /// Initialize a new configuration
    /// - Parameter dimensions: Number of dimensions for vectors
    public init(dimensions: UInt32) {
        self.dimensions = dimensions
    }
}

/// Connection data for TinyVec database
public struct ConnectionData {
    /// File path to the database
    public var filePath: UnsafeMutablePointer<Int8>?
    /// Number of dimensions
    public var dimensions: UInt32
    
    public init(filePath: UnsafeMutablePointer<Int8>? = nil, dimensions: UInt32 = 0) {
        self.filePath = filePath
        self.dimensions = dimensions
    }
}

/// Holds database connection information
public struct TinyVecConnection {
    /// File path to the database
    public var filePath: UnsafePointer<Int8>?
    /// Number of dimensions for vectors in the database
    public var dimensions: UInt32
    
    public init(filePath: UnsafePointer<Int8>? = nil, dimensions: UInt32 = 0) {
        self.filePath = filePath
        self.dimensions = dimensions
    }
}

/// Statistics about the vector index file
public struct IndexFileStats {
    /// Number of vectors in the database
    public var vectorCount: UInt64
    /// Number of dimensions for each vector
    public var dimensions: UInt32
    
    public init(vectorCount: UInt64 = 0, dimensions: UInt32 = 0) {
        self.vectorCount = vectorCount
        self.dimensions = dimensions
    }
}

// MARK: - Swift-friendly Types

/// Swift-friendly representation of a vector search result
public struct TinyVecSearchResult {
    /// Similarity score (higher is more similar)
    public let similarity: Float
    /// Vector ID (index)
    public let id: Int
    /// Metadata associated with the vector
    public let metadata: [String: Any]
    
    public init(similarity: Float, id: Int, metadata: [String: Any]) {
        self.similarity = similarity
        self.id = id
        self.metadata = metadata
    }
}

/// Data structure for vector insertion
public struct TinyVecInsertion {
    /// Vector values
    public let vector: [Float]
    /// Associated metadata
    public let metadata: [String: Any]
    
    /// Initialize a new insertion
    /// - Parameters:
    ///   - vector: Vector data as an array of floats
    ///   - metadata: Metadata associated with the vector
    public init(vector: [Float], metadata: [String: Any]) {
        self.vector = vector
        self.metadata = metadata
    }
}

/// Options for vector search
public struct TinyVecSearchOptions {
    /// Initialize new search options
    public init() {
        // Default initialization
    }
}

/// Options for filtering vector search or deletion
public struct TinyVecFilterOptions {
    /// Filter query in SQL WHERE clause format
    public let filter: String
    
    /// Initialize new filter options
    /// - Parameter filter: Filter expression in SQL-like syntax
    public init(filter: String) {
        self.filter = filter
    }
}

// MARK: - Extensions for C Types

// Extension removed to avoid conflicts with the Swift struct