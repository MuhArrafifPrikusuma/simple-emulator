const std = @import("std");
const Io = std.Io;

const RegID = enum {
    A, // 0
    DIN, // 1
    DOUT, // 2
    DSL, // 3
    IR, // 4
    MAR, // 5
    MBR, // 6
    PC, // 7
    SR, // 8
    Z, // 9
    // EFLAG will have each bits in it as a flag to each for a different things
    // 10 ^ 0 >> is for OF (overflow)
    // 10 ^ 1 >> is for CF (carry flag)
    // 10 ^ 2 >> is for NG (negative) <<= this mainly used for CMP with JNE
    // the rest i haven't think of yet
    EFLAG, // A NOTE: EFLAG is a flag register to determine 0 and negative for addition and comparison
};
const State = enum {
    FETCH,
    DECODE,
    EXECUTE,
};

var state: State = .FETCH;
var R = std.enums.EnumArray(RegID, u16).initUndefined();

var ram: [4096]u16 = undefined;
var clock_pulse: u8 = 1;
var current_ins: u8 = undefined;
var halted: bool = false;

const Instructions = *const fn (u8) void;
const instructions = blk: {
    var arr = [_]Instructions{nop} ** 16;

    arr[0] = hlt;
    arr[1] = jmp;
    arr[2] = lda;
    arr[3] = mov;
    arr[14] = add;
    arr[15] = nop;

    break :blk arr;
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len != 2) {
        std.log.err("No Executable to run\n", .{});
        return error.NoProgramFound;
    }

    for (args, 0..) |prog, i| {
        if (i == 1) try loadProgram(prog, io, allocator);
    }
    run(io);
}

var codes: []u16 = &[_]u16{};

fn loadProgram(program: []const u8, io: std.Io, allocator: std.mem.Allocator) !void {
    const file = try std.Io.Dir.cwd().readFileAlloc(io, program, allocator, .unlimited);
    defer {
        allocator.free(file);
    }

    var count_iter = std.mem.splitScalar(u8, file, '\n');
    var total_lines: usize = 0;
    while (count_iter.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) break;
        total_lines += 1;
    }

    if (total_lines == 0) return error.InvalidFile;
    var iter = std.mem.splitScalar(u8, file, '\n');

    codes = try allocator.alloc(u16, total_lines);
    var i: usize = 0;

    while (iter.next()) |line| : (i += 1) {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) break;
        codes[i] = try std.fmt.parseInt(u16, trimmed, 0);
    }
}

fn cycle() void {
    while (clock_pulse < 4) : (clock_pulse += 1) {
        processTick(clock_pulse);
    }
    clock_pulse = 1;
}

fn processTick(tick: u8) void {
    switch (state) {
        .FETCH => {
            // NOTE: later use 1 to determine what state it is
            R.set(.MBR, 0x00);
            R.set(.MBR, ram[R.get(.MAR)]);
            R.set(.IR, R.get(.MBR));
            state = .DECODE;
            R.getPtr(.PC).* += 1;
        },
        .DECODE => {
            if (R.get(.PC) == ~@as(u16, 0) - 1) R.getPtr(.PC).* = 0x00;
            current_ins = getInstruction();
        },
        .EXECUTE => {
            instructions[current_ins](tick);
        },
    }
}

fn getInstruction() u8 {
    state = .EXECUTE;
    return @as(u8, @intCast((R.get(.IR) & 0xF000) >> 12));
}

// Instructions

fn nop(tick: u8) void {
    _ = tick;
    R.set(.MAR, R.get(.PC));
    state = .FETCH;
}
// NOTE: if i add interupt make sure to modify this
fn hlt(tick: u8) void {
    _ = tick;
    halted = true;
    R.set(.MAR, R.get(.PC));
}

fn jmp(tick: u8) void {
    _ = tick;
    R.set(.PC, R.get(.MBR) & 0x0FFF);
    R.set(.MAR, R.get(.PC));
    state = .FETCH;
}

/// Value to register only with A << B
fn lda(tick: u8) void {
    _ = tick;
    const raw_idx: u4 = @truncate((R.get(.MBR) & 0x0F00) >> 8);
    const dest: RegID = @enumFromInt(raw_idx);

    R.set(dest, @as(u16, (R.get(.MBR) & 0x00FF)));
    R.set(.MAR, R.get(.PC));
    state = .FETCH;
}

/// register to register only and use the 12-4 bits for register id with A << B
fn mov(tick: u8) void {
    _ = tick;
    const low_raw_idx: u4 = @truncate((R.get(.MBR) & 0x00F0) >> 4);
    const high_raw_idx: u4 = @truncate((R.get(.MBR) & 0x0F00) >> 8);

    const src: RegID = @enumFromInt(low_raw_idx);
    const dest: RegID = @enumFromInt(high_raw_idx);

    R.set(dest, R.get(src));
    R.set(.MAR, R.get(.PC));
    state = .FETCH;
}

/// you need to add to a register with A << VAL because im to stupid to implement register
/// to register ADD
fn add(tick: u8) void {
    _ = tick;
    const src: u16 = (R.get(.MBR) & 0x00FF);
    const raw_idx: u4 = @truncate(((R.get(.MBR) & 0x0F00) >> 12));

    const dest: RegID = @enumFromInt(raw_idx);
    alu(src, dest);

    R.set(.MAR, R.get(.PC));
    state = .FETCH;
}

// emulate hardwares
// don't you dare to use any math operator here
fn alu(src: u16, dest: RegID) void {
    var b = src;
    while (b != 0) {
        const sum: u16 = R.get(dest) ^ b;
        const carry: u16 = (R.get(dest) & b) << 1;

        R.set(dest, sum);
        b = carry;
    }
    R.getPtr(.EFLAG).* ^= @as(u16, @intFromBool((R.get(dest) & 0xFF00) != 0));
}

fn dumpRegisters(stdout: *std.Io.Writer) void {
    stdout.print("PC: 0x{X:0>4}, IR: 0x{X:0>4}, MAR: 0x{X:0>4}, MBR: 0x{X:0>4}, A: 0x{X:0>4}, Z: 0x{X:0>4}, EFLAG: 0x{X:0>4}\n", .{
        R.get(.PC),
        R.get(.IR),
        R.get(.MAR),
        R.get(.MBR),
        R.get(.A),
        R.get(.Z),
        R.get(.EFLAG),
    }) catch |err| std.log.err("{any}\n", .{err});
}

fn run(io: std.Io) void {
    @memset(&ram, 0x00);
    @memmove(ram[0..codes.len], codes);
    var buf: [1024]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buf);
    const stdout = &writer.interface;

    while (true) {
        if (halted) continue;
        cycle();
        dumpRegisters(stdout);
        stdout.flush() catch |err| std.log.err("{any}\n", .{err});
        std.Io.sleep(io, std.Io.Duration.fromSeconds(1), std.Io.Clock.real) catch |err| std.log.err("{any}\n", .{err});
    }
}
