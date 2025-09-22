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

static char* dup_cstr_view(const char* s) {
    if (!s) return nullptr;
    size_t n = std::strlen(s);
    char* p = static_cast<char*>(std::malloc(n + 1));
    if (!p) return nullptr;
    if (n) std::memcpy(p, s, n);
    p[n] = '\0';
    return p;
}

void zgsm_free(void* p) {
    std::free(p);
}

// ---------------- Legacy one-shot helper (kept for compatibility) ----------------

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

// ---------------- New struct-returning API ----------------

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

static inline ZgsmStringResult make_string_result_ok(const std::string& s) {
    ZgsmStringResult r;
    r.status = ZGSM_OK;
    r.gcp_code = 0;
    r.err = nullptr;
    r.ptr = dup_cstr(s);
    if (!r.ptr) {
        r.status = ZGSM_ERR_ALLOC;
        r.err = dup_cstr("alloc failed");
    }
    return r;
}

static inline ZgsmStringResult make_string_result_err(ZgsmStatus st, int gcp_code, const std::string& msg) {
    ZgsmStringResult r;
    r.status = st;
    r.gcp_code = gcp_code;
    r.err = dup_cstr(msg);
    r.ptr = nullptr;
    return r;
}

ZgsmClientResult zgsm_client_new2(void) {
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

static inline std::string make_name(const char* project_id, const char* secret_id, const char* version) {
    const char* ver = (version && version[0]) ? version : "latest";
    std::string name = "projects/";
    name += (project_id ? project_id : "");
    name += "/secrets/";
    name += (secret_id ? secret_id : "");
    name += "/versions/";
    name += ver;
    return name;
}

ZgsmBytesResult zgsm_access_secret_version2(
    struct ZgsmClient* client,
    const char* project_id,
    const char* secret_id,
    const char* version
) {
    if (!client || !project_id || !project_id[0] || !secret_id || !secret_id[0]) {
        return make_bytes_result_err(ZGSM_ERR_ARG, 0, "invalid arguments");
    }
    std::string name = make_name(project_id, secret_id, version);
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

ZgsmBytesResult zgsm_access_secret_version_by_name2(
    struct ZgsmClient* client,
    const char* secret_version_resource
) {
    if (!client || !secret_version_resource || !secret_version_resource[0]) {
        return make_bytes_result_err(ZGSM_ERR_ARG, 0, "invalid arguments");
    }
    auto resp = client->client.AccessSecretVersion(secret_version_resource);
    if (!resp.ok()) {
        const auto code = static_cast<int>(resp.status().code());
        std::string msg = resp.status().message();
        if (msg.empty()) msg = "access failed";
        return make_bytes_result_err(ZGSM_ERR_HTTP, code, msg);
    }
    const std::string& data = resp->payload().data();
    return make_bytes_result_ok(data);
}

// Minimal JSON escaping for strings (escape backslash and quote)
static inline std::string json_escape(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (unsigned char ch : s) {
        switch (ch) {
            case '\\': out += "\\\\"; break;
            case '\"': out += "\\\""; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (ch < 0x20) {
                    // control characters -> \u00XX
                    static const char hex[] = "0123456789abcdef";
                    out += "\\u00";
                    out += hex[(ch >> 4) & 0xF];
                    out += hex[ch & 0xF];
                } else {
                    out += static_cast<char>(ch);
                }
        }
    }
    return out;
}

static inline ZgsmStringResult secret_version_to_json(auto const& sv) {
    // Fields: name, state (int), create_time_seconds, create_time_nanos, destroy_time_seconds, destroy_time_nanos, etag
    // Use presence checks if available; if not present, use 0.
    std::string name = sv.name();
    int state = static_cast<int>(sv.state());

    long long create_s = 0;
    int create_n = 0;
#if defined(GOOGLE_CLOUD_CPP_VERSION_MAJOR) // feature guard is not needed; keeping for clarity
    if (sv.has_create_time()) {
        create_s = static_cast<long long>(sv.create_time().seconds());
        create_n = sv.create_time().nanos();
    }
#else
    // assume presence methods exist
    if (sv.has_create_time()) {
        create_s = static_cast<long long>(sv.create_time().seconds());
        create_n = sv.create_time().nanos();
    }
#endif

    long long destroy_s = 0;
    int destroy_n = 0;
    if (sv.has_destroy_time()) {
        destroy_s = static_cast<long long>(sv.destroy_time().seconds());
        destroy_n = sv.destroy_time().nanos();
    }

    std::string etag = sv.etag();

    std::string json;
    json.reserve(name.size() + etag.size() + 128);
    json += "{";
    json += "\"name\":\""; json += json_escape(name); json += "\",";
    json += "\"state\":"; json += std::to_string(state); json += ",";
    json += "\"create_time_seconds\":"; json += std::to_string(create_s); json += ",";
    json += "\"create_time_nanos\":"; json += std::to_string(create_n); json += ",";
    json += "\"destroy_time_seconds\":"; json += std::to_string(destroy_s); json += ",";
    json += "\"destroy_time_nanos\":"; json += std::to_string(destroy_n); json += ",";
    json += "\"etag\":\""; json += json_escape(etag); json += "\"";
    json += "}";
    return make_string_result_ok(json);
}

ZgsmStringResult zgsm_get_secret_version2(
    struct ZgsmClient* client,
    const char* project_id,
    const char* secret_id,
    const char* version
) {
    if (!client || !project_id || !project_id[0] || !secret_id || !secret_id[0]) {
        return make_string_result_err(ZGSM_ERR_ARG, 0, "invalid arguments");
    }
    std::string name = make_name(project_id, secret_id, version);
    auto resp = client->client.GetSecretVersion(name);
    if (!resp.ok()) {
        const auto code = static_cast<int>(resp.status().code());
        std::string msg = resp.status().message();
        if (msg.empty()) msg = "get failed";
        return make_string_result_err(ZGSM_ERR_HTTP, code, msg);
    }
    return secret_version_to_json(*resp);
}

ZgsmStringResult zgsm_get_secret_version_by_name2(
    struct ZgsmClient* client,
    const char* secret_version_resource
) {
    if (!client || !secret_version_resource || !secret_version_resource[0]) {
        return make_string_result_err(ZGSM_ERR_ARG, 0, "invalid arguments");
    }
    auto resp = client->client.GetSecretVersion(secret_version_resource);
    if (!resp.ok()) {
        const auto code = static_cast<int>(resp.status().code());
        std::string msg = resp.status().message();
        if (msg.empty()) msg = "get failed";
        return make_string_result_err(ZGSM_ERR_HTTP, code, msg);
    }
    return secret_version_to_json(*resp);
}

ZgsmStringResult zgsm_make_secret_version_name2(
    const char* project_id,
    const char* secret_id,
    const char* version
) {
    if (!project_id || !project_id[0] || !secret_id || !secret_id[0]) {
        return make_string_result_err(ZGSM_ERR_ARG, 0, "invalid arguments");
    }
    std::string name = make_name(project_id, secret_id, version);
    return make_string_result_ok(name);
}

} // extern "C"
