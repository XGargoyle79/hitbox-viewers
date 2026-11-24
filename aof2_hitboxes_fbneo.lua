--[[
------------------------------------------------------------------------------------
Art of Fighting 2 (aof2.zip) Hitbox & Axis Viewer - FBNeo 
Tested on Fightcade FBNeo v0.2.97.44-55

Original data analysis, reverse engineering, and LUA script by XGargoyle. 
AI assistance has been used for optimizing the LUA script.
URL: https://github.com/XGargoyle79/hitbox-viewers/

Last updated: 20261124
------------------------------------------------------------------------------------
--]]

--[[
------------------------------------------------------------------------------------
KNOWN ISSUES:
- Crossover moves will have reverted boxes until the character lands and plays the turn animation
------------------------------------------------------------------------------------
--]]


local cam_x_addr = cam_x_addr or 0x109792 
local cam_y_addr = cam_y_addr or 0x109798 
local floor_y    = floor_y or 216  -- Base ground Y level in 224px screen space

local axis_size  = 5

-- Adjust the frame delay (0, 1, 2, 3...) until drawn boxes align with the rendered sprites
local frame_delay = 2

-- Colors used for the boxes. You can change the colors if you want (Colors in RGBA format)
local colors = {
    hitbox_line      = 0xFF0000FF,
    hitbox_fill      = 0xFF000005,
    hurtbox_line     = 0x0000FFFF,
    hurtbox_fill     = 0x0000FF05,
    pushbox_line     = 0x00FF00FF,
    pushbox_fill     = 0x00FF0005,
    proj_hitbox_line = 0xFF66FFFF,
    proj_hitbox_fill = 0xFF66FF05,
    axis_color       = 0xFFFFFFFF
}

local function to_i8(val)
    val = val % 256
    if val >= 128 then
        return val - 256
    end
    return val
end

local function to_i16(val)
    val = val % 65536
    if val >= 32768 then
        return val - 65536
    end
    return val
end

local function read_i8(addr)
    return to_i8(memory.readbyte(addr))
end

local function read_i16(addr)
    return to_i16(memory.readword(addr))
end

-- Define all box base addresses and their corresponding colors
local P1_boxes = {
    { addr = 0x109372, line = colors.hurtbox_line, fill = colors.hurtbox_fill }, -- Hurtbox 1
    { addr = 0x109472, line = colors.hurtbox_line, fill = colors.hurtbox_fill }, -- Hurtbox 2
    { addr = 0x109572, line = colors.hurtbox_line, fill = colors.hurtbox_fill }, -- Hurtbox 3
    { addr = 0x109672, line = colors.hitbox_line,  fill = colors.hitbox_fill  }, -- Hitbox 1
    { addr = 0x109772, line = colors.hitbox_line,  fill = colors.hitbox_fill  }, -- Hitbox 2
    { addr = 0x109872, line = colors.pushbox_line, fill = colors.pushbox_fill }  -- Pushbox (not always present)
}

local P2_boxes = {
    { addr = 0x10A372, line = colors.hurtbox_line, fill = colors.hurtbox_fill }, -- Hurtbox 1
    { addr = 0x10A472, line = colors.hurtbox_line, fill = colors.hurtbox_fill }, -- Hurtbox 2
    { addr = 0x10A572, line = colors.hurtbox_line, fill = colors.hurtbox_fill }, -- Hurtbox 3
    { addr = 0x10A672, line = colors.hitbox_line,  fill = colors.hitbox_fill  }, -- Hitbox 1
    { addr = 0x10A772, line = colors.hitbox_line,  fill = colors.hitbox_fill  }, -- Hitbox 2
    { addr = 0x10A872, line = colors.pushbox_line, fill = colors.pushbox_fill }  -- Pushbox (not always present)
}

local P1_proj_slots = {
    { status_addr = 0x109901, x_addr = 0x10990C, y_addr = 0x10990E, box_addr = 0x109972, line = colors.proj_hitbox_line, fill = colors.proj_hitbox_fill },
    { status_addr = 0x109A01, x_addr = 0x109A0C, y_addr = 0x109A0E, box_addr = 0x109A72, line = colors.proj_hitbox_line, fill = colors.proj_hitbox_fill },
    { status_addr = 0x109B01, x_addr = 0x109B0C, y_addr = 0x109B0E, box_addr = 0x109B72, line = colors.proj_hitbox_line, fill = colors.proj_hitbox_fill }
}

local P2_proj_slots = {
    { status_addr = 0x10A901, x_addr = 0x10A90C, y_addr = 0x10A90E, box_addr = 0x10A972, line = colors.proj_hitbox_line, fill = colors.proj_hitbox_fill },
    { status_addr = 0x10AA01, x_addr = 0x10AA0C, y_addr = 0x10AA0E, box_addr = 0x10AA72, line = colors.proj_hitbox_line, fill = colors.proj_hitbox_fill },
    { status_addr = 0x10AB01, x_addr = 0x10AB0C, y_addr = 0x10AB0E, box_addr = 0x10AB72, line = colors.proj_hitbox_line, fill = colors.proj_hitbox_fill }
}

-- history[1] = newest captured frame, history[2] = 1 frame older, etc.
local history = {}

local function read_box_list(box_list)
    local out = {}
    for i, box in ipairs(box_list) do
        out[i] = {
            x0       = read_i8(box.addr + 0x00),
            x_growth = read_i8(box.addr + 0x01),
            y0       = read_i8(box.addr + 0x02),
            y_growth = read_i8(box.addr + 0x03),
            line     = box.line,
            fill     = box.fill
        }
    end
    return out
end

local function read_proj_slots(slots)
    local out = {}
    for _, slot in ipairs(slots) do
        local status = memory.readbyte(slot.status_addr)
        if status == 0x0E then
            out[#out + 1] = {
                proj_x   = read_i16(slot.x_addr),
                proj_y   = read_i16(slot.y_addr),
                x0       = read_i8(slot.box_addr + 0x00),
                x_growth = read_i8(slot.box_addr + 0x01),
                y0       = read_i8(slot.box_addr + 0x02),
                y_growth = read_i8(slot.box_addr + 0x03),
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

    local P1_axis_x = read_i16(0x109010)
    local P1_axis_y = read_i16(0x109018)
    local P2_axis_x = read_i16(0x10A010)
    local P2_axis_y = read_i16(0x10A018)
    local P1_spos_x = read_i16(0x10900C)
    local P1_spos_y = read_i16(0x10900E)
    local P2_spos_x = read_i16(0x10A00C)
    local P2_spos_y = read_i16(0x10A00E)

    local P1_zoom_x = memory.readbyte(0x109064) / 255
    local P1_zoom_y = memory.readbyte(0x109065) / 255
    local P2_zoom_x = memory.readbyte(0x10A064) / 255
    local P2_zoom_y = memory.readbyte(0x10A065) / 255

    local P1_teamside = memory.readbyte(0x109ABE)
    local P2_teamside = memory.readbyte(0x109BBE)
    local P1_facing   = (P1_teamside == 0) and 1 or -1
    local P2_facing   = (P2_teamside == 0) and 1 or -1

    local cam_x = memory.readword(cam_x_addr) or 0
    local cam_y = read_i16(cam_y_addr) or 0

    local p1_boxes_snap = read_box_list(P1_boxes)
    local p2_boxes_snap = read_box_list(P2_boxes)
    local hb1_first     = p1_boxes_snap[1] or { x0 = 0, y0 = 0, x_growth = 0, y_growth = 0 }

    local snapshot = {
        P1_axis_x  = P1_axis_x,
        P1_axis_y  = P1_axis_y,
        P2_axis_x  = P2_axis_x,
        P2_axis_y  = P2_axis_y,
        P1_spos_x  = P1_spos_x,
        P1_spos_y  = P1_spos_y,
        P2_spos_x  = P2_spos_x,
        P2_spos_y  = P2_spos_y,
        P1_zoom_x  = P1_zoom_x,
        P1_zoom_y  = P1_zoom_y,
        P2_zoom_x  = P2_zoom_x,
        P2_zoom_y  = P2_zoom_y,
        P1_facing  = P1_facing,
        P2_facing  = P2_facing,
        cam_x      = cam_x,
        cam_y      = cam_y,
        p1_boxes   = p1_boxes_snap,
        p2_boxes   = p2_boxes_snap,
        p1_projs   = read_proj_slots(P1_proj_slots),
        p2_projs   = read_proj_slots(P2_proj_slots),
        hb1_debug  = {
            x0    = hb1_first.x0,
            y0    = hb1_first.y0,
            x_gro = hb1_first.x_growth,
            y_gro = hb1_first.y_growth
        }
    }

    table.insert(history, 1, snapshot)
    local max_keep = math.max(frame_delay + 2, 4)
    while #history > max_keep do
        table.remove(history)
    end
end

local function draw_snapshot_boxes(box_list, screen_x, screen_y, facing, zoom_x)
    local scale = 2
    for _, box in ipairs(box_list) do
        local left   = screen_x + scale * (facing * box.x0) * zoom_x
        local top    = screen_y - scale *box.y0 * zoom_x
        local right  = left + scale * (facing * box.x_growth) * zoom_x
        local bottom = top + scale * box.y_growth * zoom_x
        gui.box(left, top, right, bottom, box.fill, box.line)
    end
end

local function draw_snapshot_projs(projs, facing, zoom_x)
    local scale = 2
    for _, proj in ipairs(projs) do
        local screen_x = proj.proj_x
        local screen_y = 240 - proj.proj_y

        gui.line(screen_x - axis_size, screen_y, screen_x + axis_size, screen_y, colors.axis_color)
        gui.line(screen_x, screen_y - axis_size, screen_x, screen_y + axis_size, colors.axis_color)

        local left   = screen_x + scale * (facing * proj.x0) * zoom_x
        local top    = screen_y - scale * proj.y0 * zoom_x
        local right  = left + scale * (facing * proj.x_growth) * zoom_x
        local bottom = top + scale * proj.y_growth * zoom_x
        
        gui.box(left, top, right, bottom, proj.fill, proj.line)
    end
end

local function draw_hitboxes()
    local idx = math.max(1, frame_delay + 1)
    local s = history[idx]
    if not s then
        return
    end

    local P1_screen_x = s.P1_spos_x
    local P1_screen_y = 240 - s.P1_spos_y
    local P2_screen_x = s.P2_spos_x
    local P2_screen_y = 240 - s.P2_spos_y

    draw_snapshot_boxes(s.p1_boxes, P1_screen_x, P1_screen_y, s.P1_facing, s.P1_zoom_x)
    draw_snapshot_boxes(s.p2_boxes, P2_screen_x, P2_screen_y, s.P2_facing, s.P2_zoom_x)

    -- P1 Character Axis
    gui.line(P1_screen_x - axis_size, P1_screen_y, P1_screen_x + axis_size, P1_screen_y, colors.axis_color)
    gui.line(P1_screen_x, P1_screen_y - axis_size, P1_screen_x, P1_screen_y + axis_size, colors.axis_color)

    -- P2 Character Axis
    gui.line(P2_screen_x - axis_size, P2_screen_y, P2_screen_x + axis_size, P2_screen_y, colors.axis_color)
    gui.line(P2_screen_x, P2_screen_y - axis_size, P2_screen_x, P2_screen_y + axis_size, colors.axis_color)

    -- Active Projectile Slots
    draw_snapshot_projs(s.p1_projs, s.P1_facing, s.P1_zoom_x)
    draw_snapshot_projs(s.p2_projs, s.P2_facing, s.P2_zoom_x)

end

emu.registerafter(capture_state)
gui.register(draw_hitboxes)