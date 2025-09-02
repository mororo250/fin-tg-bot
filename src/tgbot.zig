const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;

const TgBot = @This();

allocator: std.mem.Allocator,
client: *std.http.Client,
token: []const u8,

pub fn init(allocator: std.mem.Allocator, client: *std.http.Client, token: []const u8) TgBot {
    return .{
        .token = token,
        .allocator = allocator,
        .client = client,
    };
}

pub fn deinit(self: *TgBot) void {
    _ = self;
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

pub fn Response(comptime T: type) type {
    return struct {
        ok: bool,
        result: ?T = null,
        error_code: ?i32 = null,
        description: ?[]const u8 = null,
    };
}

pub const Update = struct {
    update_id: i64,
    message: ?Message = null,
};

pub const User = struct {
    id: i64,
    is_bot: bool,
    first_name: []const u8,
    last_name: ?[]const u8 = null,
    username: ?[]const u8 = null,
    language_code: ?[]const u8 = null,
};

pub const Chat = struct {
    id: i64,
    type: []const u8,
    title: ?[]const u8 = null,
    username: ?[]const u8 = null,
    first_name: ?[]const u8 = null,
    last_name: ?[]const u8 = null,
};

pub const Message = struct {
    message_id: i64,
    from: ?User = null,
    chat: Chat,
    date: i64,
    text: ?[]const u8 = null,
    reply_markup: ?InlineKeyboardMarkup = null,
};

pub const InlineKeyboardButton = struct {
    text: []const u8,
    callback_data: []const u8,
};

pub const InlineKeyboardMarkup = struct {
    inline_keyboard: [] const [] const InlineKeyboardButton,
};

pub const SendMessagePayload = struct {
    chat_id: i64,
    text: []const u8,
};

pub const SendMessageWithMarkupPayload = struct {
    chat_id: i64,
    text: []const u8,
    reply_markup: InlineKeyboardMarkup,
};

pub fn getUpdates(self: *TgBot, offset: i64) !Owned([]Update) {
    const request_uri = try std.fmt.allocPrint(self.allocator, "https://api.telegram.org/bot{s}/getUpdates?offset={d}", .{ self.token, offset });
    defer self.allocator.free(request_uri);

    var request = try self.client.request(.GET, try std.Uri.parse(request_uri), .{});
    defer request.deinit();

    try request.sendBodiless();
    var redirect_buffer: [1024]u8 = undefined;
    var response = try request.receiveHead(&redirect_buffer);

    var transferBuffer: [64]u8 = undefined;
    var json_reader = std.json.Scanner.Reader.init(self.allocator, response.reader(&transferBuffer));
    defer json_reader.deinit();

    const parsed: std.json.Parsed(Response([]Update)) = try std.json.parseFromTokenSource(Response([]Update), self.allocator, &json_reader, .{});
    if (!parsed.value.ok) {
        if (parsed.value.description) |desc| {
            std.debug.print("Error from telegram: {s}\n", .{desc});
        } else {
            std.debug.print("Error from telegram: unknown\n", .{});
        }
        return error.NotValidResponse;
    }
    return Owned([]Update){
        .arena = parsed.arena,
        .value = parsed.value.result.?,
    };
}

fn sendPostRequest(self: *TgBot, comptime PayloadType: type, comptime ResponseType: type, uri_path: []const u8, payload: PayloadType) !Owned(ResponseType) {
    const request_uri = try std.fmt.allocPrint(self.allocator, "https://api.telegram.org/bot{s}{s}", .{ self.token, uri_path });
    defer self.allocator.free(request_uri);

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

    // used only for print debug
    //const body = try response.reader(&.{}).allocRemaining(self.allocator, .unlimited);
    //defer self.allocator.free(body);
    //std.debug.print("Body: {s}", .{body});
    // End of the debugger code

    var transferBuffer2: [1024]u8 = undefined;
    var json_reader = std.json.Scanner.Reader.init(self.allocator, response.reader(&transferBuffer2));
    defer json_reader.deinit();

    const parsed = try std.json.parseFromTokenSource(Response(ResponseType), self.allocator, &json_reader, .{});
    errdefer parsed.deinit();
    if (!parsed.value.ok) {
        if (parsed.value.description) |desc| {
            std.debug.print("Error from telegram: {s}\n", .{desc});
        } else {
            std.debug.print("Error from telegram: unknown\n", .{});
        }
        return error.NotValidResponse;
    }

    return Owned(ResponseType){
        .arena = parsed.arena,
        .value = parsed.value.result.?,
    };
}

pub fn sendTextMessage(self: *TgBot, chat_id: i64, text: []const u8) !Owned(Message) {
    const payload = SendMessagePayload{
        .chat_id = chat_id,
        .text = text,
    };
    return self.sendPostRequest(SendMessagePayload, Message, "/sendMessage", payload);
}

pub fn sendTextMessageWithKeyboardMarkup(self: *TgBot, chat_id: i64, text: []const u8, keyboard: InlineKeyboardMarkup) !Owned(Message) {
    const payload = SendMessageWithMarkupPayload{
        .chat_id = chat_id,
        .text = text,
        .reply_markup = keyboard,
    };
    return self.sendPostRequest(SendMessageWithMarkupPayload, Message, "/sendMessage", payload);
}

test "getUpdates" {
    var client = std.http.Client{ .allocator = std.testing.allocator };
    defer client.deinit();

    const token = try std.process.getEnvVarOwned(std.testing.allocator, "TELEGRAM_TOKEN");
    defer std.testing.allocator.free(token);
    var bot = TgBot.init(std.testing.allocator, &client, token);
    defer bot.deinit();

    const ownedUpdate = try bot.getUpdates(0);
    defer ownedUpdate.deinit();
}

test "sendMessage" {
    var client = std.http.Client{ .allocator = std.testing.allocator };
    defer client.deinit();

    const token = try std.process.getEnvVarOwned(std.testing.allocator, "TELEGRAM_TOKEN");
    defer std.testing.allocator.free(token);
    const chat_id_str = try std.process.getEnvVarOwned(std.testing.allocator, "TELEGRAM_CHAT_ID");
    defer std.testing.allocator.free(chat_id_str);
    const chat_id = try std.fmt.parseInt(i64, chat_id_str, 10);

    var bot = TgBot.init(std.testing.allocator, &client, token);
    defer bot.deinit();

    const ownedMessage = try bot.sendTextMessage(chat_id, "Hello from zig test!");
    defer ownedMessage.deinit();
}

test "SendMessageWithKeyboardMarkup"
{
 var client = std.http.Client{ .allocator = std.testing.allocator };
    defer client.deinit();

    const token = try std.process.getEnvVarOwned(std.testing.allocator, "TELEGRAM_TOKEN");
    defer std.testing.allocator.free(token);
    const chat_id_str = try std.process.getEnvVarOwned(std.testing.allocator, "TELEGRAM_CHAT_ID");
    defer std.testing.allocator.free(chat_id_str);
    const chat_id = try std.fmt.parseInt(i64, chat_id_str, 10);

    var bot = TgBot.init(std.testing.allocator, &client, token);
    defer bot.deinit();

    const keyboardArray :[] const InlineKeyboardButton = &.{
        .{ .text = "Button 1", .callback_data = "1" },
        .{ .text = "Button 2", .callback_data = "2" },
    };
    const keyboard : InlineKeyboardMarkup  = .{ .inline_keyboard = &.{
        keyboardArray
    }};
    const ownedMessageWithMarkup = try bot.sendTextMessageWithKeyboardMarkup(chat_id, "Hello with markup!", keyboard);
    defer ownedMessageWithMarkup.deinit();
}
