var count: u16 = 0x1c1c;
export fn _start() u32 {
    while (count != 0) {
        count +%= 1;
        asm volatile ("nop");
    }
    const status: u32 = 0x42;
    const n: u32 = 1;
    // `sys_exit` for linux
    asm volatile ("int $0x80"
        :: [n] "{eax}" (n),
        [status] "{ebx}" (status)
        : "eax", "ebx"
    );
    return status;
}
