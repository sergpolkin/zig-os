const std = @import("std");

const PortIO = @import("port.zig");

/// ATA Bus:
///   Primary:   BAR0: 0x1F0, BAR1: 0x3F4
///   Secondary: BAR0: 0x170, BAR1: 0x374

pub const Bus = enum { Primary, Secondary };
pub const Drive = enum { Master, Slave };

pub fn PIODevice(comptime bus: Bus, comptime drv: Drive) type {
    return struct {
        const BAR0 = switch (bus) {
            .Primary   => 0x1F0,
            .Secondary => 0x170,
        };
        const BAR1 = switch (bus) {
            .Primary   => 0x3F4,
            .Secondary => 0x374,
        };

        const PIO_DATA = BAR0 + 0;
        const PIO_ERROR = BAR0 + 1;
        const PIO_SECTOR_COUNT = BAR0 + 2;

        const PIO_LBA0 = BAR0 + 3;
        const PIO_LBA1 = BAR0 + 4;
        const PIO_LBA2 = BAR0 + 5;

        const PIO_SELECT  = BAR0 + 6;

        const PIO_COMMAND = BAR0 + 7;
        const PIO_STATUS  = BAR0 + 7;

        const PIO_CONTROL = BAR1 + 2;
        const PIO_ALTSTATUS = BAR1 + 2;

        const ATAError = error {
            NotExist,
            NotATA,
            TransferError,
        };

        const Self = @This();

        block_count: u64,

        pub fn init() ATAError!Self {
            var self: Self = undefined;
            irqDisable();
            if (altStatus() == 0) return ATAError.NotExist;
            var ident: [256]u16 = undefined;
            try self.identify(@ptrCast(*[512]u8, &ident));
            const lba = LBAInfo.parse(&ident);
            if (!lba.lba48) return ATAError.NotATA;
            self.block_count = lba.block_count;
            return self;
        }

        fn irqDisable() void {
            PortIO.out(u8, PIO_CONTROL, 0x02);
        }
        // Alternate Status
        fn altStatus() u8 {
            return PortIO.in(u8, PIO_ALTSTATUS);
        }

        pub fn identify(self: *Self, buf: []u8) ATAError!void {
            const ATA_IDENTIFY = 0xEC;

            PortIO.out(u8, PIO_SELECT, switch (drv) {
                .Master => 0xA0,
                .Slave  => 0xB0,
            });

            PortIO.out(u8, PIO_SECTOR_COUNT, 0);
            PortIO.out(u8, PIO_LBA0, 0);
            PortIO.out(u8, PIO_LBA1, 0);
            PortIO.out(u8, PIO_LBA2, 0);

            PortIO.out(u8, PIO_COMMAND, ATA_IDENTIFY);

            var status = PortIO.in(u8, PIO_STATUS);
            if (status == 0) return ATAError.NotExist;
            // wait while BSY
            while (true) {
                status = PortIO.in(u8, PIO_STATUS);
                if (status & 0x80 == 0) break;
                const midLBA = PortIO.in(u8, PIO_LBA1);
                const hiLBA  = PortIO.in(u8, PIO_LBA2);
                if (midLBA != 0 or hiLBA != 0) return ATAError.NotATA;
            }
            // wait while DRQ or ERR
            while (true) {
                status = PortIO.in(u8, PIO_STATUS);
                if (status & 0x08 != 0) break;
                if (status & 0x01 != 0) return ATAError.TransferError;
            }
            var tmp: [256]u16 = undefined;
            for (tmp) |*data| {
                data.* = PortIO.in(u16, PIO_DATA);
            }
            std.mem.copy(u8, buf, @ptrCast(*const [512]u8, &tmp));
        }

        pub fn read(self: *Self, block: u64, buf: []u8) ATAError!void {
            const ATA_READ_EXT = 0x24;

            PortIO.out(u8, PIO_SELECT, switch (drv) {
                .Master => 0x40,
                .Slave  => 0x50,
            });

            // sectorcount high byte
            PortIO.out(u8, PIO_SECTOR_COUNT, 0);
            // LBA 6:4
            PortIO.out(u8, PIO_LBA0, @truncate(u8, block >> 24));
            PortIO.out(u8, PIO_LBA1, @truncate(u8, block >> 32));
            PortIO.out(u8, PIO_LBA2, @truncate(u8, block >> 40));
            // sectorcount low byte
            PortIO.out(u8, PIO_SECTOR_COUNT, 1);
            // LBA 3:1
            PortIO.out(u8, PIO_LBA0, @truncate(u8, block));
            PortIO.out(u8, PIO_LBA1, @truncate(u8, block >> 8));
            PortIO.out(u8, PIO_LBA2, @truncate(u8, block >> 16));

            PortIO.out(u8, PIO_COMMAND, ATA_READ_EXT);

            var status = PortIO.in(u8, PIO_STATUS);
            if (status == 0) return ATAError.NotExist;
            // wait while BSY
            while (true) {
                status = PortIO.in(u8, PIO_STATUS);
                if (status & 0x80 == 0) break;
            }
            // wait while DRQ
            var trys: usize = 1000;
            while (true) {
                status = PortIO.in(u8, PIO_STATUS);
                if (status & 0x08 != 0) break;
                if (trys == 0) return ATAError.TransferError;
                trys -= 1;
            }
            var tmp: [256]u16 = undefined;
            for (tmp) |*data| {
                data.* = PortIO.in(u16, PIO_DATA);
            }
            std.mem.copy(u8, buf, @ptrCast(*const [512]u8, &tmp));
        }
    };
}

const LBAInfo = struct {
    lba48: bool,
    block_count: u64,

    const Self = @This();

    pub fn parse(ident: *const [256]u16) Self {
        var info = Self {
            .lba48 = false,
            .block_count = 0,
        };
        const lba48_capable = ident[83] & 0x400 != 0;
        if (lba48_capable) {
            info.lba48 = true;
            info.block_count =
                @as(u64, ident[103]) << 48 |
                @as(u64, ident[102]) << 32 |
                @as(u32, ident[101]) << 16 |
                ident[100];
        }
        else {
            info.block_count =
                @as(u32, ident[61]) << 16 |
                ident[60];
        }
        return info;
    }
};
