--[[
------------------------------------------------------------------------------------
Art of Fighting 2 (aof2.zip) Hitbox & Axis Viewer - MAME 
Tested on MAME 0.287

Original data analysis, reverse engineering, and LUA script by XGargoyle. 
AI assistance has been used for optimizing the LUA script.
URL: https://github.com/XGargoyle79/hitbox-viewers/

Last updated: 20261119
------------------------------------------------------------------------------------
--]]

--[[
------------------------------------------------------------------------------------
KNOWN ISSUES:
- Crossover moves will have reverted boxes until the character lands and plays the turn animation
------------------------------------------------------------------------------------
--]]

cam_x_addr = cam_x_addr or 0x109792 
cam_y_addr = cam_y_addr or 0x109798 
floor_y    = floor_y or 216  -- Base ground Y level in 224px screen space

axis_size = 5 

-- Adjust the frame delay (0, 1, 2, 3...) until drawn boxes align with the rendered sprites
local frame_delay = 1

-- Colors used for the boxes. You can change the colors if you want (Colors in ARGB format)
colors = {
    hitbox_line      = 0xFFFF0000,
    hitbox_fill      = 0x00FF0000,
    hurtbox_line     = 0xFF0000FF,
    hurtbox_fill     = 0x000000FF,
    pushbox_line     = 0xFF00FF00,
    pushbox_fill     = 0x0000FF00,
    proj_hitbox_line = 0xFFFF66FF,
    proj_hitbox_fill = 0x00FF66FF,
    axis_color       = 0xFFFFFFFF
}

-- Define all box base addresses and their corresponding colors
local P1_boxes = {
    { addr = 0x109372, line = colors.hurtbox_line,     fill = colors.hurtbox_fill },     -- Hurtbox 1
    { addr = 0x109472, line = colors.hurtbox_line,     fill = colors.hurtbox_fill },     -- Hurtbox 2
    { addr = 0x109572, line = colors.hurtbox_line,     fill = colors.hurtbox_fill },     -- Hurtbox 3
    { addr = 0x109672, line = colors.hitbox_line,      fill = colors.hitbox_fill },      -- Hitbox 1
    { addr = 0x109772, line = colors.hitbox_line,      fill = colors.hitbox_fill },      -- Hitbox 2
    { addr = 0x109872, line = colors.pushbox_line,     fill = colors.pushbox_fill }      -- Pushbox, but not always present in every move
}

local P2_boxes = {
    { addr = 0x10A372, line = colors.hurtbox_line,     fill = colors.hurtbox_fill },     -- Hurtbox 1
    { addr = 0x10A472, line = colors.hurtbox_line,     fill = colors.hurtbox_fill },     -- Hurtbox 2
    { addr = 0x10A572, line = colors.hurtbox_line,     fill = colors.hurtbox_fill },     -- Hurtbox 3
    { addr = 0x10A672, line = colors.hitbox_line,      fill = colors.hitbox_fill },      -- Hitbox 1
    { addr = 0x10A772, line = colors.hitbox_line,      fill = colors.hitbox_fill },      -- Hitbox 2
    { addr = 0x10A872, line = colors.pushbox_line,     fill = colors.pushbox_fill }      -- Pushbox, but not always present in every move
}

local P1_proj_slots = {
    { status_addr = 0x109901, x_addr = 0x10990C, y_addr = 0x10990E, box_addr = 0x109972, line = colors.proj_hitbox_line, fill = colors.proj_hitbox_fill }, -- Projectile Slot 1
    { status_addr = 0x109A01, x_addr = 0x109A0C, y_addr = 0x109A0E, box_addr = 0x109A72, line = colors.proj_hitbox_line, fill = colors.proj_hitbox_fill }, -- Projectile Slot 2
    { status_addr = 0x109B01, x_addr = 0x109B0C, y_addr = 0x109B0E, box_addr = 0x109B72, line = colors.proj_hitbox_line, fill = colors.proj_hitbox_fill }  -- Projectile Slot 3
}

local P2_proj_slots = {
    { status_addr = 0x10A901, x_addr = 0x10A90C, y_addr = 0x10A90E, box_addr = 0x10A972, line = colors.proj_hitbox_line, fill = colors.proj_hitbox_fill }, -- Projectile Slot 1
    { status_addr = 0x10AA01, x_addr = 0x10AA0C, y_addr = 0x10AA0E, box_addr = 0x10AA72, line = colors.proj_hitbox_line, fill = colors.proj_hitbox_fill }, -- Projectile Slot 2
    { status_addr = 0x10AB01, x_addr = 0x10AB0C, y_addr = 0x10AB0E, box_addr = 0x10AB72, line = colors.proj_hitbox_line, fill = colors.proj_hitbox_fill }  -- Projectile Slot 3
}

-- history[1] = newest captured frame, history[2] = 1 frame older, etc.
local history = {}
local capture_count = 0
local frame_notifier = nil
local reset_notifier = nil

local function read_box_list(space, box_list)
    local out = {}
    for i, box in ipairs(box_list) do
        out[i] = {
            x0       = space:read_i8(box.addr + 0x00),
            x_growth = space:read_i8(box.addr + 0x01),
            y0       = space:read_i8(box.addr + 0x02),
            y_growth = space:read_i8(box.addr + 0x03),
            line     = box.line,
            fill     = box.fill
        }
    end
    return out
end

local function read_proj_slots(space, slots)
    local out = {}
    for _, slot in ipairs(slots) do
        local status = space:read_u8(slot.status_addr)
        if status == 0x0E then
            out[#out + 1] = {
                proj_x   = space:read_i16(slot.x_addr),
                proj_y   = space:read_i16(slot.y_addr),
                x0       = space:read_i8(slot.box_addr + 0x00),
                x_growth = space:read_i8(slot.box_addr + 0x01),
                y0       = space:read_i8(slot.box_addr + 0x02),
                y_growth = space:read_i8(slot.box_addr + 0x03),
                line     = slot.line,
                fill     = slot.fill
            }
        end
    end
    return out
end

local function capture_state()
    local rom = emu.romname()
    if not rom or not rom:match("aof2") then
        history = {}
        return
    end

    local machine = manager.machine
    if not machine or machine.paused then
        return
    end

    local cpu = machine.devices[":maincpu"]
    if not cpu then
        return
    end

    local space = cpu.spaces["program"]
    if not space then
        return
    end

    capture_count = capture_count + 1

    local P1_axis_x = space:read_i16(0x109010)
    local P1_axis_y = space:read_i16(0x109018)
    local P2_axis_x = space:read_i16(0x10A010)
    local P2_axis_y = space:read_i16(0x10A018)
    local P1_spos_x = space:read_i16(0x10900C)
    local P1_spos_y = space:read_i16(0x10900E)
    local P2_spos_x = space:read_i16(0x10A00C)
    local P2_spos_y = space:read_i16(0x10A00E)

    local P1_zoom_x = space:read_u8(0x109064) / 255
    local P1_zoom_y = space:read_u8(0x109065) / 255
    local P2_zoom_x = space:read_u8(0x10A064) / 255
    local P2_zoom_y = space:read_u8(0x10A065) / 255

    local P1_teamside = space:read_u8(0x109ABE)
    local P2_teamside = space:read_u8(0x109BBE)
    local P1_facing   = (P1_teamside == 0) and -1 or 1
    local P2_facing   = (P2_teamside == 0) and -1 or 1

    local cam_x = space:read_u16(cam_x_addr) or 0
    local cam_y = space:read_i16(cam_y_addr) or 0

    local p1_boxes_snap = read_box_list(space, P1_boxes)
    local hb1_first     = p1_boxes_snap[1] or { x0 = 0, y0 = 0, x_growth = 0, y_growth = 0 }

    local snapshot = {
        frame_num = capture_count,
        P1_axis_x = P1_axis_x,
        P1_axis_y = P1_axis_y,
        P2_axis_x = P2_axis_x,
        P2_axis_y = P2_axis_y,
        P1_spos_x = P1_spos_x,
        P1_spos_y = P1_spos_y,
        P2_spos_x = P2_spos_x,
        P2_spos_y = P2_spos_y,
        P1_zoom_x = P1_zoom_x,
        P1_zoom_y = P1_zoom_y,
        P2_zoom_x = P2_zoom_x,
        P2_zoom_y = P2_zoom_y,
        P1_facing = P1_facing,
        P2_facing = P2_facing,
        cam_x     = cam_x,
        cam_y     = cam_y,
        p1_boxes  = p1_boxes_snap,
        p2_boxes  = read_box_list(space, P2_boxes),
        p1_projs  = read_proj_slots(space, P1_proj_slots),
        p2_projs  = read_proj_slots(space, P2_proj_slots),
        hb1_debug = {
            x0    = hb1_first.x0,
            y0    = hb1_first.y0,
            x_gro = hb1_first.x_growth,
            y_gro = hb1_first.y_growth
        }
    }

    table.insert(history, 1, snapshot)
    local max_keep = math.max(frame_delay + 2, 5)
    while #history > max_keep do
        table.remove(history)
    end
end

local function draw_snapshot_boxes(screen, box_list, screen_x, screen_y, facing, zoom_x)
    local scale = 2
    for _, box in ipairs(box_list) do
        local right  = screen_x - scale * (facing * box.x0) * zoom_x
        local left   = right - scale * (facing * box.x_growth) * zoom_x
        local top    = screen_y - scale * box.y0 * zoom_x
        local bottom = top + scale * box.y_growth * zoom_x

        screen:draw_box(left, top, right, bottom, box.line, box.fill)
    end
end

local function draw_snapshot_projs(screen, projs, facing, zoom_x)
    local scale = 2
    for _, proj in ipairs(projs) do
        local screen_x = proj.proj_x
        local screen_y = 240 - proj.proj_y

        screen:draw_line(screen_x - axis_size, screen_y, screen_x + axis_size, screen_y, colors.axis_color)
        screen:draw_line(screen_x, screen_y - axis_size, screen_x, screen_y + axis_size, colors.axis_color)

        local right  = screen_x - scale * (facing * proj.x0) * zoom_x
        local left   = right - scale * (facing * proj.x_growth) * zoom_x
        local top    = screen_y - scale * proj.y0 * zoom_x
        local bottom = top + scale * proj.y_growth * zoom_x

        screen:draw_box(left, top, right, bottom, proj.line, proj.fill)
    end
end

local function draw_hitboxes()
    local rom = emu.romname()
    if not rom or not rom:match("aof2") then
        return
    end

    local screen = manager.machine.screens[":screen"]
    if not screen then
        return
    end

    if #history == 0 then
        return
    end

    local idx = math.min(#history, math.max(1, frame_delay + 1))
    local s = history[idx]
    if not s then
        return
    end

    local P1_screen_x = s.P1_spos_x
    local P1_screen_y = 240 - s.P1_spos_y
    local P2_screen_x = s.P2_spos_x
    local P2_screen_y = 240 - s.P2_spos_y

    draw_snapshot_boxes(screen, s.p1_boxes, P1_screen_x, P1_screen_y, s.P1_facing, s.P1_zoom_x)
    draw_snapshot_boxes(screen, s.p2_boxes, P2_screen_x, P2_screen_y, s.P2_facing, s.P2_zoom_x)

    -- P1 Character Axis
    screen:draw_line(P1_screen_x - axis_size, P1_screen_y, P1_screen_x + axis_size, P1_screen_y, colors.axis_color)
    screen:draw_line(P1_screen_x, P1_screen_y - axis_size, P1_screen_x, P1_screen_y + axis_size, colors.axis_color)

    -- P2 Character Axis
    screen:draw_line(P2_screen_x - axis_size, P2_screen_y, P2_screen_x + axis_size, P2_screen_y, colors.axis_color)
    screen:draw_line(P2_screen_x, P2_screen_y - axis_size, P2_screen_x, P2_screen_y + axis_size, colors.axis_color)

    -- Active Projectile Slots
    draw_snapshot_projs(screen, s.p1_projs, s.P1_facing, s.P1_zoom_x)
    draw_snapshot_projs(screen, s.p2_projs, s.P2_facing, s.P2_zoom_x)

    -- Diagnostic Overlay
  --  screen:draw_text(10, 12, string.format("Delay:%d Hist:%d/%d SnapFrame:%d", frame_delay, idx, #history, s.frame_num or 0), 0xFFFFFF00, 0x80000000)
  --  screen:draw_text(10, 20, string.format("P1 Spos:(%d,%d) Axis:(%d,%d)", s.P1_spos_x, s.P1_spos_y, s.P1_axis_x, s.P1_axis_y), 0xFFFF0000, 0x80000000)
  --  screen:draw_text(10, 28, string.format("HB1 X0:%d Y0:%d x_gro:%d y_gro:%d", s.hb1_debug.x0, s.hb1_debug.y0, s.hb1_debug.x_gro, s.hb1_debug.y_gro), 0xFFFFFFFF, 0x80000000)
end

local function install_frame_notifier()
    history = {}
    if manager.machine then
        frame_notifier = emu.add_machine_frame_notifier(capture_state)
    end
end

if manager.machine then
    reset_notifier = emu.add_machine_reset_notifier(install_frame_notifier)
    install_frame_notifier()
end

emu.register_frame_done(draw_hitboxes)