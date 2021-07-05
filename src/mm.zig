const std = @import("std");

const realmode = @import("realmode.zig");
const RegisterState = realmode.RegisterState;

// Global allocator
const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

var high_memory_allocator: FixedBufferAllocator = undefined;
pub var GlobalAllocator: *Allocator = undefined;

pub fn init() void {
    var regs = RegisterState{};
    while (true) {
        var entry = AddressRangeDescriptor{};

        regs.eax = 0xe820;
        regs.edi = @ptrToInt(&entry);
        regs.ecx = @sizeOf(@TypeOf(entry));
        regs.edx = std.mem.readIntBig(u32, "SMAP");
        realmode.invoke(0x15, &regs);

        // Check CF
        if (regs.efl & 1 != 0) {
            @panic("Error on BIOS E820h");
        }

        // is High Memory
        if (entry.base == 0x0010_0000 and entry.ty == 1) {
            const base = @truncate(usize, entry.base);
            const size = @truncate(usize, entry.size);
            const high_memory = @intToPtr([*]u8, base)[0..size];
            high_memory_allocator = FixedBufferAllocator.init(high_memory);
            GlobalAllocator = &high_memory_allocator.allocator;
            return;
        }

        // Last entry?
        if (regs.ebx == 0) {
            break;
        }
    }
    @panic("High Memory region not found.");
}

pub fn printMap(writer: anytype) !void {
    var regs = RegisterState{};
    while (true) {
        var entry = AddressRangeDescriptor{};

        regs.eax = 0xe820;
        regs.edi = @ptrToInt(&entry);
        regs.ecx = @sizeOf(@TypeOf(entry));
        regs.edx = std.mem.readIntBig(u32, "SMAP");
        realmode.invoke(0x15, &regs);

        // Check CF
        if (regs.efl & 1 != 0) {
            @panic("Error on BIOS E820h");
        }
        try writer.print("{}\n", .{entry});
        // Last entry?
        if (regs.ebx == 0) {
            break;
        }
    }
}

const AddressRangeDescriptor = packed struct {
    base: u64 = undefined,
    size: u64 = undefined,
    ty:   u32 = undefined,

    pub fn format(
        self: @This(),
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        const mem_type = switch (self.ty) {
            1 => "Free",
            2 => "Reserved",
            else => "Undefined",
        };
        try writer.print("0x{x:0>8} | {:10} | ({}) {s}", .{
            self.base,
            self.size,
            self.ty,
            mem_type,
        });
    }
};
