// Minimal C shim to use Google Secreat Manager in zig
#ifndef ZIG_GCP_SECREAT_MANAGER_H
#define ZIG_GCP_SECREAT_MANAGER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum ZgsmStatus {
    ZGSM_OK = 0,
    ZGSM_ERR_ARG = 1,
    ZGSM_ERR_CURL = 2,
    ZGSM_ERR_HTTP = 3,
    ZGSM_ERR_JSON = 4,
    ZGSM_ERR_BASE64 = 5,
    ZGSM_ERR_ALLOC = 6
} ZgsmStatus;

ZgsmStatus zgsm_get_secret(
    const char* project_id,
    const char* secret_id,
    const char* version,
    unsigned char** out_buf,
    size_t* out_len,
    char** out_err
);

void zgsm_free(void* p);

#ifdef __cplusplus
} 
#endif

#endif
