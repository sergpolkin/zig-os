const std = @import("std");

pub const Elf = @import("utils/elf.zig");
pub const Paging = @import("utils/paging.zig");

const Serial = @import("io.zig").Serial;

const SFL = @import("utils/sfl.zig");

pub fn serialboot(allocator: *std.mem.Allocator, port: usize) ![]u8 {
    // Disable interrupts for serial
    const serial_irq = try Serial.get_irq(port);
    try Serial.set_irq(port, 0);
    defer Serial.set_irq(port, serial_irq) catch unreachable;
    // Send "magic" request to Host
    for (SFL.magic_req) |c| {
        try Serial.write(port, c);
    }
    try SFL.checkAck(port);
    var total: usize = 0;
    var buf: ?[]u8 = null;
    var done = false;
    errdefer if (buf != null) allocator.free(buf.?);
    errdefer SFL.clean(port) catch unreachable;
    while (true) {
        const sfl = try SFL.receive(port);
        switch (@intToEnum(SFL.Commands, sfl.cmd)) {
            .abort => {
                try Serial.write(port, SFL.ack_success);
                return SFL.Error.Abort;
            },
            .load => {
                // first 4 bytes is address
                const size = sfl.payload_length - 4;
                const payload = @ptrCast([*]const u8, &sfl.payload);
                buf = if (buf == null)
                    try allocator.allocAdvanced(u8, 16, size, .at_least)
                    else try allocator.realloc(buf.?, total + size);
                std.mem.copy(u8, buf.?[total..total+size], payload[4..size+4]);
                total += size;
                try Serial.write(port, SFL.ack_success);
            },
            .jump => {
                try Serial.write(port, SFL.ack_success);
                done = true;
                break;
            },
            else => {
                try Serial.write(port, SFL.ack_unknown);
                break;
            },
        }
    }
    return if (buf == null or !done) SFL.Error.Abort else buf.?;
}

pub fn dump(out: anytype, data: []const u8) !void {
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        if (i % 16 == 0 and i != 0) { try out.print("\n", .{}); }
        else if (i % 8 == 0 and i != 0) { try out.print(" ", .{}); }
        try out.print("{X:0>2} ", .{data[i]});
    }
    try out.print("\n", .{});
}
