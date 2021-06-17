export fn main(arg: u32) align(16) callconv(.C) noreturn {
    const display = @intToPtr([*]volatile u16, 0xb8000);

    // "Zig"
    display[80 + 0] = 0x0f5a;
    display[80 + 1] = 0x0f69;
    display[80 + 2] = 0x0f67;

    if (is_ok(arg)) {
        // "OK"
        display[160 + 0] = 0x0f4f;
        display[160 + 1] = 0x0f4b;
    }

    while (true) {
        asm volatile ("hlt");
    }
}

fn is_ok(arg: u32) bool {
    return arg == 0x12345678;
}
