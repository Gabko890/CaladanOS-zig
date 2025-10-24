const std = @import("std");
const console = @import("console");

pub const bootloader_magic: u32 = 0x36d76289;

pub const FramebufferType = enum(u8) {
    indexed = 0,
    rgb = 1,
    text = 2,
};

pub const FramebufferInfo = struct {
    address: ?[*]volatile u8 = null,
    pitch: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    bpp: u8 = 0,
    kind: FramebufferType = .text,
    text_buffer: ?[*]volatile u16 = null,
};

pub const MemoryType = enum(u32) {
    available = 1,
    reserved = 2,
    acpi_reclaimable = 3,
    acpi_nvs = 4,
    bad_memory = 5,
    undefined,
};

pub const MemoryMapEntry = extern struct {
    addr: u64,
    len: u64,
    type: u32,
    reserved: u32,
};

pub const MemoryMap = struct {
    entries: [*]const MemoryMapEntry,
    count: usize,
};

// A convenient, self-contained view of the bootloader's memory map.
// Provides a constructor from the Multiboot2 info block and a printer
pub const BootloaderMemoryMap = struct {
    entries: []const MemoryMapEntry,
    total_usable: u64,

    pub fn init(info_addr: usize) ?BootloaderMemoryMap {
        const map = memory_map(info_addr) orelse return null;

        var total: u64 = 0;
        var i: usize = 0;
        while (i < map.count) : (i += 1) {
            const entry = map.entries[i];
            if (entry.type == @intFromEnum(MemoryType.available))
                total += entry.len;
        }

        return BootloaderMemoryMap{
            .entries = map.entries[0..map.count],
            .total_usable = total,
        };
    }

    pub fn print(self: BootloaderMemoryMap) void {
        console.puts("Memory map (bootloader):\n");
        var idx: usize = 0;
        while (idx < self.entries.len) : (idx += 1) {
            const entry = self.entries[idx];
            const type_str = memory_type_name(entry.type);
            console.printf(
                "  region {d}: base=0x{X:0>16}, len=0x{X:0>16} ({s})\n",
                .{ idx, entry.addr, entry.len, type_str },
            );
        }
        console.printf(
            "Total usable memory: {d} MiB\n",
            .{self.total_usable / (1024 * 1024)},
        );
    }
};

const InfoHeader = extern struct {
    total_size: u32,
    reserved: u32,
};

const TagHeader = extern struct {
    type: u32,
    size: u32,
};

const FramebufferTag = extern struct {
    header: TagHeader,
    framebuffer_addr: u64,
    framebuffer_pitch: u32,
    framebuffer_width: u32,
    framebuffer_height: u32,
    framebuffer_bpp: u8,
    framebuffer_type: u8,
    reserved: u16,
};

const MemoryMapTag = extern struct {
    header: TagHeader,
    entry_size: u32,
    entry_version: u32,
};

fn align_to_8(value: usize) usize {
    return (value + 7) & ~@as(usize, 7);
}

pub fn locate_framebuffer(info_addr: usize) ?FramebufferInfo {
    const header_ptr = @as(*const InfoHeader, @ptrFromInt(info_addr));
    var cursor = info_addr + @sizeOf(InfoHeader);
    const end = info_addr + header_ptr.total_size;

    while (cursor < end) {
        const tag = @as(*const TagHeader, @ptrFromInt(cursor));
        if (tag.type == 0 or tag.size == 0) break;

        if (tag.type == 8) {
            const aligned = @as(*align(@alignOf(FramebufferTag)) const TagHeader, @alignCast(tag));
            const fb_tag = @as(*const FramebufferTag, @ptrCast(aligned));
            const fb_type: FramebufferType = @enumFromInt(fb_tag.framebuffer_type);
            var info = FramebufferInfo{
                .pitch = fb_tag.framebuffer_pitch,
                .width = fb_tag.framebuffer_width,
                .height = fb_tag.framebuffer_height,
                .bpp = fb_tag.framebuffer_bpp,
                .kind = fb_type,
            };

            const addr = std.math.cast(usize, fb_tag.framebuffer_addr) orelse return null;
            switch (fb_type) {
                .text => {
                    info.text_buffer = @as([*]volatile u16, @ptrFromInt(addr));
                },
                else => {
                    info.address = @as([*]volatile u8, @ptrFromInt(addr));
                },
            }
            return info;
        }

        cursor = align_to_8(cursor + tag.size);
    }

    return null;
}

pub fn memory_map(info_addr: usize) ?MemoryMap {
    const header_ptr = @as(*const InfoHeader, @ptrFromInt(info_addr));
    var cursor = info_addr + @sizeOf(InfoHeader);
    const end = info_addr + header_ptr.total_size;

    while (cursor < end) {
        const tag = @as(*const TagHeader, @ptrFromInt(cursor));
        if (tag.type == 0 or tag.size == 0) break;

        if (tag.type == 6) {
            const aligned = @as(*align(@alignOf(MemoryMapTag)) const TagHeader, @alignCast(tag));
            const mmap_tag = @as(*const MemoryMapTag, @ptrCast(aligned));
            const entries_addr = @intFromPtr(mmap_tag) + @sizeOf(MemoryMapTag);
            const entries_ptr = @as([*]const MemoryMapEntry, @ptrFromInt(entries_addr));
            const entry_count = (mmap_tag.header.size - @sizeOf(MemoryMapTag)) / mmap_tag.entry_size;
            return MemoryMap{
                .entries = entries_ptr,
                .count = entry_count,
            };
        }

        cursor = align_to_8(cursor + tag.size);
    }

    return null;
}

pub fn memory_type_name(value: u32) []const u8 {
    return switch (value) {
        @intFromEnum(MemoryType.available) => "usable",
        @intFromEnum(MemoryType.reserved) => "reserved",
        @intFromEnum(MemoryType.acpi_reclaimable) => "ACPI reclaim",
        @intFromEnum(MemoryType.acpi_nvs) => "ACPI NVS",
        @intFromEnum(MemoryType.bad_memory) => "bad memory",
        else => "unknown",
    };
}
