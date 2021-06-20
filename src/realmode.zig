pub const RegisterState = packed struct {
    eax: u32 = 0,
    ecx: u32 = 0,
    edx: u32 = 0,
    ebx: u32 = 0,
    esp: u32 = 0,
    ebp: u32 = 0,
    esi: u32 = 0,
    edi: u32 = 0,
    efl: u32 = 0,
    es:  u16 = 0,
    ds:  u16 = 0,
    fs:  u16 = 0,
    gs:  u16 = 0,
    ss:  u16 = 0,
};

extern fn _invoke_realmode(int_number: u8, regs: u32) callconv(.C) void;

pub fn invoke(int_number: u8, regs: *RegisterState) void {
    _invoke_realmode(int_number, @ptrToInt(regs));
}
