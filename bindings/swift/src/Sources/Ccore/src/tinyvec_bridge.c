#include "../include/tinyvec_bridge.h"
#include "../include/db.h"
#include "../include/vec_types.h"

// Bridge functions to map Swift function names to C function names
TinyVecConnection* connect_to_db(const char* file_path, const TinyVecConnectionConfig* config) {
    return create_tiny_vec_connection(file_path, config->dimensions);
}

IndexFileStats get_index_file_stats_from_db(const char* file_path) {
    return get_index_stats(file_path);
}

DBSearchResult* vector_query(const char* file_path, const float* query_vec, const int top_k) {
    return get_top_k(file_path, query_vec, top_k);
}

DBSearchResult* vector_query_with_filter(const char* file_path, const float* query_vec, const int top_k, const char* json_filter) {
    return get_top_k_with_filter(file_path, query_vec, top_k, json_filter);
}

int delete_vecs_by_ids(const char* file_path, int* ids_to_delete, int delete_count) {
    return delete_data_by_ids(file_path, ids_to_delete, delete_count);
}

int delete_vecs_by_filter(const char* file_path, const char* json_filter) {
    return delete_data_by_filter(file_path, json_filter);
}

int insert_many_vectors(const char* file_path, float** vectors, char** metadatas, size_t* metadata_lengths,
                       const size_t vec_count, const uint32_t dimensions) {
    return insert_data(file_path, vectors, metadatas, metadata_lengths, vec_count, dimensions);
} 