import Foundation
import Ccore

// Import C functions from Ccore module
// This bridges the C API to Swift

// Connection functions
@_silgen_name("connect_to_db")
public func connect_to_db(
    _ filePath: UnsafePointer<CChar>,
    _ config: UnsafePointer<TinyVecConnectionConfig>
) -> UnsafeMutablePointer<TinyVecConnection>?

// Search functions
@_silgen_name("vector_query")
public func vector_query(
    _ filePath: UnsafePointer<CChar>,
    _ queryVec: UnsafePointer<Float>,
    _ topK: Int32
) -> UnsafeMutablePointer<DBSearchResult>?

@_silgen_name("vector_query_with_filter")
public func vector_query_with_filter(
    _ filePath: UnsafePointer<CChar>,
    _ queryVec: UnsafePointer<Float>,
    _ topK: Int32,
    _ jsonFilter: UnsafePointer<CChar>
) -> UnsafeMutablePointer<DBSearchResult>?

// Insert function
@_silgen_name("insert_many_vectors")
public func insert_many_vectors(
    _ filePath: UnsafePointer<CChar>,
    _ vectors: UnsafeMutablePointer<UnsafeMutablePointer<Float>?>,
    _ metadatas: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>,
    _ metadataLengths: UnsafeMutablePointer<UInt>,
    _ vecCount: UInt,
    _ dimensions: UInt32
) -> Int32

// Delete functions
@_silgen_name("delete_vecs_by_ids")
public func delete_vecs_by_ids(
    _ filePath: UnsafePointer<CChar>,
    _ idsToDelete: UnsafeMutablePointer<Int32>,
    _ deleteCount: Int32
) -> Int32

@_silgen_name("delete_vecs_by_filter")
public func delete_vecs_by_filter(
    _ filePath: UnsafePointer<CChar>,
    _ jsonFilter: UnsafePointer<CChar>
) -> Int32

// Stats function
@_silgen_name("get_index_file_stats_from_db")
public func get_index_file_stats_from_db(
    _ filePath: UnsafePointer<CChar>
) -> IndexFileStats

// Helper functions
@_silgen_name("update_db_file_connection")
public func update_db_file_connection(
    _ filePath: UnsafePointer<CChar>
) -> Bool