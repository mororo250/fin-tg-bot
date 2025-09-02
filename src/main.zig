const std = @import("std");
const tgbot = @import("tgbot");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const token = try std.process.getEnvVarOwned(allocator, "TELEGRAM_TOKEN");
    defer allocator.free(token);
    std.debug.print("Telegram Token: {s} \n", .{token});
    const chat_id_str = try std.process.getEnvVarOwned(allocator, "TELEGRAM_CHAT_ID");
    defer allocator.free(chat_id_str);
    const chat_id = try std.fmt.parseInt(i64, chat_id_str, 10);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var bot = tgbot.init(allocator, &client, token);
    defer bot.deinit();

    var message = try bot.sendTextMessage(chat_id ,"this is a test");
    message.deinit();
}
