pub fn out(comptime T: type, io: u16, val: T) void {
    switch (@typeInfo(T)) {
        .Int => switch (@typeInfo(T).Int.bits) {
            8 => asm volatile ("outb %%al, %%dx"
                :: [io] "{dx}" (io), [val] "{al}" (val),
                : "eax", "edx"),
            32 => asm volatile ("out %%eax, %%dx"
                :: [io] "{dx}" (io), [val] "{eax}" (val),
                : "eax", "edx"),
            else => @compileError("Only 8 and 32 bits access supported."),
        },
        else => @compileError("Unsupported type '" ++ @typeName(T) ++ "'."),
    }
}

pub fn in(comptime T: type, io: u16) T {
    return switch (@typeInfo(T)) {
        .Int => switch (@typeInfo(T).Int.bits) {
            8 => asm volatile ("inb %%dx, %%al"
                : [ret] "={al}" (-> T)
                : [io] "{dx}" (io)
                : "eax", "edx"),
            32 => asm volatile ("in %%dx, %%eax"
                : [ret] "={eax}" (-> T)
                : [io] "{dx}" (io)
                : "eax", "edx"),
            else => @compileError("Only 8 and 32 bits access supported."),
        },
        else => @compileError("Unsupported type '" ++ @typeName(T) ++ "'."),
    };
}
