const std = @import("std");

pub const ZgsmStatus = enum(c_int) {
    ZGSM_OK = 0,
    ZGSM_ERR_ARG = 1,
    ZGSM_ERR_CURL = 2,
    ZGSM_ERR_HTTP = 3,
    ZGSM_ERR_JSON = 4,
    ZGSM_ERR_BASE64 = 5,
    ZGSM_ERR_ALLOC = 6,
};

extern fn zgsm_get_secret(
    project_id: [*:0]const u8,
    secret_id: [*:0]const u8,
    version: [*:0]const u8,
    out_buf: *[*]u8,
    out_len: *usize,
    out_err: *[*:0]u8,
) ZgsmStatus;

extern fn zgsm_free(p: ?*anyopaque) void;

test "zig_gcp_secret_manager get_secret" {
    std.debug.print("test start", .{});
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const project_opt = std.process.getEnvVarOwned(alloc, "GCP_PROJECT_ID") catch null;
    defer if (project_opt) |p| alloc.free(p);
    if (project_opt == null) return; // skip when env not set
    const secret_opt = std.process.getEnvVarOwned(alloc, "GCP_SECRET_ID") catch null;
    defer if (secret_opt) |p| alloc.free(p);
    if (secret_opt == null) return; // skip when env not set

    const version_opt = std.process.getEnvVarOwned(alloc, "GCP_SECRET_VERSION") catch null;
    defer if (version_opt) |p| alloc.free(p);

    const project_z = try std.fmt.allocPrintZ(alloc, "{s}", .{project_opt.?});
    defer alloc.free(project_z);
    const secret_z = try std.fmt.allocPrintZ(alloc, "{s}", .{secret_opt.?});
    defer alloc.free(secret_z);
    const version_z = if (version_opt) |v| blk: {
        break :blk try std.fmt.allocPrintZ(alloc, "{s}", .{v});
    } else blk2: {
        break :blk2 try std.fmt.allocPrintZ(alloc, "latest", .{});
    };
    defer alloc.free(version_z);

    var c_buf: [*]u8 = undefined;
    var c_len: usize = 0;
    var c_err: [*:0]u8 = null;

    const st = zgsm_get_secret(project_z, secret_z, version_z, &c_buf, &c_len, &c_err);
    if (st != .ZGSM_OK) {
        const err_msg: []const u8 = if (c_err) |e| std.mem.span(e) else "unknown error";
        if (c_err) zgsm_free(c_err);
        std.debug.print("zgsm_get_secret failed: {s} (status={})\n", .{ err_msg, st });
        try std.testing.expect(false);
        return;
    }

    try std.testing.expect(c_len >= 0);
    if (c_len > 0) {
        // no-op; secret bytes are in c_buf[0..c_len]
    }
    if (c_buf) zgsm_free(c_buf);
}
