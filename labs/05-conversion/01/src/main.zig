const std = @import("std");

const max_output_size: usize = 1024 * 1024;

const Output = struct {
    bytes: []u8,
    used: usize,
};

const Decoder = struct {
    output: []u8,
    used: usize = 0,
    base: u32 = 0,
    finished: bool = false,
    has_data: bool = false,

    fn record(self: *Decoder, line: []const u8) !void {
        if (self.finished) return error.DataAfterEOF;
        if (line.len < 11 or line[0] != ':') return error.InvalidRecord;

        const count = try hexByte(line, 1);
        const n: usize = count;
        if (line.len != 11 + n * 2) return error.InvalidRecordLength;

        var checksum: u8 = 0;
        var i: usize = 0;
        while (i < n + 5) : (i += 1) {
            checksum +%= try hexByte(line, 1 + 2 * i);
        }
        if (checksum != 0) return error.InvalidChecksum;

        const address = @as(u16, try hexByte(line, 3)) * 256 +
            @as(u16, try hexByte(line, 5));
        const record_type = try hexByte(line, 7);

        switch (record_type) {
            0x00 => {
                const absolute = @as(u64, self.base) + @as(u64, address);
                if (absolute > @as(u64, @intCast(self.output.len))) return error.AddressTooLarge;
                const offset: usize = @intCast(absolute);
                if (n > self.output.len - offset) return error.AddressTooLarge;

                for (0..n) |index| {
                    self.output[offset + index] = try hexByte(line, 9 + index * 2);
                }
                if (n > 0) {
                    self.has_data = true;
                    self.used = @max(self.used, offset + n);
                }
            },
            0x01 => {
                if (n != 0 or address != 0) return error.InvalidEOFRecord;
                self.finished = true;
            },
            0x02 => {
                if (n != 2 or address != 0) return error.InvalidAddressRecord;
                const segment = @as(u32, try hexByte(line, 9)) * 256 +
                    @as(u32, try hexByte(line, 11));
                self.base = segment * 16;
            },
            0x04 => {
                if (n != 2 or address != 0) return error.InvalidAddressRecord;
                const upper = @as(u32, try hexByte(line, 9)) * 256 +
                    @as(u32, try hexByte(line, 11));
                self.base = upper * 65536;
            },
            0x03, 0x05 => {
                if (n != 4 or address != 0) return error.InvalidStartAddressRecord;
            },
            else => return error.UnsupportedRecordType,
        }
    }
};

fn nibble(character: u8) !u8 {
    return switch (character) {
        '0'...'9' => character - '0',
        'A'...'F' => character - 'A' + 10,
        'a'...'f' => character - 'a' + 10,
        else => error.InvalidHexDigit,
    };
}

fn hexByte(line: []const u8, index: usize) !u8 {
    if (index >= line.len or line.len - index < 2) return error.InvalidRecordLength;
    return (try nibble(line[index])) * 16 + (try nibble(line[index + 1]));
}

fn whitespaceTrim(source: []const u8) []const u8 {
    var first: usize = 0;
    var last: usize = source.len;
    while (first < last and (source[first] == ' ' or source[first] == '\t' or source[first] == '\r')) : (first += 1) {}
    while (last > first and (source[last - 1] == ' ' or source[last - 1] == '\t' or source[last - 1] == '\r')) : (last -= 1) {}
    return source[first..last];
}

fn convert(allocator: std.mem.Allocator, source: []const u8) !Output {
    const output = try allocator.alloc(u8, max_output_size);
    errdefer allocator.free(output);
    @memset(output, 0xFF);

    var decoder = Decoder{ .output = output };
    var start: usize = 0;
    while (start < source.len) {
        var end = start;
        while (end < source.len and source[end] != '\n') : (end += 1) {}
        const line = whitespaceTrim(source[start..end]);
        if (line.len != 0) try decoder.record(line);
        start = if (end < source.len) end + 1 else source.len;
    }
    if (!decoder.finished) return error.MissingEOF;
    if (!decoder.has_data) return error.NoData;
    return .{ .bytes = output, .used = decoder.used };
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;
    const dir = std.Io.Dir.cwd();

    const source = try dir.readFileAlloc(io, "input.hex", allocator, .limited(1024 * 1024));
    defer allocator.free(source);

    const result = convert(allocator, source) catch |err| {
        std.debug.print("Conversion error: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(result.bytes);

    const file = try dir.createFile(io, "output.bin", .{});
    defer file.close(io);
    try file.writeStreamingAll(io, result.bytes[0..result.used]);
    std.debug.print("Converted {d} bytes into output.bin\n", .{result.used});
}

fn expectBytes(source: []const u8, expected: []const u8) !void {
    const result = try convert(std.testing.allocator, source);
    defer std.testing.allocator.free(result.bytes);
    try std.testing.expectEqualSlices(u8, expected, result.bytes[0..result.used]);
}

test "simple record" {
    try expectBytes(":0400000001020304F2\n:00000001FF\n", &.{ 1, 2, 3, 4 });
}

test "address gaps filled with FF" {
    try expectBytes(":0400000001020304F2\n:02000600AABB93\n:00000001FF\n", &.{ 1, 2, 3, 4, 255, 255, 170, 187 });
}

test "extended segment address" {
    const result = try convert(std.testing.allocator, ":020000020001FB\n:01000000AB54\n:00000001FF\n");
    defer std.testing.allocator.free(result.bytes);
    try std.testing.expectEqual(@as(usize, 17), result.used);
    try std.testing.expectEqual(@as(u8, 0xFF), result.bytes[0]);
    try std.testing.expectEqual(@as(u8, 0xAB), result.bytes[16]);
}

test "extended linear address" {
    const result = try convert(std.testing.allocator, ":020000040001F9\n:010000007F80\n:00000001FF\n");
    defer std.testing.allocator.free(result.bytes);
    try std.testing.expectEqual(@as(usize, 65537), result.used);
    try std.testing.expectEqual(@as(u8, 0x7F), result.bytes[65536]);
}

test "start address record is ignored" {
    try expectBytes(":0400000500000000F7\n:0400000001020304F2\n:00000001FF\n", &.{ 1, 2, 3, 4 });
}

test "checksum mismatch" {
    try std.testing.expectError(error.InvalidChecksum, convert(std.testing.allocator, ":0400000001020304F3\n:00000001FF\n"));
}

test "bad hex digit" {
    try std.testing.expectError(error.InvalidHexDigit, convert(std.testing.allocator, ":04000000010G0304F2\n:00000001FF\n"));
}

test "missing EOF" {
    try std.testing.expectError(error.MissingEOF, convert(std.testing.allocator, ":0400000001020304F2\n"));
}

test "address above limit" {
    try std.testing.expectError(error.AddressTooLarge, convert(std.testing.allocator, ":020000040010EA\n:010000007F80\n:00000001FF\n"));
}

test "unsupported record type" {
    try std.testing.expectError(error.UnsupportedRecordType, convert(std.testing.allocator, ":00000006FA\n:00000001FF\n"));
}

test "missing data" {
    try std.testing.expectError(error.NoData, convert(std.testing.allocator, ":00000001FF\n"));
}

test "record after EOF" {
    try std.testing.expectError(error.DataAfterEOF, convert(std.testing.allocator, ":00000001FF\n:0400000001020304F2\n"));
}

test "invalid record length" {
    try std.testing.expectError(error.InvalidRecordLength, convert(std.testing.allocator, ":0400000001020304\n:00000001FF\n"));
}
