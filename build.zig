const std = @import("std");

const Config = struct {
    architecture: []const u8,
    enable_serial: bool,
};

const default_config = Config{ .architecture = "x86_64", .enable_serial = false };

pub fn build(b: *std.Build) void {
    // Prefer safer runtime checks by default
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseSafe });
    const config = loadConfig(b);
    const target = b.resolveTargetQuery(targetFromArchitecture(config.architecture));

    const build_options_step = b.addOptions();
    build_options_step.addOption([]const u8, "architecture", config.architecture);
    build_options_step.addOption(bool, "enable_serial", config.enable_serial);
    const build_options_mod = build_options_step.createModule();

    // Kernel modules
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/kernel/main.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .kernel,
    });
    root_module.addImport("build_options", build_options_mod);

    const console_module = b.createModule(.{
        .root_source_file = b.path("src/drivers/video/console.zig"),
        .target = target,
        .optimize = optimize,
    });
    console_module.addImport("build_options", build_options_mod);

    const portio_module = b.createModule(.{
        .root_source_file = b.path("src/arch/x86_64/cpu/io.zig"),
        .target = target,
        .optimize = optimize,
    });

    var serial_module: ?*std.Build.Module = null;
    if (config.enable_serial) {
        const module = b.createModule(.{
            .root_source_file = b.path("src/drivers/debug/serial.zig"),
            .target = target,
            .optimize = optimize,
        });
        module.addImport("portio", portio_module);
        serial_module = module;
    }

    const multiboot_module = b.createModule(.{
        .root_source_file = b.path("src/arch/x86_64/boot/multiboot2.zig"),
        .target = target,
        .optimize = optimize,
    });
    multiboot_module.addImport("build_options", build_options_mod);
    // Allow mb2 helpers to print via the console.
    multiboot_module.addImport("console", console_module);

    const cpuid_module = b.createModule(.{
        .root_source_file = b.path("src/arch/x86_64/cpu/cpuid.zig"),
        .target = target,
        .optimize = optimize,
    });
    cpuid_module.addImport("build_options", build_options_mod);

    const mm_module = b.createModule(.{
        .root_source_file = b.path("src/mm.zig"),
        .target = target,
        .optimize = optimize,
    });
    // mm depends on multiboot helpers for parsing memory map
    mm_module.addImport("arch_boot", multiboot_module);

    root_module.addImport("console", console_module);
    root_module.addImport("arch_boot", multiboot_module);
    root_module.addImport("arch_cpu", cpuid_module);
    root_module.addImport("mm", mm_module);
    if (serial_module) |m| {
        root_module.addImport("serial", m);
        console_module.addImport("serial", m);
    }

    // Kernel build
    const kernel = b.addExecutable(.{
        .name = "kernel.elf",
        .root_module = root_module,
    });
    // Add 32-bit bootstrap/long-mode trampoline and register capture helper
    kernel.addAssemblyFile(b.path("src/arch/x86_64/boot/boot.S"));
    kernel.addAssemblyFile(b.path("src/arch/x86_64/cpu/regs.S"));
    // Default IDT handler stubs (64-bit)
    kernel.addAssemblyFile(b.path("src/arch/x86_64/cpu/idt_stubs.S"));
    kernel.setLinkerScript(b.path("src/arch/x86_64/linker/kernel.ld"));
    const install_kernel = b.addInstallArtifact(kernel, .{});

    // UEFI ISO build (GRUB x86_64-efi)
    const iso_step = b.step("iso", "Build UEFI GRUB ISO");

    const iso_dir = "zig-out/iso";
    const kernel_path = b.getInstallPath(.bin, "kernel.elf");
    const iso_out = b.getInstallPath(.bin, "kernel.iso");
    const grub_cfg = b.path("boot/grub/grub.cfg");

    const make_dirs = b.addSystemCommand(&[_][]const u8{
        "mkdir",                 "-p",
        iso_dir ++ "/boot/grub", iso_dir ++ "/EFI/BOOT",
    });
    make_dirs.step.dependOn(&install_kernel.step);

    const copy_kernel = b.addSystemCommand(&[_][]const u8{
        "cp", kernel_path, iso_dir ++ "/boot/kernel.elf",
    });
    copy_kernel.step.dependOn(&make_dirs.step);

    const copy_font = b.addSystemCommand(&[_][]const u8{
        "bash",                                                                                 "-c",
        "cp /usr/share/grub/unicode.pf2 zig-out/iso/boot/grub/unicode.pf2 2>/dev/null || true",
    });
    copy_font.step.dependOn(&copy_kernel.step);

    const copy_cfg = b.addSystemCommand(&[_][]const u8{
        "cp", grub_cfg.getPath(b), iso_dir ++ "/boot/grub/grub.cfg",
    });
    copy_cfg.step.dependOn(&copy_font.step);

    const mkimage = b.addSystemCommand(&[_][]const u8{
        "grub-mkimage",
        "-O",
        "x86_64-efi",
        "-o",
        iso_dir ++ "/EFI/BOOT/BOOTX64.EFI",
        "-p",
        "/boot/grub",
        "iso9660",
        "part_gpt",
        "part_msdos",
        "efi_gop",
        "efi_uga",
        "multiboot2",
        "normal",
    });
    mkimage.step.dependOn(&copy_cfg.step);

    // Build FAT ESP image with BOOTX64.EFI
    const mkesp = b.addSystemCommand(&[_][]const u8{
        "bash", "-lc",
        "set -e; truncate -s 4M 'zig-out/iso/EFI/efiboot.img'; " ++
            "(command -v mkfs.vfat >/dev/null && mkfs.vfat -F 16 -n CALADAN-ESP 'zig-out/iso/EFI/efiboot.img' || mformat -i 'zig-out/iso/EFI/efiboot.img' -v CALADAN-ESP ::); " ++
            "mmd -i 'zig-out/iso/EFI/efiboot.img' ::/EFI ::/EFI/BOOT; " ++
            "mcopy -i 'zig-out/iso/EFI/efiboot.img' 'zig-out/iso/EFI/BOOT/BOOTX64.EFI' ::/EFI/BOOT/BOOTX64.EFI;"
    });
    mkesp.step.dependOn(&mkimage.step);

    // Create UEFI ISO (El Torito: efiboot.img)
    const mkiso = b.addSystemCommand(&[_][]const u8{
        "xorriso", "-as", "mkisofs",
        "-R", "-J",
        "-V", "CALADANOS",
        "-eltorito-alt-boot",
        "-e", "EFI/efiboot.img",
        "-no-emul-boot",
        "-o", iso_out,
        iso_dir,
    });
    mkiso.step.dependOn(&mkesp.step);

    iso_step.dependOn(&mkiso.step);

    const kernel_step = b.step("kernel", "Build kernel ELF");
    kernel_step.dependOn(&install_kernel.step);

    iso_step.dependOn(kernel_step);

    // ------------------------------------------------------------------------
    // Config
    // ------------------------------------------------------------------------
    const config_step = b.step("config", "Configure build options");
    const config_cmd = b.addSystemCommand(&[_][]const u8{
        "bash", "-lc", "tools/configure.sh",
    });
    config_step.dependOn(&config_cmd.step);
}

// ------------------------------------------------------------------------
// Helpers
// ------------------------------------------------------------------------
fn targetFromArchitecture(arch: []const u8) std.Target.Query {
    // Kernel is x86_64-only; accept legacy values by mapping to x86_64
    if (std.mem.eql(u8, arch, "x86_64") or std.mem.eql(u8, arch, "x86")) {
        return .{
            .cpu_arch = .x86_64,
            .os_tag = .freestanding,
            .abi = .none,
        };
    }
    std.debug.print("Unknown architecture '{s}', defaulting to x86_64.\n", .{arch});
    return .{ .cpu_arch = .x86_64, .os_tag = .freestanding, .abi = .none };
}

fn loadConfig(b: *std.Build) Config {
    const path = b.path("build/config.json");
    var file = std.fs.cwd().openFile(path.getPath(b), .{}) catch return default_config;
    defer file.close();

    const contents = file.readToEndAlloc(b.allocator, 4096) catch return default_config;
    defer b.allocator.free(contents);

    const JsonConfig = struct {
        architecture: []const u8 = default_config.architecture,
        debug: struct { serial: bool = default_config.enable_serial } = .{},
    };

    var arena = std.heap.ArenaAllocator.init(b.allocator);
    defer arena.deinit();

    const parsed = std.json.parseFromSliceLeaky(JsonConfig, arena.allocator(), contents, .{
        .ignore_unknown_fields = true,
    }) catch return default_config;

    const arch_dup = b.allocator.dupe(u8, parsed.architecture) catch return default_config;
    return .{ .architecture = arch_dup, .enable_serial = parsed.debug.serial };
}
