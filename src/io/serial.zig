const std = @import("std");

const PortIO = @import("port.zig");

// BIOS Data Area (BDA)
const bda_base = 0x0400;

// address IO ports for COM1-COM4 (`null` if not present)
pub var ports: [4]?u16 = undefined;

pub const IRQ_AVAIL = 1;   // Data available
pub const IRQ_EMPTY = 2;   // Transmitter empty
pub const IRQ_ERROR = 4;   // Break/error
pub const IRQ_STATUS = 8;  // Status change

pub fn init() void {
    for (@intToPtr(*const [4]u16, bda_base)) |addr, id| {
        if (addr == 0) {
            ports[id] = null;
            continue;
        }

        PortIO.out(u8, addr + 1, 0x00); // Disable all interrupts
        PortIO.out(u8, addr + 3, 0x80); // Enable DLAB
        PortIO.out(u8, addr + 0, 0x01); // Low byte divisor (115200 baud)
        PortIO.out(u8, addr + 1, 0x00); // High byte divisor
        PortIO.out(u8, addr + 3, 0x03); // 8 bits, 1 stop bit, no parity
        PortIO.out(u8, addr + 4, 0x03); // RTS/DSR set

        ports[id] = addr;
    }
}

pub fn get_irq(port: usize) SerialError!u8 {
    if (ports[port]) |addr| {
        return PortIO.in(u8, addr + 1);
    }
    else return error.NotPresent;
}

pub fn set_irq(port: usize, irq: u8) SerialError!void {
    if (ports[port]) |addr| {
        PortIO.out(u8, addr + 1, irq);
    }
    else return error.NotPresent;
}

pub fn read(port: usize) SerialError!u8 {
    if (ports[port]) |addr| {
        while (!(try is_data_available(port))) {}
        return PortIO.in(u8, addr);
    }
    else return error.NotPresent;
}

pub fn is_data_available(port: usize) SerialError!bool {
    if (ports[port]) |addr| {
        return PortIO.in(u8, addr + 5) & 0x01 != 0;
    }
    else return error.NotPresent;
}

pub fn is_transmit_empty(port: usize) SerialError!bool {
    if (ports[port]) |addr| {
        return PortIO.in(u8, addr + 5) & 0x20 != 0;
    }
    else return error.NotPresent;
}

pub fn write(port: usize, val: u8) SerialError!void {
    if (ports[port]) |addr| {
        while (!(try is_transmit_empty(port))) {}
        PortIO.out(u8, addr, val);
    }
    else return error.NotPresent;
}

pub const SerialError = error {
    NotPresent,
};

fn write_to_all(ctx: void, bytes: []const u8) SerialError!usize {
    for (bytes) |c| {
        for (ports) |_, id| {
            if (c == '\n') write(id, '\r') catch continue;
            write(id, c) catch continue;
        }
    }
    return bytes.len;
}

pub const Writer = std.io.Writer(void, SerialError, write_to_all);

pub fn writer() Writer {
    return .{ .context = {}};
}
