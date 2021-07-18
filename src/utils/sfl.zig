const Serial = @import("../io.zig").Serial;
const PortIO = @import("../io.zig").PortIO;

pub const magic_req = "sL5DdSMmkekro\n";
pub const magic_ack = "z6IHG7cYDID6o\n";

pub const Commands = enum(u8) {
    abort = 0,
    load = 1,
    jump = 2,
    _,
};

pub const ack_success = 'K';
pub const ack_crcerror = 'C';
pub const ack_unknown = 'U';
pub const ack_error = 'E';

pub const Error = error {
    Timeout,
    Cancelled,
    Abort,
    UnknownCommand,
};

payload_length: u8,
crc: u16,
cmd: u8,
payload: [255]u8,

const Self = @This();

pub fn receive(port: usize) !Self {
    var frame: Self = undefined;
    frame.payload_length = try Serial.read(port);
    frame.crc =
        @as(u16, try Serial.read(port)) |
        @as(u16, try Serial.read(port)) << 8;
    frame.cmd = try Serial.read(port);
    var i: usize = 0;
    const payload: [*]u8 = &frame.payload;
    while (i < frame.payload_length) : (i += 1) {
        payload[i] = try Serial.read(port);
    }
    // TODO check crc16
    return frame;
}

const Timer = struct {
    pub fn oneShot(val: u16) void {
        // Counter 0, Mode 0
        PortIO.out(u8, 0x43, 0b00110000);
        PortIO.out(u8, 0x40, @truncate(u8, val));
        PortIO.out(u8, 0x40, @truncate(u8, val>>8));
    }
    pub fn read() u16 {
        // Counter 0, latch
        PortIO.out(u8, 0x43, 0b00000000);
        const val: u16 =
            @as(u16, PortIO.in(u8, 0x40)) |
            @as(u16, PortIO.in(u8, 0x40)) << 8;
        return val;
    }
};

fn isCancelled(c: u8) bool {
    return c == 'Q' or c == '\x1b';
}

pub fn checkAck(port: usize) !void {
    var i: usize = 0;
    Timer.oneShot(0xFFFF);
    while (true) {
        if (try Serial.is_data_available(port)) {
            const c = try Serial.read(port);
            if (isCancelled(c)) {
                return Error.Cancelled;
            }
            else if (magic_ack[i] == c) {
                i += 1;
                if (i == magic_ack.len) {
                    break;
                }
            }
            else {
                i = if (magic_ack[0] == c) 1 else 0;
            }
        }
        // Read timer
        if (Timer.read() == 0) return Error.Timeout;
    }
}

pub fn clean(port: usize) !void {
    Timer.oneShot(0xFFFF);
    while (true) {
        if (try Serial.is_data_available(port)) {
            _ = try Serial.read(port);
            Timer.oneShot(0xFFFF);
        }
        // Read timer
        if (Timer.read() == 0) break;
    }
}
