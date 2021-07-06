const std = @import("std");

const mm = @import("mm.zig");

const handlers = @import("interrupts/handlers.zig").handlers;

// Interrupt Descriptor Table
pub var idt: []IdtEntry = undefined;

pub fn init() void {
    // place IDT to Extended memory
    idt = mm.GlobalAllocator.allocWithOptions(IdtEntry, 256, 4096, null) catch {
        @panic("Error allocate IDT.");
    };
    for (idt) |*entry, i| {
        const off = @ptrToInt(handlers[i]);
        const cs = 0x18; // code segment selector in GDT
        const typ = 0xe; // 32-bit interrupt gate
        const ist: u1 = switch (i) {
            // NMI, #DF, #MC without IST for now
            2, 8, 18, => 0,
            else => 0,
        };
        entry.* = IdtEntry.init(cs, off, typ, ist, 0);
    }
    const idt_table = IdtTable{
        .limit = @truncate(u16, idt.len * @sizeOf(IdtEntry) - 1),
        .base = @ptrToInt(idt.ptr),
    };
    std.debug.assert(idt_table.limit == 0x07FF);
    std.debug.assert(idt_table.base == 0x0010_0000);
    idt_table.load();
}

const IdtEntry = packed struct {
    offset_1: u16,
    selector: u16,
    zeroes: u8,
    type_attr: u8,
    offset_2: u16,

    fn init(cs: u16, off: u32, typ: u4, ist: u1, dpl: u2) @This() {
        return .{
            .offset_1 = @truncate(u16, off),
            .selector = cs,
            .zeroes = 0,
            .type_attr =
                @as(u8, 1) << 7 |    // P - present
                @as(u8, dpl) << 5 |  // DPL - Descriptor Privilege Level
                @as(u8, ist) << 4 |  // S - Storage Segment
                @as(u8, typ),        // Type - Gate Type
            .offset_2 = @truncate(u16, off >> 16),
        };
    }

    pub fn dump(self: *const @This(), writer: anytype) !void {
        const entry = @ptrCast([*]const u8, self)[0..8];
        try writer.print("{}, offset 0x{x:0>8}\n", .{
            std.fmt.fmtSliceHexLower(entry),
            @as(u32, self.offset_1) | (@as(u32, self.offset_2) << 16),
        });
    }
};

const IdtTable = packed struct {
    limit: u16,
    base: u32,

    fn load(self: @This()) void {
        asm volatile ("lidt (%%eax)"
            :: [self] "{eax}" (self) : "memory");
    }
};

pub fn print_idtr(writer: anytype) !void {
    var idtr: [6]u8 = undefined;
    asm volatile ("sidt (%%eax)"
        :: [idtr] "{eax}" (idtr) : "memory");
    try writer.print("{}\n", .{std.fmt.fmtSliceHexLower(&idtr)});
}

