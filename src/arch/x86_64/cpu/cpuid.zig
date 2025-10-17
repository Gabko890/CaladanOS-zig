const std = @import("std");
const ascii = std.ascii;

pub const CpuidResult = struct {
    eax: u32,
    ebx: u32,
    ecx: u32,
    edx: u32,
};

fn cpuid_raw(leaf: u32, subleaf: u32) CpuidResult {
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;

    asm volatile ("cpuid"
        : [a] "={eax}" (eax),
          [b] "={ebx}" (ebx),
          [c] "={ecx}" (ecx),
          [d] "={edx}" (edx),
        : [leaf] "{eax}" (leaf),
          [subleaf] "{ecx}" (subleaf),
        : .{ .memory = true });

    return CpuidResult{
        .eax = eax,
        .ebx = ebx,
        .ecx = ecx,
        .edx = edx,
    };
}

fn maxBasicLeaf() u32 {
    return cpuid_raw(0x00, 0).eax;
}

fn maxExtendedLeaf() u32 {
    return cpuid_raw(0x8000_0000, 0).eax;
}

fn normalizeCpuidString(buffer: []u8, original_len: usize) []const u8 {
    var write_idx: usize = 0;
    var idx: usize = 0;

    while (idx < original_len and idx < buffer.len) : (idx += 1) {
        const byte = buffer[idx];
        if (byte == 0) break;

        const replacement = switch (byte) {
            0xAE => "(R)", // ®
            0x99 => "(TM)", // ™
            0xA9 => "(C)", // ©
            else => null,
        };

        if (replacement) |seq| {
            if (write_idx + seq.len > buffer.len) break;
            var j: usize = 0;
            while (j < seq.len) : (j += 1) {
                buffer[write_idx + j] = seq[j];
            }
            write_idx += seq.len;
            continue;
        }

        if (!ascii.isPrint(byte)) continue;

        buffer[write_idx] = byte;
        write_idx += 1;
    }

    return buffer[0..write_idx];
}

fn ensureNonEmpty(buffer: []u8, slice: []const u8) []const u8 {
    if (slice.len != 0) return slice;
    const fallback = "unknown";
    const count = @min(fallback.len, buffer.len);
    var j: usize = 0;
    while (j < count) : (j += 1) buffer[j] = fallback[j];
    return buffer[0..count];
}

fn topologyLogicalCount(leaf: u32) ?u32 {
    var level: u32 = 0;
    var best_overall: u32 = 0;
    var core_level: ?u32 = null;

    while (true) : (level += 1) {
        const res = cpuid_raw(leaf, level);
        const level_type: u32 = (res.ecx >> 8) & 0xFF;
        const logical_at_level: u32 = res.ebx & 0xFFFF;

        if (level_type == 0 or logical_at_level == 0) break;

        if (level_type == 2) core_level = logical_at_level;
        if (logical_at_level > best_overall) best_overall = logical_at_level;
    }

    if (core_level) |v| return v;
    return if (best_overall != 0) best_overall else null;
}

pub fn logicalProcessorCount() u32 {
    const max_basic = maxBasicLeaf();

    if (max_basic >= 0x1F) {
        if (topologyLogicalCount(0x1F)) |count| return count;
    }

    if (max_basic >= 0x0B) {
        if (topologyLogicalCount(0x0B)) |count| return count;
    }

    if (max_basic >= 0x04) {
        const topo = cpuid_raw(0x04, 0);
        const cores_minus_one = (topo.eax >> 26) & 0x3F;
        const cores = cores_minus_one + 1;
        if (cores != 0) {
            const base = cpuid_raw(0x01, 0);
            const logical_total = (base.ebx >> 16) & 0xFF;
            if (logical_total != 0) {
                return if (logical_total >= cores) logical_total else cores;
            }
            return cores;
        }
    }

    const legacy = (cpuid_raw(0x01, 0).ebx >> 16) & 0xFF;
    if (legacy != 0) return legacy;

    return 1;
}

pub fn writeVendorString(buffer: []u8) []const u8 {
    if (buffer.len < 12) return buffer[0..0];
    const res = cpuid_raw(0x00, 0);
    const ebx_bytes: [4]u8 = @bitCast(res.ebx);
    const edx_bytes: [4]u8 = @bitCast(res.edx);
    const ecx_bytes: [4]u8 = @bitCast(res.ecx);
    inline for (ebx_bytes, 0..) |b, i| buffer[i] = b;
    inline for (edx_bytes, 0..) |b, i| buffer[i + 4] = b;
    inline for (ecx_bytes, 0..) |b, i| buffer[i + 8] = b;

    const normalized = normalizeCpuidString(buffer, 12);
    return ensureNonEmpty(buffer, normalized);
}

pub fn writeBrandString(buffer: []u8) []const u8 {
    const max_ext = maxExtendedLeaf();
    if (max_ext < 0x8000_0004) return writeVendorString(buffer);
    if (buffer.len < 48) return ensureNonEmpty(buffer, buffer[0..0]);

    var offset: usize = 0;
    inline for (&.{ 0x8000_0002, 0x8000_0003, 0x8000_0004 }) |leaf| {
        const res = cpuid_raw(leaf, 0);
        const words = [_]u32{ res.eax, res.ebx, res.ecx, res.edx };
        inline for (words) |word| {
            const bytes: [4]u8 = @bitCast(word);
            inline for (bytes, 0..) |b, i| buffer[offset + i] = b;
            offset += 4;
        }
    }

    var end = offset;
    while (end > 0) {
        const byte = buffer[end - 1];
        if (byte == 0 or byte == ' ') {
            end -= 1;
            continue;
        }
        break;
    }

    if (end == 0) return ensureNonEmpty(buffer, buffer[0..0]);
    const normalized = normalizeCpuidString(buffer, end);
    return ensureNonEmpty(buffer, normalized);
}
