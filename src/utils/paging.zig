const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PageAlign = 4096;
pub const Page = struct {
    pmem: *align(PageAlign) [4096]u8,
    vaddr: u32,
    flags: u32,

    const Self = @This();

    pub fn map(self: *const Self, allocator: *Allocator) !void {
        var pt = try getPageTable(allocator, self.vaddr);
        const Mask = ~@as(u32, 0xffc00000);
        const pte_idx = (self.vaddr & Mask) >> 12;
        var pte = &pt[pte_idx];
        const attr: u32 = if (self.flags & std.elf.PF_W != 0) 3 else 1;
        pte.* = @ptrToInt(self.pmem) | attr;
    }

    pub fn format(
        self: *const Self,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        var flags: [3]u8 = .{'-'} ** 3;
        if (self.flags & std.elf.PF_R != 0) flags[0] = 'R';
        if (self.flags & std.elf.PF_W != 0) flags[1] = 'W';
        if (self.flags & std.elf.PF_X != 0) flags[2] = 'X';
        try writer.print("padr 0x{x:0>8} | vadr 0x{x:0>8} | {s}", .{
            @ptrToInt(self.pmem),
            self.vaddr,
            flags,
        });
    }
};

/// Page Directory
pub var pd: ?*align(PageAlign) [1024]u32 = null;

const PageTable = *align(PageAlign) [1024]u32;

pub fn init(allocator: *Allocator) !void {
    if (pd != null) @panic("Page Directory already init.");
    // Allocate PD
    pd = (try allocator.allocAdvanced(u32, PageAlign, 1024, .exact))[0..1024];
    // Set each PDE to not present
    for (pd.?) |*pde| {
        // This sets the following flags to the pages:
        //   Supervisor: Only kernel-mode can access them
        //   Write Enabled: It can be both read from and written to
        //   Not Present: The page table is not present
        pde.* = 0x0000_0002;
    }
    var pt = try allocator.allocAdvanced(u32, PageAlign, 1024, .exact);
    // Mapping first 4MiB
    for (pt) |*pte, i| {
        // attributes: supervisor level, read/write, present.
        const attr = 3;
        pte.* = (i * 0x1000) | attr;
    }
    // Load to page directory
    // attributes: supervisor level, read/write, present
    pd.?[0] = @ptrToInt(pt.ptr) | 3;

    loadPD();

    // Enable paging
    asm volatile (
        \\mov %%cr0, %%eax
        \\or $0x80000000, %%eax
        \\mov %%eax, %%cr0
        ::: "eax"
    );
}

pub fn loadPD() void {
    asm volatile ("mov %%eax, %%cr3"
        :: [pd] "{eax}" (@ptrToInt(pd))
        : "eax"
    );
}

pub fn clearPD() void {
    for (pd.?[1..1024]) |*pde| {
        pde.* = 0x0000_0002;
    }
    loadPD();
}

fn getPageTable(allocator: *Allocator, vaddr: u32) !PageTable {
    if (pd == null) return error.PageDirectoryNull;
    const pde_idx = vaddr >> 22;
    var pde: *u32 = &pd.?[pde_idx];
    var pt: PageTable = undefined;
    // if PDE not present, create new page table
    if (pde.* & 1 == 0) {
        pt = (try allocator.allocAdvanced(u32, PageAlign, 1024, .exact))[0..1024];
        for (pt) |*pte| {
            pte.* = 0;
        }
        // Add PDE with new page table
        // attributes: supervisor level, read/write, present
        pde.* = @ptrToInt(pt) | 3;
    }
    else {
        const Mask = ~@as(u32, 0xFFF);
        pt = @intToPtr(PageTable, pde.* & Mask);
    }
    return pt;
}

pub fn readCR0() u32 {
    return asm volatile ("mov %%cr0, %[ret]"
        : [ret] "={eax}" (-> u32)
        :: "eax"
    );
}

pub fn readCR2() u32 {
    return asm volatile ("mov %%cr2, %[ret]"
        : [ret] "={eax}" (-> u32)
        :: "eax"
    );
}

pub fn readCR3() u32 {
    return asm volatile ("mov %%cr3, %[ret]"
        : [ret] "={eax}" (-> u32)
        :: "eax"
    );
}

