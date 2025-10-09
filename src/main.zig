const std = @import("std");
const tgbot = @import("tgbot");
const pluggy = @import("pluggy");

// GCP Secret Manager C shim (from src/zig-gcp/zig_gcp_secret_manager.h)
const ZgsmStatus = enum(c_int) {
    ZGSM_OK = 0,
    ZGSM_ERR_ARG = 1,
    ZGSM_ERR_CURL = 2,
    ZGSM_ERR_HTTP = 3,
    ZGSM_ERR_JSON = 4,
    ZGSM_ERR_BASE64 = 5,
    ZGSM_ERR_ALLOC = 6,
};

const ZgsmClient = opaque {};
const ZgsmClientResult = extern struct {
    status: ZgsmStatus,
    gcp_code: c_int,
    err: ?[*:0]u8,
    client: ?*ZgsmClient,

    pub fn destroy(self: *ZgsmClientResult) void {
        if (self.err) |e| zgsm_free(e);
        if (self.client) |c| zgsm_client_free(c);
    }
};
const ZgsmBytesResult = extern struct {
    status: ZgsmStatus,
    gcp_code: c_int,
    err: ?[*:0]u8,
    data: ?[*]u8,
    len: usize,

    pub fn destroy(self: *ZgsmBytesResult) void {
        if (self.err) |e| zgsm_free(e);
        if (self.data) |d| zgsm_free(d);
    }
};

extern "c" fn zgsm_client_new() ZgsmClientResult;
extern "c" fn zgsm_client_free(client: *ZgsmClient) void;
extern "c" fn zgsm_access_secret_version(
    client: *ZgsmClient,
    resource_name_ptr: [*]const u8,
    resource_name_len: usize,
) ZgsmBytesResult;

extern "c" fn zgsm_free(p: ?*anyopaque) void;

fn initPluggy(allocator: std.mem.Allocator, http_client: *std.http.Client) !pluggy.Owned([]const u8) {
    var plug_inst = pluggy.init(allocator, http_client);

    var client_res = zgsm_client_new();
    defer client_res.destroy();
    if (client_res.status != .ZGSM_OK or client_res.client == null) {
        if (client_res.err) |e| std.debug.print("GCP client init error: {s}\n", .{e});
        return error.GcpClientInitFailed;
    }
    const gcp = client_res.client.?;

    const project_id = try std.process.getEnvVarOwned(allocator, "GCP_PROJECT_ID");
    defer allocator.free(project_id);

    // Fetch PLUGGY_CLIENT_ID
    const client_id_key = try std.fmt.allocPrint(allocator, "projects/{s}/secrets/{s}/versions/latest", .{ project_id, "PLUGGY_CLIENT_ID" });
    defer allocator.free(client_id_key);
    var client_id_res = zgsm_access_secret_version(gcp, client_id_key.ptr, client_id_key.len);
    defer client_id_res.destroy();
    if (client_id_res.status != .ZGSM_OK or client_id_res.data == null) {
        if (client_id_res.err) |e| std.debug.print("Secret fetch error (client_id): {s}\n", .{e});
        return error.GcpSecretFetchFailed;
    }
    const pluggy_client_id =  client_id_res.data.?[0..client_id_res.len];

    // Fetch PLUGGY_CLIENT_SECRET
    const client_secret_key = try std.fmt.allocPrint(allocator, "projects/{s}/secrets/{s}/versions/latest", .{ project_id, "PLUGGY_CLIENT_SECRET" });
    defer allocator.free(client_secret_key);
    var client_secret_res = zgsm_access_secret_version(gcp, client_secret_key.ptr, client_secret_key.len);
    defer client_secret_res.destroy();
    if (client_secret_res.status != .ZGSM_OK or client_secret_res.data == null) {
        if (client_secret_res.err) |e| std.debug.print("Secret fetch error (client_secret): {s}\n", .{std.mem.span(e)});
        return error.GcpSecretFetchFailed;
    }
    const pluggy_client_secret = client_secret_res.data.?[0..client_secret_res.len];
    defer allocator.free(pluggy_client_secret);

    // Authenticate with Pluggy
    return try plug_inst.auth(pluggy_client_id, pluggy_client_secret);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const token = try std.process.getEnvVarOwned(allocator, "TELEGRAM_TOKEN");
    defer allocator.free(token);
    const chat_id_str = try std.process.getEnvVarOwned(allocator, "TELEGRAM_CHAT_ID");
    defer allocator.free(chat_id_str);
    const chat_id = try std.fmt.parseInt(i64, chat_id_str, 10);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();
    var bot = tgbot.init(allocator, &client, token);
    defer bot.deinit();

    var pluggy_token = try initPluggy(allocator, &client);
    defer pluggy_token.deinit();


    const keyboard_buttons: []const tgbot.InlineKeyboardButton = &.{
        .{ .text = "Yes", .callback_data = "yes_callback" },
        .{ .text = "No", .callback_data = "no_callback" },
    };
    const keyboard_markup = tgbot.InlineKeyboardMarkup{ .inline_keyboard = &.{keyboard_buttons} };

    var message = try bot.sendTextMessageWithKeyboardMarkup(chat_id, "Choose an option:", keyboard_markup);
    message.deinit();

    var update_offset: i64 = 0;
    while (true) {
        std.debug.print("Checking for updates with offset {d}\n", .{update_offset});
        var updates = bot.getUpdates(update_offset) catch |err| {
            std.debug.print("Error getting updates: {any}\n", .{err});
            continue;
        };
        defer updates.deinit();

        for (updates.value) |update| {
            update_offset = update.update_id + 1;
            if (update.callback_query) |callback| {
                const callback_data = callback.data orelse "no_data";
                const confirmation_text = try std.fmt.allocPrint(allocator, "You chose: {s}", .{callback_data});
                defer allocator.free(confirmation_text);

                _ = try bot.answerCallbackQuery(callback.id, confirmation_text);
            }
        }

        std.Thread.sleep(std.time.ns_per_s);
    }
}
