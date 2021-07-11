
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

pub const InterruptContext = packed struct {
    n: u32,
    error_code: u32,
    frame: *InterruptFrame,
    regs: *RegsState,
};

export fn zig_entry() align(16) callconv(.Naked) void {
    asm volatile (
        \\push 12(%%ecx)
        \\push 8(%%ecx)
        \\push 4(%%ecx)
        \\push 0(%%ecx)
        \\push %%esi
        \\push %%edi
        \\push %%ebp
        ::: "memory"
    );
    asm volatile (
        \\push %%esp              # all registers state
        \\push %%edx              # interrupt frame
        \\push %%ebx              # error code
        \\push %%eax              # interrupt number
        \\mov %%esp, %%ebp
        \\push %%esp              # interrupt context
        \\call interrupt_handler
        \\mov %%ebp, %%esp
        \\add $16, %%esp          # 'pop' of interrupt context
        ::: "memory"
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
}

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
    const has_error_code = switch (N) {
        8, 10, 11, 12, 13, 14, 17 => true,
        else => false,
    };
    const impl = struct {
        fn inner() align(16) callconv(.Naked) noreturn {
            asm volatile (
                \\push %%eax
                \\push %%ebx
                \\push %%ecx
                \\push %%edx
                \\mov %%esp, %%ecx
            );
            if (has_error_code) {
                asm volatile ("lea 20(%%ecx), %%edx");
                asm volatile ("mov 16(%%ecx), %%ebx");
            }
            else {
                asm volatile ("lea 16(%%ecx), %%edx");
                asm volatile ("xor %%ebx, %%ebx");
            }
            asm volatile ("call zig_entry" ::
                [n] "{eax}" (@as(u32, N))
                : "memory"
            );
            // 'pop' off the error code and registers
            if (has_error_code) {
                asm volatile ("add $20, %%esp");
            }
            else {
                asm volatile ("add $16, %%esp");
            }
            while (true) {
                asm volatile ("iret");
            }
        }
    };
    return impl.inner;
}
