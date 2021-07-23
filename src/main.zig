const std = @import("std");
const builtin = @import("builtin");

const os = @import("os.zig");
const utils = @import("utils.zig");
const Elf = utils.Elf;
const Paging = utils.Paging;

const io = @import("io.zig");
const PortIO = io.PortIO;
const Serial = io.Serial;

const interrupts = @import("interrupts.zig");
const InterruptContext = interrupts.InterruptContext;

const mm = @import("mm.zig");

const PIC = @import("pic.zig");

const display = @intToPtr([*]volatile u16, 0xb8000);

// some color codes for terminal
const COLOR_RED = "\x1b[31;1m";
const COLOR_GREEN = "\x1b[32;1m";
const COLOR_YELLOW = "\x1b[33;1m";
const COLOR_MAGENTA = "\x1b[35;1m";
const COLOR_WHITE = "\x1b[37;1m";
const COLOR_RESET = "\x1b[0m";

var serialboot_mode: bool = false;

export fn main(arg: u32) align(16) callconv(.C) noreturn {
    // "Zig"
    display[80 + 0] = 0x0a5a;
    display[80 + 1] = 0x0a69;
    display[80 + 2] = 0x0a67;

    os.init() catch {
        @panic("OS init error!");
    };

    interrupt_test();

    Paging.init(mm.GlobalAllocator) catch @panic("Paging init error!");

    if (is_ok(arg)) {
        // "OK"
        display[160 + 0] = 0x0f4f;
        display[160 + 1] = 0x0f4b;
        const out = Serial.writer();
        out.print(COLOR_GREEN ++ "OK\n" ++ COLOR_RESET, .{}) catch {};
    }

    while (true) {
        const out = Serial.writer();
        if (serialboot_mode) {
            defer serialboot_mode = false;
            asm volatile ("cli");
            // Boot from 'COM2'
            const port = 1;
            const allocator = mm.GlobalAllocator;
            const buf = utils.serialboot(allocator, port) catch |err| {
                const msg = COLOR_RED ++ "serialboot {}.\n" ++ COLOR_RESET;
                out.print(msg, .{err}) catch {};
                continue;
            };
            defer allocator.free(buf);
            out.print("serialboot is done: {*} {} bytes.\n",
                .{buf.ptr, buf.len}) catch {};
            const r = execElf(buf, out) catch |err| {
                const msg = COLOR_RED ++ "ELF exec {}.\n" ++ COLOR_RESET;
                out.print(msg, .{err}) catch {};
                continue;
            };
            const msg = COLOR_GREEN ++ "Exit code: 0x{x}\n" ++ COLOR_RESET;
            out.print(msg, .{r}) catch {};
        }
        out.print(COLOR_MAGENTA ++ "CPU halt.\n" ++ COLOR_RESET, .{}) catch {};
        asm volatile ("sti");
        asm volatile ("hlt");
    }
}

fn execElf(buf: []const u8, out: anytype) !u32 {
    var arena = std.heap.ArenaAllocator.init(mm.GlobalAllocator);
    defer arena.deinit();
    const allocator = &arena.allocator;
    // Load elf
    const prog = try Elf.load(allocator, buf);
    try out.print("Entrypoint: 0x{x:0>8}\n", .{prog.entry});
    // Map `prog` to virtual memory
    for (prog.pages) |*p| {
        try out.print("Page: {}\n", .{p});
        p.map(allocator) catch @panic("Page mapping error.");
    }
    Paging.loadPD();
    // Execute
    const r = asm volatile ("call *%[entry]"
        : [ret] "={eax}" (-> u32)
        : [entry] "{eax}" (prog.entry)
        : "eax", "memory"
    );
    // Clear virtual memory, except first 4 MiB
    Paging.clearPD();
    return r;
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
    if (scancode) |_| {
        switch (scancode.?) {
            // '1' - serialboot request
            0x82 => serialboot_mode = true,
            else => {},
        }
    }
    // Send EOI
    PIC.eoi(.master);
}

fn serial_handler(out: anytype, n: u32) !void {
    const port = switch (n) {
        0x23 => blk: {
            const is_com2 = Serial.is_data_available(1) catch false;
            const is_com4 = Serial.is_data_available(3) catch false;
            if (is_com2) break :blk @as(usize, 1)
            else if (is_com4) break :blk @as(usize, 3)
            else @panic("serial_handler: IRQ#23 error");
        },
        0x24 => blk: {
            const is_com1 = Serial.is_data_available(0) catch false;
            const is_com3 = Serial.is_data_available(2) catch false;
            if (is_com1) break :blk @as(usize, 0)
            else if (is_com3) break :blk @as(usize, 2)
            else @panic("serial_handler: IRQ#24 error");
        },
        else => @panic("serial_handler: IRQ error"),
    };
    const data = Serial.read(port) catch unreachable;
    switch (data) {
        '1' => {
            try out.print("Serial port {}: serialboot request.\n", .{port});
            serialboot_mode = true;
        },
        else => try out.print("Serial port {}: 0x{x:0>2}\n", .{port, data}),
    }
    // Send EOI
    PIC.eoi(.master);
}

fn pagefault_handler(out: anytype) !void {
    const cr2 = Paging.readCR2();
    try out.print("Pagefault at 0x{x:0>8}\n", .{cr2});
    @panic("Pagefault!");
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
        // 'Page Fault'
        0x0e => pagefault_handler(out) catch {},
        // 'Keyboard'
        0x21 => keyboard_handler(out) catch {},
        // 'COM1-COM4'
        0x23, 0x24 => serial_handler(out, ctx.n) catch {},
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
