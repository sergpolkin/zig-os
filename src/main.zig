const std = @import("std");
const builtin = @import("builtin");

const Serial = @import("io.zig").Serial;

const mm = @import("mm.zig");
const interrupts = @import("interrupts.zig");

const display = @intToPtr([*]volatile u16, 0xb8000);

// Symbols provide by `linker.ld`
extern const _start: usize;
extern const _end: usize;

export fn main(arg: u32) align(16) callconv(.C) noreturn {
    // "Zig"
    display[80 + 0] = 0x0a5a;
    display[80 + 1] = 0x0a69;
    display[80 + 2] = 0x0a67;

    // Initialize serial ports.
    // COM1-COM4 115200n1
    Serial.init();

    const out = Serial.writer();
    out.print("Zig {}\nBuild: {}\n", .{
        builtin.zig_version,
        builtin.mode,
    }) catch {};

    out.print("Bootloader size: {} bytes\n", .{
        @ptrToInt(&_end) - @ptrToInt(&_start),
    }) catch {};

    out.print("Memory map:\n", .{}) catch {};
    mm.printMap(out) catch {};

    interrupts.init();

    out.print("IDTR: ", .{}) catch {};
    interrupts.print_idtr(out) catch {};

    if (is_ok(arg)) {
        // "OK"
        display[160 + 0] = 0x0f4f;
        display[160 + 1] = 0x0f4b;
        out.print("\x1b[32;1m" ++ "OK" ++ "\x1b[0m\n", .{}) catch {};
    }

    while (true) {
        out.print("CPU halt.\n", .{}) catch {};
        asm volatile ("sti");
        asm volatile ("hlt");
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
    out.print("PANIC \"{s}\"\n", .{msg}) catch {};

    while(true) {
        asm volatile ("hlt");
    }
}
