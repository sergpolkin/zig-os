const std = @import("std");

const Elf32_Shdr = std.elf.Elf32_Shdr;
const Elf32_Phdr = std.elf.Elf32_Phdr;

const paging = @import("paging.zig");
const PageAlign = paging.PageAlign;
const Page = paging.Page;

const native_endian = @import("builtin").target.cpu.arch.endian();

pub fn print(out: anytype, buf: []const u8) !void {
    var elf_stream = std.io.StreamSource{
        .const_buffer = std.io.fixedBufferStream(buf),
    };
    const hdr = try std.elf.Header.read(&elf_stream);
    if (hdr.is_64) return error.Elf64;

    try out.print("Entrypoint: 0x{x:0>8}\n", .{hdr.entry});
    try out.print("Sections:\n", .{});
    try out.print("{s:<8} {s:<8} {s:<8}\n", .{
        "Addr", "Off", "Size",
    });
    var sections = SectionHeaderIterator(@TypeOf(elf_stream)){
        .elf_header = hdr,
        .parse_source = elf_stream,
    };
    while (try sections.next()) |*s| {
        try out.print("{}\n", .{fmtSectionHeader(s)});
    }

    try out.print("Programs:\n", .{});
    try out.print("{s:<8} {s:<8} {s:<8} {s:<8} {s:<8} {s:<8} {s:<3}\n", .{
        "Type", "FileOff", "FileSz", "VAddr", "PAddr", "MemSz", "Flg",
    });
    var programs = ProgramHeaderIterator(@TypeOf(elf_stream)){
        .elf_header = hdr,
        .parse_source = elf_stream,
    };
    while (try programs.next()) |*p| {
        try out.print("{}\n", .{fmtProgramHeader(p)});
    }
}

pub const Program = struct {
    entry: u32,
    pages: []Page,
};

pub fn load(allocator: *std.mem.Allocator, buf: []const u8) !Program {
    var pages = std.ArrayList(Page).init(allocator);
    defer pages.deinit();

    var elf_stream = std.io.StreamSource{
        .const_buffer = std.io.fixedBufferStream(buf),
    };
    const hdr = try std.elf.Header.read(&elf_stream);
    if (hdr.is_64) return error.Elf64;

    var programs = ProgramHeaderIterator(@TypeOf(elf_stream)){
        .elf_header = hdr,
        .parse_source = elf_stream,
    };

    while (try programs.next()) |*p| {
        if (p.p_type == std.elf.PT_LOAD) {
            if (p.p_filesz >= PageAlign) return error.OutOfPage;
            var page = try allocator.allocAdvanced(u8, PageAlign, 4096, .at_least);
            // Copy data to page
            const off = p.p_vaddr & 0xfff;
            try elf_stream.seekableStream().seekTo(p.p_offset);
            try elf_stream.reader().readNoEof(page[off..off+p.p_filesz]);
            try pages.append(.{
                .pmem = page[0..4096],
                .vaddr = p.p_vaddr & 0xffff_f000,
                .flags = p.p_flags,
            });
        }
    }
    return Program{
        .entry = @truncate(u32, hdr.entry),
        .pages = pages.toOwnedSlice(),
    };
}

fn SectionHeaderIterator(ParseSource: anytype) type {
    return struct {
        elf_header: std.elf.Header,
        parse_source: ParseSource,
        index: usize = 0,

        pub fn next(self: *@This()) !?Elf32_Shdr {
            if (self.index >= self.elf_header.shnum) return null;
            defer self.index += 1;

            var shdr: Elf32_Shdr = undefined;
            const offset = self.elf_header.shoff + @sizeOf(@TypeOf(shdr)) * self.index;
            try self.parse_source.seekableStream().seekTo(offset);
            try self.parse_source.reader().readNoEof(std.mem.asBytes(&shdr));

            if (self.elf_header.endian != native_endian) {
                @panic("ELF endianness does NOT match");
            }

            return shdr;
        }
    };
}

const SectionFormatter = struct {
    pub fn f(
        s: *const Elf32_Shdr,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("{x:0>8} {x:0>8} {x:0>8}", .{
            s.sh_addr,
            s.sh_offset,
            s.sh_size,
        });
    }
};

fn fmtSectionHeader(s: *const Elf32_Shdr) std.fmt.Formatter(SectionFormatter.f) {
    return .{ .data = s };
}

fn ProgramHeaderIterator(ParseSource: anytype) type {
    return struct {
        elf_header: std.elf.Header,
        parse_source: ParseSource,
        index: usize = 0,

        pub fn next(self: *@This()) !?std.elf.Elf32_Phdr {
            if (self.index >= self.elf_header.phnum) return null;
            defer self.index += 1;

            var phdr: std.elf.Elf32_Phdr = undefined;
            const offset = self.elf_header.phoff + @sizeOf(@TypeOf(phdr)) * self.index;
            try self.parse_source.seekableStream().seekTo(offset);
            try self.parse_source.reader().readNoEof(std.mem.asBytes(&phdr));

            if (self.elf_header.endian != native_endian) {
                @panic("ELF endianness does NOT match");
            }

            return phdr;
        }
    };
}

const ProgramFormatter = struct {
    pub fn f(
        p: *const Elf32_Phdr,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        var flags: [3]u8 = .{'-'} ** 3;
        if (p.p_flags & std.elf.PF_R != 0) flags[0] = 'R';
        if (p.p_flags & std.elf.PF_W != 0) flags[1] = 'W';
        if (p.p_flags & std.elf.PF_X != 0) flags[2] = 'X';
        try writer.print("{x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {x:0>8} {s}", .{
            p.p_type,
            p.p_offset,
            p.p_filesz,
            p.p_vaddr,
            p.p_paddr,
            p.p_memsz,
            flags,
        });
    }
};

fn fmtProgramHeader(p: *const Elf32_Phdr) std.fmt.Formatter(ProgramFormatter.f) {
    return .{ .data = p };
}
