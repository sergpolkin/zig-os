const std = @import("std");
const builtin = @import("builtin");

const io = @import("io.zig");
const Serial = io.Serial;

const mm = @import("mm.zig");
const interrupts = @import("interrupts.zig");

const PIC = @import("pic.zig");

// Symbols provide by `linker.ld`
extern const _start: usize;
extern const _end: usize;

pub fn init() !void {
    // Initialize serial ports.
    // COM1-COM4 115200n1
    Serial.init();

    const out = Serial.writer();

    // Print prompt.
    try out.print("Zig {}\nBuild: {}\n", .{
        builtin.zig_version,
        builtin.mode,
    });
    // Check size of bootloader.
    const boot_size = @ptrToInt(&_end) - @ptrToInt(&_start);
    try out.print("Bootloader size: {} bytes\n", .{
        boot_size,
    });
    // In 'stage0' copy 127 blocks by 512 byte.
    if (boot_size > 127 * 512) {
        @panic("Bootloader size");
    }

    // Initialize memory (GlobalAllocator).
    mm.init();
    try out.print("Memory map:\n", .{});
    try mm.printMap(out);

    // Initialize interrupts (IDT).
    interrupts.init();
    try out.print("IDTR: ", .{});
    try interrupts.print_idtr(out);

    initPIC();
}

fn initPIC() void {
    // Disable all IRQ, except 'Keyboard'
    PIC.set_mask(.master, 0xfd);
    PIC.set_mask(.slave, 0xff);
    // Remap PIC IRQ0..7 -> INT0x20..0x27
    PIC.remap(.master, 0x20);
    // Remap PIC IRQ8..15 -> INT0x28..0x2F
    PIC.remap(.slave, 0x28);
}
