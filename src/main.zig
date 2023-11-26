const std = @import("std");
const Allocator = std.mem.Allocator;
const c = @cImport(@cInclude("raylib.h"));

const Cell = struct {
    h: f32 = 0.0,
    v: f32 = 0.0,
    a: f32 = 0.0,
    m: f32 = 1.0,
    visc: f32 = 0.01,
    hue: f32 = 240.0,
};

const State = struct {
    cells: std.MultiArrayList(Cell),
    width: usize,

    pub fn init(allocator: Allocator, width: usize, height: usize) Allocator.Error!State {
        var cells: std.MultiArrayList(Cell) = .{};
        try cells.setCapacity(allocator, width * height);
        for (0..cells.capacity) |_| {
            cells.appendAssumeCapacity(.{});
        }
        return .{
            .cells = cells,
            .width = width,
        };
    }

    pub fn deinit(state: *State, allocator: Allocator) void {
        state.cells.deinit(allocator);
        state.* = undefined;
    }

    pub fn index(state: State, x: usize, y: usize) usize {
        return y * state.width + x;
    }

    pub fn get(state: State, x: usize, y: usize) Cell {
        return state.cells.get(state.index(x, y));
    }

    pub fn doBrush(
        state: *State,
        comptime Ctx: type,
        center_x: usize,
        center_y: usize,
        brush_size: usize,
        action: fn (state: *State, x: usize, y: usize, dist: f32, ctx: Ctx) void,
        ctx: Ctx,
    ) void {
        const width = state.width;
        const height = @divExact(state.cells.len, width);
        var x_offset: isize = -@as(isize, @intCast(brush_size));
        while (x_offset <= brush_size) : (x_offset += 1) {
            var y_offset: isize = -@as(isize, @intCast(brush_size));
            while (y_offset <= brush_size) : (y_offset += 1) {
                const x = @as(isize, @intCast(center_x)) + x_offset;
                const y = @as(isize, @intCast(center_y)) + y_offset;
                const dist = std.math.hypot(f32, @floatFromInt(x_offset), @floatFromInt(y_offset));
                if (x >= 0 and x < width and
                    y >= 0 and y < height and
                    dist <= @as(f32, @floatFromInt(brush_size)))
                {
                    action(state, @intCast(x), @intCast(y), dist, ctx);
                }
            }
        }
    }

    pub fn step(state: *State) void {
        const width = state.width;
        const height = @divExact(state.cells.len, width);
        const hs = state.cells.items(.h);
        const vs = state.cells.items(.v);
        const as = state.cells.items(.a);
        const ms = state.cells.items(.m);
        const viscs = state.cells.items(.visc);

        for (0..width) |x| {
            for (0..height) |y| {
                var disp: f32 = -8.0 * hs[state.index(x, y)];
                if (x > 0) {
                    disp += hs[state.index(x - 1, y)];
                    if (y > 0) {
                        disp += hs[state.index(x - 1, y - 1)];
                    }
                    if (y < height - 1) {
                        disp += hs[state.index(x - 1, y + 1)];
                    }
                }
                if (x < width - 1) {
                    disp += hs[state.index(x + 1, y)];
                    if (y > 0) {
                        disp += hs[state.index(x + 1, y - 1)];
                    }
                    if (y < height - 1) {
                        disp += hs[state.index(x + 1, y + 1)];
                    }
                }
                if (y > 0) {
                    disp += hs[state.index(x, y - 1)];
                }
                if (y < height - 1) {
                    disp += hs[state.index(x, y + 1)];
                }
                as[state.index(x, y)] = disp / 8.0 / ms[state.index(x, y)];
            }
        }

        for (hs, vs, as, ms, viscs) |*h, *v, *a, m, visc| {
            a.* += -v.* * visc / m;
            v.* += a.*;
            h.* += v.*;
            h.* = @max(-1.0, @min(h.*, 1.0));
        }
    }
};

pub fn main() !void {
    const win_width = 800;
    const win_height = 800;
    const pixel_size = 2;
    const state_width = @divExact(win_width, pixel_size);
    const state_height = @divExact(win_height, pixel_size);
    c.InitWindow(win_width, win_height, "Ripple Garden");
    defer c.CloseWindow();

    var state = try State.init(std.heap.c_allocator, state_width, state_height);
    defer state.deinit(std.heap.c_allocator);

    c.SetTargetFPS(60);

    while (!c.WindowShouldClose()) {
        state.step();

        if (c.IsMouseButtonDown(c.MOUSE_BUTTON_LEFT)) {
            const mouse_x = @divFloor(c.GetMouseX(), pixel_size);
            const mouse_y = @divFloor(c.GetMouseY(), pixel_size);
            if (mouse_x >= 0 and mouse_x < state_width and
                mouse_y >= 0 and mouse_y < state_height)
            {
                state.doBrush(usize, @intCast(mouse_x), @intCast(mouse_y), 3, makeRipple, 3);
            }
        }
        if (c.IsMouseButtonDown(c.MOUSE_BUTTON_RIGHT)) {
            const mouse_x = @divFloor(c.GetMouseX(), pixel_size);
            const mouse_y = @divFloor(c.GetMouseY(), pixel_size);
            if (mouse_x >= 0 and mouse_x < state_width and
                mouse_y >= 0 and mouse_y < state_height)
            {
                state.doBrush(MaterialSpec, @intCast(mouse_x), @intCast(mouse_y), 5, makeMaterial, .{
                    .m = 10.0,
                    .visc = 0.001,
                    .hue = 30.0,
                });
            }
        }

        c.BeginDrawing();
        defer c.EndDrawing();
        c.ClearBackground(c.RAYWHITE);
        for (0..state_width) |x| {
            for (0..state_height) |y| {
                const cell = state.get(x, y);
                const disp = (cell.h + 1.0) / 2.0;
                const color = c.ColorFromHSV(cell.hue, 1.0 - disp, 1.0);
                c.DrawRectangle(
                    @intCast(x * pixel_size),
                    @intCast(y * pixel_size),
                    pixel_size,
                    pixel_size,
                    color,
                );
            }
        }
    }
}

const MaterialSpec = struct {
    m: f32,
    visc: f32,
    hue: f32,
};

fn makeMaterial(state: *State, x: usize, y: usize, _: f32, spec: MaterialSpec) void {
    state.cells.items(.m)[state.index(x, y)] = spec.m;
    state.cells.items(.visc)[state.index(x, y)] = spec.visc;
    state.cells.items(.hue)[state.index(x, y)] = spec.hue;
}

fn makeRipple(state: *State, x: usize, y: usize, dist: f32, brush_size: usize) void {
    state.cells.items(.h)[state.index(x, y)] = -1.0 + dist / @as(f32, @floatFromInt(brush_size));
}
