// Minimal C shim to use Google Secret Manager in Zig with low-level access
#ifndef ZIG_GCP_SECREAT_MANAGER_H
#define ZIG_GCP_SECREAT_MANAGER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Status codes returned by the shim
typedef enum ZgsmStatus {
    ZGSM_OK = 0,
    ZGSM_ERR_ARG = 1,
    ZGSM_ERR_CURL = 2,
    ZGSM_ERR_HTTP = 3,
    ZGSM_ERR_JSON = 4,
    ZGSM_ERR_BASE64 = 5,
    ZGSM_ERR_ALLOC = 6
} ZgsmStatus;

// Opaque client type (owns resources in C++ and must be freed with zgsm_client_free)
struct ZgsmClient;

// Uniform result structs (returned by value) to avoid out-parameters.
// Ownership rules:
// - On success (status == ZGSM_OK): err == NULL.
// - On failure: pointer fields (client/data) are NULL; err may be non-NULL and must be freed with zgsm_free.
// - Any data returned on success must be freed with zgsm_free by the caller.
// - The client returned on success must be freed with zgsm_client_free by the caller.

typedef struct {
    ZgsmStatus status;
    int gcp_code;   // google::cloud::StatusCode numeric value (0 when not applicable or success)
    char* err;      // nullable; malloc'd error message
    struct ZgsmClient* client; // non-null on success
} ZgsmClientResult;

typedef struct {
    ZgsmStatus status;
    int gcp_code;
    char* err;           // nullable; malloc'd error message
    unsigned char* data; // non-null on success; malloc'd
    size_t len;
} ZgsmBytesResult;

// Lifecycle (important)
ZgsmClientResult zgsm_client_new(void);
void zgsm_client_free(struct ZgsmClient* client);

// Core operations (important)
ZgsmBytesResult zgsm_access_secret_version(
    struct ZgsmClient* client,
    const unsigned char* resource_name,
    size_t resource_name_len
);

// Free any buffer allocated by this shim (err, data)
void zgsm_free(void* p);

#ifdef __cplusplus
} 
#endif

#endif
