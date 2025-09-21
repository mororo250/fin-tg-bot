const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const PluggyClient = @This();

allocator: std.mem.Allocator,
client: *std.http.Client,

fn Response(comptime T: type) type {
     return struct {
        result: ?T,
        code: ?i32,
        message: ?[]const u8,
        code_description: ?[]const u8,
     };
}

pub fn Owned(comptime T: type) type {
    return struct {
        arena: *ArenaAllocator,
        value: T,

        pub fn deinit(self: @This()) void {
            const allocator = self.arena.child_allocator;
            self.arena.deinit();
            allocator.destroy(self.arena);
        }
    };
}

pub fn init(allocator: std.mem.Allocator, client: *std.http.Client) PluggyClient {
    return .{
        .client = client,
        .allocator = allocator,
    };
}


pub fn auth(self: *PluggyClient, clientId: []const u8, clientSecreat: []const u8) !Owned([]const u8) {
    const payload = .{.clientId = clientId, .clientSecreat = clientSecreat};
    const request_uri = "https://api.pluggy.ai/auth";
    var request = try self.client.request(.POST, try std.Uri.parse(request_uri), .{
        .headers = .{
            .content_type = .{ .override = "application/json" },
        },
    });
    defer request.deinit();
    request.transfer_encoding = .chunked; // This is a necessary step. If you want to use length we would have to know the length beforehand by as an example stringfy it using a different writer
    var transferBuffer: [1024]u8 = undefined;
    var body_writer = try request.sendBodyUnflushed(&transferBuffer);
    try std.json.Stringify.value(payload, .{}, &body_writer.writer);
    try body_writer.end();
    try request.connection.?.flush();

    var redirect_buffer: [1024]u8 = undefined;
    var response = try request.receiveHead(&redirect_buffer);

    var json_reader = std.json.Scanner.Reader.init(self.allocator, response.reader(&transferBuffer));
    defer json_reader.deinit();

    const parsed: std.json.Parsed(Response([]const u8)) =
        try std.json.parseFromTokenSource(Response([]const u8), self.allocator, &json_reader, .{});
    errdefer parsed.deinit();
    if (parsed.value.result == null) {
        if (parsed.value.message) |mesg| {
            std.debug.print("Error from pluggy: {s}\n", .{mesg});
        } else {
            std.debug.print("Error from pluggy: unknown\n", .{});
        }
        return error.ErrorFromTelegram;
    }

    return Owned([]const u8){
        .arena = parsed.arena,
        .value = parsed.value.result.?,
    };
}

test "auth pluggy test" {
    const allocator = std.testing.allocator;
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var pluggy: PluggyClient = PluggyClient.init(allocator, &client);
    const client_id = try std.process.getEnvVarOwned(allocator, "PLUGGY_CLIENT_ID");
    const client_secreat= try std.process.getEnvVarOwned(allocator, "PLUGGY_CLIENT_SECREAT");

    _ = try pluggy.auth(client_id, client_secreat);
}