const std = @import("std");

const Builder = std.build.Builder;
const LibExeObjStep = std.build.LibExeObjStep;
const Step = std.build.Step;

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

    const bootloader = buildBootloader(b);
    bootloader.setTarget(target);
    bootloader.setBuildMode(mode);

    const kernel = buildKernel(b);
    kernel.setTarget(target);

    const image = generateImage(b, bootloader, kernel, "image.bin");

    b.default_step.dependOn(image);

    const qemu = b.addSystemCommand(&[_][]const u8{
        "qemu-system-i386",
        "-drive", "if=ide,format=raw,file=image.bin",
    } ++ qemu_serial_conf);
    qemu.step.dependOn(b.getInstallStep());

    const run_qemu = b.step("run", "Run in qemu");
    run_qemu.dependOn(&qemu.step);
}

fn buildBootloader(b: *Builder) *LibExeObjStep {
    const stage0_file = "zig-cache/stage0.obj";
    const stage0 = b.addSystemCommand(&[_][]const u8{
        "nasm",
        "-felf32",
        "-o", stage0_file,
        "-isrc/bootloader",
        "src/bootloader/stage0.asm",
    });

    const stage1 = b.addExecutable("bootloader", "src/main.zig");
    stage1.setLinkerScriptPath("linker.ld");
    stage1.addObjectFile(stage0_file);
    stage1.step.dependOn(&stage0.step);
    stage1.install();
    return stage1;
}

fn buildKernel(b: *Builder) *LibExeObjStep {
    const kernel = b.addExecutable("kernel", "src/kernel.zig");
    kernel.setBuildMode(.Debug);
    kernel.image_base = 0x4200_0000;
    kernel.strip = true;
    kernel.install();
    return kernel;
}

fn generateImage(
    b: *Builder,
    bootloader: *LibExeObjStep,
    kernel: *LibExeObjStep,
    output: []const u8,
) *Step {
    if (bootloader.install_step == null) unreachable;
    if (kernel.install_step == null) unreachable;
    const bootloader_path = b.getInstallPath(
        bootloader.install_step.?.dest_dir,
        bootloader.out_filename,
    );
    const kernel_path = b.getInstallPath(
        kernel.install_step.?.dest_dir,
        kernel.out_filename,
    );

    const image = b.addSystemCommand(&[_][]const u8{
        "tools/gen_image.py",
        bootloader_path,
        kernel_path,
        "image.bin",
    });
    image.step.dependOn(&bootloader.step);
    image.step.dependOn(&kernel.step);

    const gen_image = b.step("gen", "Generate image");
    gen_image.dependOn(&image.step);
    return gen_image;
}

const qemu_serial_conf = [_][]const u8{
    "-chardev", "stdio,id=com1",
    "-chardev", "pty,id=com2",
    "-chardev", "vc,id=com3",
    "-chardev", "vc,id=com4",
    "-serial", "chardev:com1",
    "-serial", "chardev:com2",
    "-serial", "chardev:com3",
    "-serial", "chardev:com4",
};
