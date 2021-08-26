const std = @import("std");
const builtin = @import("builtin");

const os = @import("os.zig");
const utils = @import("utils.zig");
const Elf = utils.Elf;
const Paging = utils.Paging;

const io = @import("io.zig");
const Serial = io.Serial;

const mm = @import("mm.zig");

const isr = @import("isr.zig");

const display = @intToPtr([*]volatile u16, 0xb8000);

const tc = @import("term_color.zig");

export var serialboot_mode: bool = false;
export var ataboot_mode: bool = false;

// Kernel offset in `image.bin`
// From 'tools/gen_image.py'
const KERNEL_OFFSET = 1024 * 512;

export fn main(arg: u32) align(16) callconv(.C) noreturn {
    // "Zig"
    display[80 + 0] = 0x0a5a;
    display[80 + 1] = 0x0a69;
    display[80 + 2] = 0x0a67;

    os.init() catch {
        @panic("OS init error!");
    };

    interrupt_test();

    isr.init();

    Paging.init(mm.GlobalAllocator) catch @panic("Paging init error!");

    if (is_ok(arg)) {
        // "OK"
        display[160 + 0] = 0x0f4f;
        display[160 + 1] = 0x0f4b;
        const out = Serial.writer();
        out.print(tc.GREEN ++ "OK\n" ++ tc.RESET, .{}) catch {};
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
                const msg = tc.RED ++ "serialboot {}.\n" ++ tc.RESET;
                out.print(msg, .{err}) catch {};
                continue;
            };
            defer allocator.free(buf);
            out.print("serialboot is done: {*} {} bytes.\n",
                .{buf.ptr, buf.len}) catch {};
            const r = execElf(buf, out) catch |err| {
                const msg = tc.RED ++ "ELF exec {}.\n" ++ tc.RESET;
                out.print(msg, .{err}) catch {};
                continue;
            };
            const msg = tc.GREEN ++ "Exit code: 0x{x}\n" ++ tc.RESET;
            out.print(msg, .{r}) catch {};
        }

        if (ataboot_mode) {
            defer ataboot_mode = false;
            asm volatile ("cli");
            const allocator = mm.GlobalAllocator;
            const buf = utils.ataboot(allocator, KERNEL_OFFSET) catch |err| {
                const msg = tc.RED ++ "ataboot {}.\n" ++ tc.RESET;
                out.print(msg, .{err}) catch {};
                continue;
            };
            defer allocator.free(buf);
            out.print("ataboot is done: {*} {} bytes.\n",
                .{buf.ptr, buf.len}) catch {};
            const r = execElf(buf, out) catch |err| {
                const msg = tc.RED ++ "ELF exec {}.\n" ++ tc.RESET;
                out.print(msg, .{err}) catch {};
                continue;
            };
            const msg = tc.GREEN ++ "Exit code: 0x{x}\n" ++ tc.RESET;
            out.print(msg, .{r}) catch {};
        }

        out.print(tc.MAGENTA ++ "CPU halt.\n" ++ tc.RESET, .{}) catch {};
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
    out.print(tc.RED ++ "PANIC \"{s}\"\n" ++ tc.RESET, .{
        msg,
    }) catch {};

    while(true) {
        asm volatile ("hlt");
    }
}
