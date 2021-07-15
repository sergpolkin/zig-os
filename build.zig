const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = .{
        .cpu_arch = .i386,
        .cpu_model = .{ .explicit = &std.Target.x86.cpu._i586 },
        .os_tag = .freestanding,
        .abi = .none,
    };

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const stage0_file = "zig-cache/stage0.obj";
    const stage0 = b.addSystemCommand(&[_][]const u8{
        "nasm",
        "-felf32",
        "-o", stage0_file,
        "-isrc/bootloader",
        "src/bootloader/stage0.asm",
    });

    const stage1 = b.addExecutable("stage1", "src/main.zig");
    stage1.setTarget(target);
    stage1.setBuildMode(mode);
    stage1.setLinkerScriptPath("linker.ld");
    stage1.addObjectFile(stage0_file);
    stage1.step.dependOn(&stage0.step);

    const stage1_obj = b.addInstallArtifact(stage1);
    b.installArtifact(stage1_obj.artifact);

    const image = b.addSystemCommand(&[_][]const u8{
        "objcopy",
        "-Obinary",
        b.getInstallPath(stage1_obj.dest_dir, stage1.out_filename),
        "image.bin",
    });
    image.step.dependOn(&stage1.step);

    b.default_step.dependOn(&image.step);

    const qemu = b.addSystemCommand(&[_][]const u8{
        "qemu-system-i386",
        "-drive", "if=ide,format=raw,file=image.bin",
    } ++ qemu_serial_conf);
    qemu.step.dependOn(b.getInstallStep());

    const run_qemu = b.step("run", "Run in qemu");
    run_qemu.dependOn(&qemu.step);
}

const qemu_serial_conf = [_][]const u8{
    "-chardev", "stdio,id=com1",
    "-chardev", "vc,id=com2",
    "-chardev", "vc,id=com3",
    "-chardev", "vc,id=com4",
    "-serial", "chardev:com1",
    "-serial", "chardev:com2",
    "-serial", "chardev:com3",
    "-serial", "chardev:com4",
};
