const std = @import("std");
const builtin = @import("builtin");

const os = @import("os.zig");

const io = @import("io.zig");
const PortIO = io.PortIO;
const Serial = io.Serial;

const interrupts = @import("interrupts.zig");
const InterruptContext = interrupts.InterruptContext;

const PIC = @import("pic.zig");

const display = @intToPtr([*]volatile u16, 0xb8000);

// some color codes for terminal
const COLOR_RED = "\x1b[31;1m";
const COLOR_GREEN = "\x1b[32;1m";
const COLOR_YELLOW = "\x1b[33;1m";
const COLOR_MAGENTA = "\x1b[35;1m";
const COLOR_WHITE = "\x1b[37;1m";
const COLOR_RESET = "\x1b[0m";

export fn main(arg: u32) align(16) callconv(.C) noreturn {
    // "Zig"
    display[80 + 0] = 0x0a5a;
    display[80 + 1] = 0x0a69;
    display[80 + 2] = 0x0a67;

    os.init() catch {
        @panic("OS init error!");
    };

    interrupt_test();

    if (is_ok(arg)) {
        // "OK"
        display[160 + 0] = 0x0f4f;
        display[160 + 1] = 0x0f4b;
        const out = Serial.writer();
        out.print(COLOR_GREEN ++ "OK\n" ++ COLOR_RESET, .{}) catch {};
    }

    while (true) {
        const out = Serial.writer();
        out.print(COLOR_MAGENTA ++ "CPU halt.\n" ++ COLOR_RESET, .{}) catch {};
        asm volatile ("sti");
        asm volatile ("hlt");
    }
}

fn interrupt_test() void {
    var buf = [4]u32 {1, 2, 3, 4};
    asm volatile ("int $0" ::
        [arg1] "{eax}" (buf[0]),
        [arg2] "{ecx}" (buf[1]),
        [arg3] "{edx}" (buf[2]),
        [arg4] "{ebx}" (buf[3]) : "memory");
}

fn keyboard_handler(out: anytype) !void {
    const KBD_COMMAND = 0x64;
    const KBD_DATA = 0x60;
    const status = PortIO.in(u8, KBD_COMMAND);
    const scancode = if (status & 1 !=0) PortIO.in(u8, KBD_DATA) else null;
    try out.print(COLOR_WHITE, .{});
    if (scancode) |_| {
        try out.print("Keyboard status: 0x{x:0>2}, ", .{status});
        try out.print("scancode: 0x{x:0>2} ", .{scancode.?});
    }
    else {
        try out.print("Keyboard status: 0x{x:0>2}", .{status});
    }
    try out.print("\n" ++ COLOR_RESET, .{});
    // Send EOI
    PIC.eoi(.master);
}

fn print_interrupt(
    out: anytype,
    ctx: *const InterruptContext,
) !void {
    try out.print(COLOR_YELLOW, .{});
    try out.print("Interrupt: {0d} 0x{0x:0>2}, error: 0x{1x:0>8}",
        .{ctx.n, ctx.error_code});
    try out.print("\n" ++ COLOR_RESET, .{});
    try out.print("Registers:\n", .{});
    try ctx.regs.print(out);
    try ctx.frame.print(out);
}

// Handler for all interrupts
export fn interrupt_handler(ctx: *InterruptContext) void {
    const out = Serial.writer();
    switch (ctx.n) {
        // 'Keyboard' IRQ?
        0x21 => keyboard_handler(out) catch {},
        else => print_interrupt(out, ctx) catch {},
    }
}

fn is_ok(arg: u32) bool {
    return arg == 0x12345678;
}

pub fn panic(msg: []const u8, bt: ?*std.builtin.StackTrace) noreturn {
    // display "PANIC!"
    display[0] = 0x0c50;
    display[1] = 0x0c41;
    display[2] = 0x0c4e;
    display[3] = 0x0c49;
    display[4] = 0x0c43;
    display[5] = 0x0c21;

    const out = Serial.writer();
    out.print(COLOR_RED ++ "PANIC \"{s}\"\n" ++ COLOR_RESET, .{
        msg,
    }) catch {};

    while(true) {
        asm volatile ("hlt");
    }
}
