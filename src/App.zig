const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const c = @cImport({
    @cInclude("raylib.h");
    @cInclude("iconset.rgi.h");
    @cDefine("RAYGUI_CUSTOM_ICONS", "");
    @cDefine("RAYGUI_IMPLEMENTATION", "");
    @cInclude("raygui.h");
});

state: State,
pixel_size: usize,
selected_tool: c_int = 0,
materials: [n_materials]Material = .{
    Material.water,
    Material.slime,
    Material.nitro,
    Material.sand,
    Material.heavy,
},
brush_size: c_int = 3,
raining: bool = false,
rain_frequency: f32 = 0.1,
rng: std.rand.DefaultPrng,

const App = @This();

const control_size = 50;
const n_materials = 5;
const tools_string = tools_string: {
    var tools: [:0]const u8 = std.fmt.comptimePrint("#{}#", .{c.ICON_CURSOR_HAND});
    for (1..n_materials + 1) |n| {
        tools = tools ++ std.fmt.comptimePrint(";{}", .{n});
    }
    break :tools_string tools;
};

fn init(
    allocator: Allocator,
    width: usize,
    height: usize,
    pixel_size: usize,
) !App {
    var state = try State.init(allocator, width, height);
    errdefer state.deinit(allocator);
    return .{
        .state = state,
        .pixel_size = pixel_size,
        .rng = std.rand.DefaultPrng.init(@bitCast(std.time.timestamp())),
    };
}

fn deinit(app: *App, allocator: Allocator) void {
    app.state.deinit(allocator);
    app.* = undefined;
}

fn open(app: App) void {
    c.InitWindow(
        @intCast(app.state.width * app.pixel_size),
        @intCast(@divExact(app.state.cells.len, app.state.width) * app.pixel_size + control_size),
        "Ripple Garden",
    );
    c.SetTargetFPS(60);
    c.GuiSetStyle(c.TOGGLE, c.GROUP_PADDING, 0);
}

fn close(_: App) void {
    c.CloseWindow();
}

fn shouldClose(_: App) bool {
    return c.WindowShouldClose();
}

fn handleInput(app: *App) void {
    const state_width = app.state.width;
    const state_height = @divExact(app.state.cells.len, state_width);
    const pixel_size_int: c_int = @intCast(app.pixel_size);

    if (c.IsMouseButtonDown(c.MOUSE_BUTTON_LEFT)) {
        const mouse_x = @divFloor(c.GetMouseX(), pixel_size_int);
        const mouse_y = @divFloor(c.GetMouseY(), pixel_size_int);
        if (mouse_x >= 0 and mouse_x < state_width and
            mouse_y >= 0 and mouse_y < state_height)
        {
            if (app.selected_tool == 0) {
                app.state.doBrush(
                    usize,
                    mouse_x,
                    mouse_y,
                    @intCast(app.brush_size),
                    makeRipple,
                    @intCast(app.brush_size),
                );
            } else {
                app.state.doBrush(
                    Material,
                    mouse_x,
                    mouse_y,
                    @intCast(app.brush_size),
                    makeMaterial,
                    app.materials[@intCast(app.selected_tool - 1)],
                );
            }
        }
    }
    for (0..n_materials + 1) |i| {
        if (c.IsKeyPressed(c.KEY_ZERO + @as(c_int, @intCast(i)))) {
            app.selected_tool = @intCast(i);
        }
    }
    if (app.raining and app.rng.random().float(f32) < app.rain_frequency) {
        const x = app.rng.random().uintLessThan(usize, state_width);
        const y = app.rng.random().uintLessThan(usize, state_height);
        app.state.cells.items(.h)[app.state.index(x, y)] = -1.0;
    }
}

fn makeMaterial(state: *State, x: usize, y: usize, _: f32, material: Material) void {
    state.cells.items(.material)[state.index(x, y)] = material;
}

fn makeRipple(state: *State, x: usize, y: usize, dist: f32, brush_size: usize) void {
    const h = &state.cells.items(.h)[state.index(x, y)];
    h.* = @min(h.*, -1.0 + dist / @as(f32, @floatFromInt(brush_size)));
}

fn draw(app: *App) void {
    const state_width = app.state.width;
    const state_height = @divExact(app.state.cells.len, state_width);

    c.BeginDrawing();
    defer c.EndDrawing();
    c.ClearBackground(c.GetColor(@bitCast(c.GuiGetStyle(c.DEFAULT, c.BACKGROUND_COLOR))));
    for (0..state_width) |x| {
        for (0..state_height) |y| {
            const cell = app.state.get(x, y);
            c.DrawRectangle(
                @intCast(x * app.pixel_size),
                @intCast(y * app.pixel_size),
                @intCast(app.pixel_size),
                @intCast(app.pixel_size),
                cell.material.color(cell.h),
            );
        }
    }

    c.GuiSetIconScale(2);
    defer c.GuiSetIconScale(1);
    const original_text_size = c.GuiGetStyle(c.DEFAULT, c.TEXT_SIZE);
    c.GuiSetStyle(c.DEFAULT, c.TEXT_SIZE, original_text_size * 2);
    defer c.GuiSetStyle(c.DEFAULT, c.TEXT_SIZE, original_text_size);
    _ = c.GuiToggleGroup(.{
        .x = 0,
        .y = @floatFromInt(state_height * app.pixel_size),
        .height = control_size,
        .width = control_size,
    }, tools_string, &app.selected_tool);
    for (app.materials, 1..) |material, i| {
        c.DrawRectangle(
            @intCast(i * control_size + 4),
            @intCast(state_height * app.pixel_size + 4),
            8,
            8,
            material.color(0.0),
        );
    }

    _ = c.GuiSpinner(.{
        .x = @floatFromInt((n_materials + 1) * control_size),
        .y = @floatFromInt(state_height * app.pixel_size),
        .height = control_size,
        .width = 2 * control_size,
    }, "", &app.brush_size, 1, 20, false);

    _ = c.GuiToggle(.{
        .x = @floatFromInt(state_width * app.pixel_size - control_size),
        .y = @floatFromInt(state_height * app.pixel_size),
        .height = control_size,
        .width = control_size,
    }, std.fmt.comptimePrint("#{}#", .{c.ICON_RAIN}), &app.raining);
}

const Material = struct {
    /// Mass. Higher masses will result in less acceleration from displacement
    /// (F = ma). Must be greater than 0.0.
    m: f32,
    /// Viscosity. Higher viscosities will proportionally slow velocity. Must
    /// be between 0.0 and 1.0, inclusive.
    visc: f32,
    /// Hue (color component). Must be between 0.0 (inclusive) and 360.0
    /// (exclusive).
    hue: f32,
    /// Value (color component). Must be between 0.0 and 1.0, inclusive.
    value: f32,

    pub const water: Material = .{
        .m = 1.0,
        .visc = 0.01,
        .hue = 240.0,
        .value = 1.0,
    };
    pub const slime: Material = .{
        .m = 5.0,
        .visc = 0.5,
        .hue = 120.0,
        .value = 0.75,
    };
    pub const nitro: Material = .{
        .m = 10.0,
        .visc = 0.0,
        .hue = 0.0,
        .value = 0.9,
    };
    pub const sand: Material = .{
        .m = 1.0,
        .visc = 1.0,
        .hue = 60.0,
        .value = 0.9,
    };
    pub const heavy: Material = .{
        .m = 100.0,
        .visc = 0.001,
        .hue = 300.0,
        .value = 0.9,
    };

    pub fn color(material: Material, height: f32) c.Color {
        return c.ColorFromHSV(
            material.hue,
            1.0 - (height + 1.0) / 2.0,
            material.value,
        );
    }
};

const Cell = struct {
    /// Height. Must be between -1.0 and 1.0, inclusive.
    h: f32 = 0.0,
    /// Velocity.
    v: f32 = 0.0,
    /// Acceleration. Recomputed on every step.
    a: f32 = 0.0,
    material: Material = Material.water,
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
        center_x: isize,
        center_y: isize,
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
                const x = center_x + x_offset;
                const y = center_y + y_offset;
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
        const materials = state.cells.items(.material);

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
                as[state.index(x, y)] = disp / 8.0 / materials[state.index(x, y)].m;
            }
        }

        for (hs, vs, as, materials) |*h, *v, *a, material| {
            v.* += a.*;
            v.* -= material.visc * v.*;
            h.* += v.*;
            h.* = @max(-1.0, @min(h.*, 1.0));
        }
    }
};

pub fn main() !void {
    var app = try App.init(std.heap.c_allocator, 300, 300, 3);
    defer app.deinit(std.heap.c_allocator);
    app.open();
    defer app.close();

    while (!app.shouldClose()) {
        app.state.step();
        app.handleInput();
        app.draw();
    }
}
