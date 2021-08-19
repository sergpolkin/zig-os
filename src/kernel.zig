var count: u16 = 0x1c1c;
export fn _start() u32 {
    while (count != 0) {
        count +%= 1;
        asm volatile ("nop");
    }
    var n: u32 = undefined;
    // `sys_write` for linux
    n = 4;
    const stdout: usize = 1;
    const msg = "Hello world!\n";
    const status = asm volatile ("int $0x80"
        : [ret] "={eax}" (-> usize)
        : [n] "{eax}" (n),
          [fd] "{ebx}" (stdout),
          [ptr] "{ecx}" (msg),
          [size] "{edx}" (msg.len),
        : "memory"
    );
    // `sys_exit` for linux
    n = 1;
    _ = asm volatile ("int $0x80"
        : [ret] "={eax}" (-> usize)
        : [n] "{eax}" (n),
          [status] "{ebx}" (status)
        : "memory"
    );
    return status;
}
