const std = @import("std");
const tgbot = @import("tgbot");

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
