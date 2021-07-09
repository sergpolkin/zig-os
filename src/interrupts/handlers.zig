
const FnHandler = fn() align(16) callconv(.Naked) noreturn;

pub const InterruptFrame = packed struct {
    eip: u32,
    cs: u32,
    eflags: u32,

    pub fn print(self: *const @This(), writer: anytype) !void {
        const msg =
            \\eip {x:0>8}
            \\eflags {x:0>8} cs {x:0>8}
            \\
        ;
        try writer.print(msg, .{self.eip, self.eflags, self.cs});
    }
};

// Structure containing all registers at the state of the interrupt
pub const RegsState = packed struct {
    ebp: u32,
    edi: u32,
    esi: u32,
    edx: u32,
    ecx: u32,
    ebx: u32,
    eax: u32,

    pub fn print(self: *const @This(), writer: anytype) !void {
        const msg =
            \\eax {x:0>8} ecx {x:0>8} edx {x:0>8} ebx {x:0>8}
            \\esp ???????? ebp {x:0>8} esi {x:0>8} edi {x:0>8}
            \\
        ;
        try writer.print(msg, .{
            self.eax, self.ecx, self.edx, self.ebx,
            self.ebp, self.esi, self.edi,
        });
    }
};

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
                \\mov %%esp, %%ecx
                \\lea 0x1c(%%esp), %%ebx
                \\push $0x103
                \\push %%ecx
                \\push %%ebx
                \\push %%eax
                \\call interrupt_handler
                \\mov %%ebp, %%esp
                ::
                [n] "{al}" (@as(u8, N))
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
