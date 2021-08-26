const io = @import("io.zig");
const PortIO = io.PortIO;
const Serial = io.Serial;

const utils = @import("utils.zig");
const Paging = utils.Paging;

const interrupts = @import("interrupts.zig");
const InterruptContext = interrupts.InterruptContext;
const InterruptError = interrupts.InterruptError;

const PIC = @import("pic.zig");


const INTERRUPT_PAGEFAULT = 0x0e;
const INTERRUPT_KEYBOARD = 0x21;
const INTERRUPT_SERIAL0 = 0x23;
const INTERRUPT_SERIAL1 = 0x24;
const INTERRUPT_USER = 0x80;

extern var serialboot_mode: bool;
extern var ataboot_mode: bool;

pub fn init() void {
    interrupts.add(INTERRUPT_PAGEFAULT, isrPagefault);
    interrupts.add(INTERRUPT_KEYBOARD, isrKeyboard);
    interrupts.add(INTERRUPT_SERIAL0, isrSerial);
    interrupts.add(INTERRUPT_SERIAL1, isrSerial);
    interrupts.add(INTERRUPT_USER, isrUser);
}

fn isrUser(ctx: *InterruptContext) InterruptError!void {
    const out = Serial.writer();
    switch (ctx.regs.eax) {
        1 => {
            const status = ctx.regs.ebx;
            try out.print("[user] sys_exit: status {0} (0x{0x})\n", .{
                status,
            });
            ctx.regs.eax = status;
        },
        4 => {
            const fd = ctx.regs.ebx;
            const len = ctx.regs.edx;
            const msg = @intToPtr([*]const u8, ctx.regs.ecx);
            try out.print("[user] sys_write[{}]: {s}\n", .{
                fd,
                msg[0..len],
            });
            ctx.regs.eax = len;
        },
        else => {
            try out.print("[user] unsupported interrupt 0x{x}\n", .{
                ctx.regs.eax,
            });
        },
    }
}

fn isrKeyboard(ctx: *InterruptContext) InterruptError!void {
    const tc = @import("term_color.zig");
    const out = Serial.writer();

    const KBD_COMMAND = 0x64;
    const KBD_DATA = 0x60;
    const status = PortIO.in(u8, KBD_COMMAND);
    const scancode = if (status & 1 !=0) PortIO.in(u8, KBD_DATA) else null;
    try out.print(tc.WHITE, .{});
    if (scancode) |_| {
        try out.print("Keyboard status: 0x{x:0>2}, ", .{status});
        try out.print("scancode: 0x{x:0>2} ", .{scancode.?});
    }
    else {
        try out.print("Keyboard status: 0x{x:0>2}", .{status});
    }
    try out.print("\n" ++ tc.RESET, .{});
    if (scancode) |_| {
        switch (scancode.?) {
            // '1' - serialboot request
            0x82 => serialboot_mode = true,
            // '2' - ataboot request
            0x83 => ataboot_mode = true,
            else => {},
        }
    }
    // Send EOI
    PIC.eoi(.master);
}

fn isrSerial(ctx: *InterruptContext) InterruptError!void {
    const out = Serial.writer();

    const port = switch (ctx.n) {
        INTERRUPT_SERIAL0 => blk: {
            const is_com2 = Serial.is_data_available(1) catch false;
            const is_com4 = Serial.is_data_available(3) catch false;
            if (is_com2) break :blk @as(usize, 1)
            else if (is_com4) break :blk @as(usize, 3)
            else @panic("serial_handler: IRQ#23 error");
        },
        INTERRUPT_SERIAL1 => blk: {
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
        '2' => {
            try out.print("Serial port {}: ataboot request.\n", .{port});
            ataboot_mode = true;
        },
        else => try out.print("Serial port {}: 0x{x:0>2}\n", .{port, data}),
    }
    // Send EOI
    PIC.eoi(.master);
}

fn isrPagefault(ctx: *InterruptContext) InterruptError!void {
    const out = Serial.writer();

    const cr2 = Paging.readCR2();
    try out.print("Pagefault at 0x{x:0>8}\n", .{cr2});
    @panic("Pagefault!");
}
