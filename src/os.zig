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

    // Enable interrupts on data receive.
    for (Serial.ports) |addr, port| {
        if (addr != null) {
            try Serial.set_irq(port, Serial.IRQ_AVAIL);
        }
    }

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
    interrupts.idt.init(mm.GlobalAllocator);
    try out.print("IDTR: ", .{});
    try interrupts.idt.printIDTR(out);

    initPIC();
}

fn initPIC() void {
    const irq_master: u8 = PIC.IRQ_KBD | PIC.IRQ_COM1 | PIC.IRQ_COM2;
    const irq_slave: u8 = 0;
    PIC.set_mask(.master, ~irq_master);
    PIC.set_mask(.slave, ~irq_slave);
    // Remap PIC IRQ0..7 -> INT0x20..0x27
    PIC.remap(.master, 0x20);
    // Remap PIC IRQ8..15 -> INT0x28..0x2F
    PIC.remap(.slave, 0x28);
}
