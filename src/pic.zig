const PortIO = @import("io.zig").PortIO;

/// Programmable Interrupt Controller 8259

pub const IRQ_TIMER = 0x01;
pub const IRQ_KBD = 0x02;
pub const IRQ_CASCADE = 0x04;
pub const IRQ_COM2 = 0x08;
pub const IRQ_COM1 = 0x10;
pub const IRQ_LPT2 = 0x20;
pub const IRQ_FLOPPY = 0x40;
pub const IRQ_LPT1 = 0x80;

pub const PICChip = enum {
    master,
    slave,

    pub fn command(pic: PICChip) u16 {
        return switch (pic) {
            .master => 0x20,
            .slave => 0xA0,
        };
    }
    pub fn data(pic: PICChip) u16 {
        return switch (pic) {
            .master => 0x21,
            .slave => 0xA1,
        };
    }
};

const ICW1_ICW4 = 0x01;       // ICW4 (not) needed
const ICW1_SINGLE = 0x02;     // Single (cascade) mode
const ICW1_INTERVAL4 = 0x04;  // Call address interval 4 (8)
const ICW1_LEVEL = 0x08;      // Level triggered (edge) mode
const ICW1_INIT = 0x10;       // Initialization - required!

const ICW4_8086 = 0x01;       // 8086/88 (MCS-80/85) mode
const ICW4_AUTO = 0x02;       // Auto (normal) EOI
const ICW4_BUF_SLAVE = 0x08;  // Buffered mode/slave
const ICW4_BUF_MASTER = 0x0C; // Buffered mode/master
const ICW4_SFNM = 0x10;       // Special fully nested (not)

// vector offset
pub var offset = [2]u8 {0x08, 0x70};

pub fn remap(pic: PICChip, new_offset: u8) void {
    const mask = PortIO.in(u8, pic.data());

    // starts the initialization sequence (in cascade mode)
    PortIO.out(u8, pic.command(), ICW1_INIT | ICW1_ICW4);
    some_delay();
    PortIO.out(u8, pic.data(), new_offset);
    some_delay();
    switch (pic) {
        .master => PortIO.out(u8, pic.data(), 4),
        .slave => PortIO.out(u8, pic.data(), 2),
    }
    some_delay();
    PortIO.out(u8, pic.data(), ICW4_AUTO);
    some_delay();

    // restore saved mask
    PortIO.out(u8, pic.data(), mask);

    // set vector offset
    switch (pic) {
        .master => offset[0] = new_offset,
        .slave => offset[1] = new_offset,
    }
}

pub fn get_mask(pic: PICChip) u8 {
    return PortIO.in(u8, pic.data());
}

pub fn set_mask(pic: PICChip, mask: u8) void {
    PortIO.out(u8, pic.data(), mask);
    some_delay();
}

pub fn eoi(pic: PICChip) void {
    const master = PICChip.master;
    const slave = PICChip.slave;
    switch (pic) {
        .master => PortIO.out(u8, master.command(), 0x20),
        .slave => {
            PortIO.out(u8, master.command(), 0x20);
            PortIO.out(u8, slave.command(), 0x20);
        },
    }
    some_delay();
}

fn some_delay() void {
    var i: usize = 60000;
    while (i != 0) : (i -= 1) {
        asm volatile ("nop");
    }
}
