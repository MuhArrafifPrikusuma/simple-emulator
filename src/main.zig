const std = @import("std");
const Io = std.Io;

const Registers = struct {
    A: u16 = undefined,
    DIN: u16 = undefined,
    DOUT: u16 = undefined,
    DSL: u16 = undefined,
    IR: u16 = 0x00,
    MAR: usize = 0x00,
    MBR: u16 = 0x00,
    PC: u16,
    SR: u16 = undefined,
    Z: u16 = undefined,
};
const State = enum {
    FETCH,
    DECODE,
    EXECUTE,
};

var state: State = .FETCH;
var cpu: Registers = .{ .PC = 0x00 };
var ram: [4096]u16 = undefined;
var clock_pulse: u8 = 1;
var current_ins: u8 = undefined;

const Instructions = *const fn (u8) void;
const instructions = blk: {
    var arr = [_]Instructions{nop} ** 16;

    arr[0] = hlt;
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
            switch (tick) {
                // NOTE: later use 1 to determine what state it is
                1 => cpu.PC += 1,
                2 => cpu.MBR = 0x00,
                3 => {
                    cpu.MBR = ram[cpu.MAR];
                    cpu.IR = cpu.MBR;
                    state = .DECODE;
                },

                else => {},
            }
        },
        .DECODE => {
            if (cpu.PC == ~@as(u16, 0) - 1) cpu.PC = 0x00;
            current_ins = getInstruction();
            clock_pulse = 1;
        },
        .EXECUTE => {
            instructions[current_ins](tick);
        },
    }
}

fn getInstruction() u8 {
    state = .EXECUTE;
    return @as(u8, @intCast(((cpu.IR & 0xF000) >> 12)));
}

// Instructions

fn nop(tick: u8) void {
    if (tick == 3) {
        cpu.MAR = cpu.PC;
        state = .FETCH;
    }
}
// NOTE: if i add interupt make sure to modify this
fn hlt(tick: u8) void {
    _ = tick;
}

fn dumpRegisters() void {
    std.log.debug("PC: 0x{X:0>4}, IR: 0x{X:0>4}, MAR: 0x{X:0>4}, MBR: 0x{x:0>4}", .{ cpu.PC, cpu.IR, cpu.MAR, cpu.MBR });
}

fn run(io: std.Io) void {
    @memset(&ram, 0x00);
    @memmove(ram[0..codes.len], codes);

    while (true) {
        cycle();
        dumpRegisters();
        std.Io.sleep(io, std.Io.Duration.fromSeconds(1), std.Io.Clock.real) catch |err| std.log.err("{any}\n", .{err});
    }
}
