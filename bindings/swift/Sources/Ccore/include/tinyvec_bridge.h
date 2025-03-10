#ifndef TINYVEC_BRIDGE_H
#define TINYVEC_BRIDGE_H

#ifdef __cplusplus
extern "C"
{
#endif

#include "db.h"
#include "vec_types.h"

// Bridge functions to map Swift function names to C function names
TinyVecConnection* connect_to_db(const char* file_path, const TinyVecConnectionConfig* config);

IndexFileStats get_index_file_stats_from_db(const char* file_path);

DBSearchResult* vector_query(const char* file_path, const float* query_vec, const int top_k);

DBSearchResult* vector_query_with_filter(const char* file_path, const float* query_vec, const int top_k, const char* json_filter);

int delete_vecs_by_ids(const char* file_path, int* ids_to_delete, int delete_count);

int delete_vecs_by_filter(const char* file_path, const char* json_filter);

int insert_many_vectors(const char* file_path, float** vectors, char** metadatas, size_t* metadata_lengths,
                       const size_t vec_count, const uint32_t dimensions);

#ifdef __cplusplus
}
#endif

#endif // TINYVEC_BRIDGE_H 