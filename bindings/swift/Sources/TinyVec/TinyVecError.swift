import Foundation

/// Represents errors that can occur when using TinyVec
public enum TinyVecError: Error {
    /// The connection to the database failed
    case connectionFailed(String)
    
    /// The database file doesn't exist
    case fileNotFound(String)
    
    /// Invalid input parameters
    case invalidInput(String)
    
    /// Operation failed
    case operationFailed(String)
    
    /// Memory allocation failed
    case memoryError(String)
    
    /// Invalid or corrupted data
    case dataError(String)
    
    /// Function availability error
    case notImplemented(String)
}