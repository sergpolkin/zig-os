const std = @import("std");

const io = @import("io.zig");
const Serial = io.Serial;

pub const idt = @import("interrupts/idt.zig");

pub const InterruptFrame = packed struct {
    eip: u32,
    cs: u32,
    eflags: u32,

    pub fn print(self: *const @This(), writer: anytype) !void {
        const msg =
            \\eip {x:0>8}
            \\eflags {x:0>8} cs {x:0>8}
            \\
        ;
        try writer.print(msg, .{self.eip, self.eflags, self.cs});
    }
};

// Structure containing all registers at the state of the interrupt
pub const RegsState = packed struct {
    ebp: u32,
    edi: u32,
    esi: u32,
    edx: u32,
    ecx: u32,
    ebx: u32,
    eax: u32,

    pub fn print(self: *const @This(), writer: anytype) !void {
        const msg =
            \\eax {x:0>8} ecx {x:0>8} edx {x:0>8} ebx {x:0>8}
            \\esp ???????? ebp {x:0>8} esi {x:0>8} edi {x:0>8}
            \\
        ;
        try writer.print(msg, .{
            self.eax, self.ecx, self.edx, self.ebx,
            self.ebp, self.esi, self.edi,
        });
    }
};

pub const InterruptContext = packed struct {
    n: u32,
    error_code: u32,
    frame: *InterruptFrame,
    regs: *RegsState,
};

pub const InterruptHandler = fn(ctx: *InterruptContext) InterruptError!void;
pub const InterruptError = Serial.SerialError;

var interrupt_table = [_]?InterruptHandler{null}**256;

// Add interrupt handler to table
pub fn add(n: u8, handler: InterruptHandler) void {
    interrupt_table[n] = handler;
}

// Remove interrupt handler
pub fn remove(n: u8) void {
    interrupt_table[n] = null;
}

// Default interrupt handler
fn default(ctx: *const InterruptContext) InterruptError!void {
    const tc = @import("term_color.zig");
    const out = Serial.writer();

    try out.print(tc.YELLOW, .{});
    try out.print("Interrupt: {0d} 0x{0x:0>2}, error: 0x{1x:0>8}",
        .{ctx.n, ctx.error_code});
    try out.print("\n" ++ tc.RESET, .{});
    try out.print("Registers:\n", .{});
    try ctx.regs.print(out);
    try ctx.frame.print(out);
}

// Handler for all interrupts
export fn interruptRouter(ctx: *InterruptContext) void {
    if (interrupt_table[ctx.n]) |handler| {
        handler(ctx) catch |err| {
            const out = Serial.writer();
            out.print("[isr] error at {}: {}\n", .{
                handler, err,
            }) catch {};
        };
    }
    else {
        default(ctx) catch {};
    }
}
