
extern fn interrupt_handler(u8, u32, u32, u32) void;

const FnHandler = fn() align(16) callconv(.Naked) noreturn;

// Create entry points for all interrupts
pub const handlers = blk: {
    const N = 256;
    var fns: [N]FnHandler = undefined;
    inline for (fns) |*f, i| {
        f.* = handler_init(i);
    }
    break :blk fns;
};

fn handler_init(comptime N: usize) FnHandler {
    const impl = struct {
        fn inner() align(16) callconv(.Naked) noreturn {
            asm volatile (
                \\push %%eax
                \\push %%ebx
                \\push %%ecx
                \\push %%edx
                \\push %%esi
                \\push %%edi
                \\push %%ebp
                ::: "memory"
            );
            asm volatile (
                \\mov %%esp, %%ebp
                \\push %%edx
                \\push %%ecx
                \\push %%ebx
                \\push %%eax
                \\call interrupt_handler
                \\mov %%ebp, %%esp
                ::
                [n] "{al}" (@as(u8, N)),
                [arg1] "{ebx}" (@as(u32, 0x101)),
                [arg2] "{ecx}" (@as(u32, 0x102)),
                [arg3] "{edx}" (@as(u32, 0x103))
                : "memory"
            );
            asm volatile (
                \\pop %%ebp
                \\pop %%edi
                \\pop %%esi
                \\pop %%edx
                \\pop %%ecx
                \\pop %%ebx
                \\pop %%eax
                ::: "memory"
            );
            while (true) {
                asm volatile ("iret");
            }
        }
    };
    return impl.inner;
}
