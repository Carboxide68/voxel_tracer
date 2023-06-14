const std = @import("std");
const log = std.log.scoped(.benchmark);

const Tracer = @import("Tracer.zig");

fn boxTraceBenchmark() void {
    {
    const start_simd = std.time.nanoTimestamp();
    _ = start_simd;
    };
}

pub fn main() !void {
    boxTraceBenchmark();
}
