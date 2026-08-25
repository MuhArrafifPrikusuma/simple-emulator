const std = @import("std");
const Io = std.Io;

const cpu_emulator = @import("cpu_emulator");

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
        std.debug.print("{d}\n", .{codes[i]});
    }
}

const Registers = struct {
    A: u16,
    DIN: u16,
    DOUT: u16,
    DSL: u16,
    IR: u16,
    MAR: u16,
    MBR: u16,
    PC: u16,
    SR: u16,
    Z: u16,
};
const State = enum {
    EXECUTE,
    FETCH,
};

var state: State = .FETCH;
var register: Registers = .{ .PC = 0x00 };
var ram: [4096]u8 = undefined;

fn run() !void {}
