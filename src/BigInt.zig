const BigInt = @This();
const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const io = std.io;
const debug = std.debug;

const BigIntErr = error{
    IntegerOverflow,
    IntegerUnderflow,
};

const segment_size = @bitSizeOf(usize);

storage: []u8,
allocator: ArenaAllocator,

const BigIntConfig = struct {
    preheat: usize = 64,
    allocator: Allocator,
    content_preheat: ?[]u8 = null,
};

pub fn init(allocator: Allocator) !*BigInt {
    return BigInt.initWithArgs(.{ .allocator = allocator });
}

pub fn deinit(self: *BigInt) void {
    self.allocator.deinit();
}

pub fn initWithArgs(config: BigIntConfig) !*BigInt {
    const preheat: usize = blk: {
        if (config.content_preheat) |content| {
            break :blk content.len;
        } else {
            break :blk config.preheat;
        }
    };
    debug.assert(std.math.log2_int(usize, preheat) % segment_size);
    var allocator = ArenaAllocator.init(config.allocator);
    var self = try allocator.allocator().create(BigInt);
    self.allocator = allocator;
    if (config.content_preheat) |content| {
        self.storage = try self.allocator.allocator().dupe(u8, content);
    } else {
        self.storage = try self.allocator.allocator().alloc(u8, config.preheat);
        @memset(self.storage, 0);
    }
    return self;
}

/// dest = a + b
/// dest may be reference to a or b
pub fn add(dest: *BigInt, a: BigInt, b: BigInt) !void {
    const min_mem_size = @max(a.storage.len, b.storage.len) + segment_size;
    if (dest.storage.len < min_mem_size) {
        const old = dest.storage.len;
        if (!dest.allocator.allocator().resize(dest.storage, min_mem_size)) {
            dest.storage = try dest.allocator.allocator().realloc(dest.storage, min_mem_size);
            @memset(dest.storage[old..dest.storage.len], 0);
        }
    }
    var carry: u16 = 0;
    if (a.storage.len >= b.storage.len) {
        for (0..b.storage.len) |i| {
            carry = carry + a.storage[i] + b.storage[i];
            dest.storage[i] = @truncate(carry & 0xff);
            carry &= 0xff00;
            carry >>= 8;
        }
        for (b.storage.len..a.storage.len) |i| {
            carry = carry + a.storage[i];
            dest.storage[i] = @truncate(carry & 0xff);
            carry &= 0xff00;
            carry >>= 8;
        }
        dest.storage[a.storage.len] = @truncate(carry & 0xff);
    } else {
        for (0..a.storage.len) |i| {
            carry = carry + a.storage[i] + b.storage[i];
            dest.storage[i] = @truncate(carry & 0xff);
            carry &= 0xff00;
            carry >>= 8;
        }
        for (a.storage.len..b.storage.len) |i| {
            carry = carry + b.storage[i];
            dest.storage[i] = @truncate(carry & 0xff);
            carry &= 0xff00;
            carry >>= 4;
        }
        dest.storage[b.storage.len] = @truncate(carry & 0xff);
    }
}

/// dest = a - b
/// dest may be reference to a or b
pub fn sub(dest: *BigInt, a: BigInt, b: BigInt) !void {
    if (b.storage.len > a.storage.len) {
        var carry: u16 = 0;
        for (0..a.storage.len) |i| {
            carry = a.storage[i] - carry - b.storage[i];
            dest.storage[i] = @truncate(carry & 0xff);
            carry &= 0xff00;
            carry >>= 8;
        }
        for (a.storage.len..b.storage.len) |i| {
            if (b.storage[i] != 0) {
                return BigIntErr.IntegerOverflow;
            }
        }
    } else {
        if (dest.storage.len < a.storage.len) {
            const old = dest.storage.len;
            if (!dest.allocator.allocator().resize(dest.storage, a.storage.len))
                dest.storage = try dest.allocator.allocator().realloc(dest.storage, a.storage.len);
            @memset(dest.storage[old..dest.storage.len], 0);
        }
        var carry: u8 = 0;
        for (0..b.storage.len) |i| {
            carry = a.storage[i] - carry - b.storage[i];
            dest.storage[i] = @truncate(carry & 0xff);
            carry &= 0xff00;
            carry >>= 8;
        }
    }
}

/// dest = a ^ b
/// dest may be reference to a or b
pub fn xor(dest: *BigInt, a: BigInt, b: BigInt) void {
    if (dest.storage.len < @max(a.storage.len, b.storage.len)) {
        if (!dest.allocator.allocator().resize(dest.storage, @max(a.storage.len, b.storage.len)))
            dest.storage = try dest.allocator.allocator().realloc(dest.storage, @max(a.storage.len, b.storage.len));
    }
    if (a.storage.len >= b.storage.len) {
        for (0..b.storage.len) |i| {
            dest.storage[i] = a.storage[i] ^ b.storage[i];
        }
        for (b.storage.len..a.storage.len) |i| {
            dest.storage[i] = a.storage[i];
        }
    } else {
        for (0..a.storage.len) |i| {
            dest.storage[i] = a.storage[i] ^ b.storage[i];
        }
        for (a.storage.len..b.storage.len) |i| {
            dest.storage[i] = b.storage[i];
        }
    }
}

/// dest = a & b
/// dest may be reference to a or b
pub fn @"and"(dest: *BigInt, a: BigInt, b: BigInt) void {
    if (dest.storage.len < @max(a.storage.len, b.storage.len)) {
        if (!dest.allocator.allocator().resize(dest.storage, @max(a.storage.len, b.storage.len)))
            dest.storage = try dest.allocator.allocator().realloc(dest.storage, @max(a.storage.len, b.storage.len));
    }
    if (a.storage.len >= b.storage.len) {
        for (0..b.storage.len) |i| {
            dest.storage[i] = a.storage[i] & b.storage[i];
        }
        for (b.storage.len..a.storage.len) |i| {
            dest.storage[i] = a.storage[i];
        }
        return;
    } else {
        for (0..a.storage.len) |i| {
            dest.storage[i] = a.storage[i] & b.storage[i];
        }
        for (a.storage.len..b.storage.len) |i| {
            dest.storage[i] = b.storage[i];
        }
    }
}

/// dest = a >> b
/// dest may be referened as a, not b
pub fn shr(dest: *BigInt, a: BigInt, b: BigInt) !void {
    if (b.storage.len > 64) @panic("Integer overflow in bit shift");
    const byte_shift = @as(u64, @ptrCast(b.storage[0..64]));
    if (a.storage.len < byte_shift) {
        if (!dest.allocator.allocator().resize(dest.storage, 1))
            dest.storage = try dest.allocator.allocator().realloc(dest.storage, 1);
        dest.storage[0] = 0;
        return;
    } else {
        if (dest.storage.len < a.storage.len - byte_shift) {
            if (!dest.allocator.allocator().resize(dest.storage, @max(a.storage.len, b.storage.len)))
                dest.storage = try dest.allocator.allocator().realloc(dest.storage, @max(a.storage.len, b.storage.len));
        }
        for (0..a.storage.len - byte_shift) |i| {
            dest.storage[i] = a.storage[byte_shift + i];
        }
    }
}

/// dest = a * b
/// dest may be referenced as a or b
pub fn mul(dest: *BigInt, a: BigInt, b: BigInt) !void {
    // TODO: kompletter mist
    if (dest.storage.len < @max(a.storage.len, b.storage.len) * 2) {
        if (!dest.allocator.allocator().resize(dest.storage, @max(a.storage.len, b.storage.len) * 2)) {
            dest.storage = dest.allocator.allocator().realloc(dest.storage, @max(a.storage.len, b.storage.len) * 2);
        }
    }
    var carry: u16 = 0;
    if (a.storage.len >= b.storage.len) {
        for (0..b.storage.len) |i| {
            carry = carry + a.storage[i] * b.storage[i];
            dest.storage[i] = @truncate(carry & 0xff);
            carry = (carry & 0xff00) >> 8;
        }
        for (b.storage.len..a.storage.len) |i| {
            carry = carry + a.storage[i];
            dest.storage[i] = @truncate(carry & 0xff);
            carry = (carry & 0xff00) >> 8;
        }
        dest.storage[a.storage.len + 1] = carry;
    } else {
        for (0..a.storage.len) |i| {
            carry = carry + a.storage[i] * b.storage[i];
            dest.storage[i] = @truncate(carry & 0xff);
            carry = (carry & 0xff00) >> 8;
        }
        for (a.storage.len..b.storage.len) |i| {
            carry = carry + a.storage[i];
            dest.storage[i] = @truncate(carry & 0xff);
            carry = (carry & 0xff00) >> 8;
        }
        dest.storage[b.storage.len + 1] = carry;
    }
}

pub fn isZero(self: BigInt) bool {
    for (self.storage) |b| {
        if (b > 0) return true;
    }
    return false;
}

pub fn eql(a: BigInt, b: BigInt) bool {
    // start with last bit, as it is little endian
    _ = a;
    _ = b;
}

pub fn printHex(self: BigInt) !void {
    const stdout = io.getStdOut().writer();
    var buf_stdout = io.bufferedWriter(stdout);
    for (self.storage) |byte| {
        _ = try buf_stdout.writer().print("{X}", .{byte});
    }
    _ = try buf_stdout.write("\n");
    try buf_stdout.flush();
}
pub fn trim(self: *BigInt) !void {
    var free: usize = 0;
    for (1..self.storage.len + 1) |i| {
        if (self.storage[self.storage.len - i] == 0) {
            free += 1;
        } else {
            break;
        }
    }
    std.debug.print("free: {d}, len: {d}, ln: {d}\n", .{ free, self.storage.len, self.storage.len - free });
    if (free > 0 and !self.allocator.allocator().resize(self.storage, self.storage.len - free)) {
        self.storage = try self.allocator.allocator().realloc(self.storage, self.storage.len - free);
    } else {
        self.storage.len = self.storage.len - free;
    }
}
pub fn sqrt(dest: *BigInt, x: BigInt) !void {
    if (dest.storage.len < x and !dest.allocator.allocator().resize(dest.storage, x.storage.len)) {
        dest.storage = dest.allocator.allocator().realloc(dest.storage, x.storage.len);
    }
    var a: u64 = 0;
    var s: u64 = 0;
    var i = try BigInt.init(dest.allocator.allocator());
    var buffer = try BigInt.init(dest.allocator.allocator());
    while (true) {
        try BigInt.shr(buffer, x, i.*);
        if (buffer.isZero()) {
            break;
        } else {
            // leaks mem, fix by either explicly allow usize large shifts or dedicated variable for b
            try i.add(i, try BigInt.initWithArgs(.{ .allocator = dest.allocator.allocator(), .content_preheat = &[_]u8{2} }));
        }
    }
    _ = &a;
    _ = &s;
}

pub fn copy(x: BigInt, allocator: Allocator) !*BigInt {
    return BigInt.initWithArgs(.{ .allocator = allocator, .content_preheat = x.storage });
}

pub fn addAbs(dest: *BigInt, a: BigInt, T: type, b: T) !void {
    if (dest.storage.len > a.storage.len) {
        if (!dest.allocator.allocator().resize(dest.storage, a.storage.len)) {
            const old = dest.storage.len;
            dest.storage = dest.allocator.allocator().realloc(dest.storage, a.storage.len);
            @memset(dest.storage[old..dest.storage.len], 0);
        }
    }
    if (a.storage.len >= @bitSizeOf(T) / 8) {
        var carry: u16 = 0;
        for (0..math.log2_int(comptime_int, @bitSizeOf(T))) |i| {
            carry = carry + a.storage[i] + @as(u8, @truncate((b >> i) & 0xff));
            dest.storage[i] = @truncate(carry & 0xff);
            carry = (carry >> 8) & 0xff;
        }
        for (math.log2_int(comptime_int, @bitSizeOf(T))..a.storage.len) |i| {
            carry = carry + a.storage[i];
            dest.storage[i] = @truncate(carry & 0xff);
            carry = (carry >> 8) & 0xff;
        }
        if (carry > 0 and dest.storage.len >= a.storage.len + 1) {
            dest.storage.len[a.storage.len + 1] = carry;
        } else {
            if (!dest.allocator.allocator().resize(dest.storage, a.storage.len)) {
                const old = dest.storage.len;
                dest.storage = dest.allocator.allocator().realloc(dest.storage, a.storage.len);
                @memset(dest.storage[old..dest.storage.len], 0);
            }
        }
    } else {
        for (0..a.storage.len) |i| {
            dest.storage[i] = @truncate((b >> i) & 0xff);
        }
    }
}

const testing = std.testing;

test "base" {
    const allocator = std.testing.allocator;
    var int = try BigInt.init(allocator);
    defer int.deinit();
}

test "base with args" {
    const allocator = std.testing.allocator;
    var int = try BigInt.initWithArgs(.{ .allocator = allocator, .preheat = 32 });
    defer int.deinit();
}

test "preheat content" {
    const allocator = std.testing.allocator;
    var content = [_]u8{ 0xff, 0xfe, 0xee };
    var int = try BigInt.initWithArgs(.{ .allocator = allocator, .preheat = 32, .content_preheat = &content });
    defer int.deinit();
}

test "add" {
    const allocator = std.testing.allocator;
    var a = [_]u8{ 0xff, 0xfe };
    var b = [_]u8{ 0xfe, 0xea };
    var d = try BigInt.initWithArgs(.{ .allocator = allocator, .preheat = 8 });
    const x = try BigInt.initWithArgs(.{ .allocator = allocator, .content_preheat = &a });
    const y = try BigInt.initWithArgs(.{ .allocator = allocator, .content_preheat = &b });
    defer {
        d.deinit();
        x.deinit();
        y.deinit();
    }
    try d.add(x.*, y.*);
    try d.trim();
    try d.printHex();

    const sol = [_]u8{ 0xfd, 0xe9, 0x01 };
    for (0..d.storage.len) |i| {
        std.debug.print("d[{d}] {X:0}\n", .{ i, d.storage[i] });
    }
    try testing.expect(blk: {
        for (0..sol.len) |i| {
            std.debug.print("i: {d}, d: {X}, s: {X}\n", .{ i, d.storage[i], sol[i] });
            if (d.storage[i] != sol[i]) {
                break :blk false;
            }
        }
        break :blk true;
    });
}
