// Minimal C shim to use Google Secret Manager in zig
#include "zig_gcp_secret_manager.h"
#include <string>
#include <cstdlib>
#include <cstring>
#include <new>

#include "google/cloud/secretmanager/v1/secret_manager_client.h"
#include "google/cloud/status_or.h"

namespace sm = ::google::cloud::secretmanager_v1;

// Opaque client definition (C-visible only as a forward decl in the header)
struct ZgsmClient {
    sm::SecretManagerServiceClient client;

    ZgsmClient() : client(sm::MakeSecretManagerServiceConnection()) {}
};

extern "C" {

static char* dup_cstr(const std::string& s) {
    char* p = static_cast<char*>(std::malloc(s.size() + 1));
    if (!p) return nullptr;
    std::memcpy(p, s.data(), s.size());
    p[s.size()] = '\0';
    return p;
}


void zgsm_free(void* p) {
    std::free(p);
}


static inline ZgsmClientResult make_client_result_ok(ZgsmClient* c) {
    ZgsmClientResult r;
    r.status = ZGSM_OK;
    r.gcp_code = 0;
    r.err = nullptr;
    r.client = c;
    return r;
}

static inline ZgsmClientResult make_client_result_err(ZgsmStatus st, int gcp_code, const std::string& msg) {
    ZgsmClientResult r;
    r.status = st;
    r.gcp_code = gcp_code;
    r.err = dup_cstr(msg);
    r.client = nullptr;
    return r;
}

static inline ZgsmBytesResult make_bytes_result_ok(const std::string& data) {
    ZgsmBytesResult r;
    r.status = ZGSM_OK;
    r.gcp_code = 0;
    r.err = nullptr;
    size_t n = data.size();
    r.data = static_cast<unsigned char*>(std::malloc(n ? n : 1));
    if (!r.data) {
        r.status = ZGSM_ERR_ALLOC;
        r.len = 0;
        r.err = dup_cstr("alloc failed");
        return r;
    }
    if (n) std::memcpy(r.data, data.data(), n);
    r.len = n;
    return r;
}

static inline ZgsmBytesResult make_bytes_result_err(ZgsmStatus st, int gcp_code, const std::string& msg) {
    ZgsmBytesResult r;
    r.status = st;
    r.gcp_code = gcp_code;
    r.err = dup_cstr(msg);
    r.data = nullptr;
    r.len = 0;
    return r;
}



ZgsmClientResult zgsm_client_new(void) {
    try {
        ZgsmClient* c = new (std::nothrow) ZgsmClient();
        if (!c) {
            return make_client_result_err(ZGSM_ERR_ALLOC, 0, "alloc failed");
        }
        return make_client_result_ok(c);
    } catch (...) {
        return make_client_result_err(ZGSM_ERR_ALLOC, 0, "exception during client allocation");
    }
}

void zgsm_client_free(struct ZgsmClient* client) {
    delete client;
}


ZgsmBytesResult zgsm_access_secret_version(
    struct ZgsmClient* client,
    const unsigned char* resource_name,
    size_t resource_name_len
) {
    if (!client || !resource_name || resource_name_len == 0) {
        return make_bytes_result_err(ZGSM_ERR_ARG, 0, "invalid arguments");
    }
    std::string name(reinterpret_cast<const char*>(resource_name), resource_name_len);
    auto resp = client->client.AccessSecretVersion(name);
    if (!resp.ok()) {
        const auto code = static_cast<int>(resp.status().code());
        std::string msg = resp.status().message();
        if (msg.empty()) msg = "access failed";
        return make_bytes_result_err(ZGSM_ERR_HTTP, code, msg);
    }
    const std::string& data = resp->payload().data();
    return make_bytes_result_ok(data);
}
} // extern "C"
