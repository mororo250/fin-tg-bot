// Minimal C shim to use Google Secreat Manager in zig
#include "zig_gcp_secret_manager.h"
#include <string>
#include <cstdlib>
#include <cstring>
#include "google/cloud/secretmanager/v1/secret_manager_client.h"
#include "google/cloud/status_or.h"

namespace sm = ::google::cloud::secretmanager_v1;

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

ZgsmStatus zgsm_get_secret(
    const char* project_id,
    const char* secret_id,
    const char* version,
    unsigned char** out_buf,
    size_t* out_len,
    char** out_err
) {
    if (out_buf) *out_buf = nullptr;
    if (out_len) *out_len = 0;
    if (out_err) *out_err = nullptr;

    if (!project_id || !project_id[0] || !secret_id || !secret_id[0] || !out_buf || !out_len || !out_err) {
        if (out_err) *out_err = dup_cstr("invalid arguments");
        return ZGSM_ERR_ARG;
    }

    const char* ver = (version && version[0]) ? version : "latest";
    std::string name = "projects/";
    name += project_id;
    name += "/secrets/";
    name += secret_id;
    name += "/versions/";
    name += ver;

    sm::SecretManagerServiceClient client(sm::MakeSecretManagerServiceConnection());
    auto resp = client.AccessSecretVersion(name);
    if (!resp.ok()) {
        std::string msg = resp.status().message();
        if (out_err) {
            char* p = dup_cstr(msg.empty() ? std::string("access failed") : msg);
            if (!p) return ZGSM_ERR_ALLOC;
            *out_err = p;
        }
        return ZGSM_ERR_HTTP;
    }

    const std::string& data = resp->payload().data();
    size_t n = data.size();
    unsigned char* buf = static_cast<unsigned char*>(std::malloc(n ? n : 1));
    if (!buf) {
        if (out_err) *out_err = dup_cstr("alloc failed");
        return ZGSM_ERR_ALLOC;
    }
    if (n) std::memcpy(buf, data.data(), n);

    *out_buf = buf;
    *out_len = n;
    return ZGSM_OK;
}

}
