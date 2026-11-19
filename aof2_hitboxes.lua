--[[
------------------------------------------------------------------------------------
Art of Fighting 2 (aof2.zip) Hitbox & Axis Viewer

Data analysis and reverse engineering by XGargoyle. 
LUA script developed by XGargoyle and optimized with AI assistance.
URL: https://github.com/XGargoyle79/hitbox-viewers/
------------------------------------------------------------------------------------
--]]


cam_x_addr = cam_x_addr or 0x109792 
cam_y_addr = cam_y_addr or 0x109798 
floor_y    = floor_y or 216  --shouldn't be 214???   -- Base ground Y level in 224px screen space

axis_size = 5 --GOOD!


--[[
------------------------------------------------------------------------------------
KNOWN ISSUES:
- Crossover moves will have reverted boxes until the character lands and plays the turn animation
- Hitboxes drawn on screen appear one frame ealier than the corresponding sprites

------------------------------------------------------------------------------------

TODO:
- port to FBNeo
- check 1 frame delay routines

--]]

-- Colors used for the boxes. You can change the colors if you want (Colors in ARGB format)
colors = {
    hitbox_line      = 0xFFFF0000,
    hitbox_fill      = 0x05FF0000,
    hurtbox_line     = 0xFF0000FF,
    hurtbox_fill     = 0x050000FF,
    pushbox_line     = 0xFF00FF00,
    pushbox_fill     = 0x0500FF00,
    proj_hitbox_line = 0xFFFF66FF,
    proj_hitbox_fill = 0x05FF66FF,
    axis_color       = 0xFFFFFFFF
}

-- Define all box base addresses and their corresponding colors
local P1_boxes = {
    { addr = 0x109372, line = colors.hurtbox_line,     fill = colors.hurtbox_fill },     -- Hurtbox 1
    { addr = 0x109472, line = colors.hurtbox_line,     fill = colors.hurtbox_fill },     -- Hurtbox 2
    { addr = 0x109572, line = colors.hurtbox_line,     fill = colors.hurtbox_fill },     -- Hurtbox 3
    { addr = 0x109672, line = colors.hitbox_line,      fill = colors.hitbox_fill },      -- Hitbox 1
    { addr = 0x109772, line = colors.hitbox_line,      fill = colors.hitbox_fill },      -- Hitbox 2
    { addr = 0x109872, line = colors.pushbox_line,     fill = colors.pushbox_fill }     -- Pushbox, but not always present in every move
  }

local P2_boxes = {
    { addr = 0x10A372, line = colors.hurtbox_line,     fill = colors.hurtbox_fill },     -- Hurtbox 1
    { addr = 0x10A472, line = colors.hurtbox_line,     fill = colors.hurtbox_fill },     -- Hurtbox 2
    { addr = 0x10A572, line = colors.hurtbox_line,     fill = colors.hurtbox_fill },     -- Hurtbox 3
    { addr = 0x10A672, line = colors.hitbox_line,      fill = colors.hitbox_fill },      -- Hitbox 1
    { addr = 0x10A772, line = colors.hitbox_line,      fill = colors.hitbox_fill },      -- Hitbox 2
    { addr = 0x10A872, line = colors.pushbox_line,     fill = colors.pushbox_fill }     -- Pushbox, but not always present in every move
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

-- Process raw data for CHARACTER boxes 
local function generate_boxes(space, screen, box_list, screen_x, screen_y, facing, zoom_x)
    local first_box_debug = { x0 = 0, y0 = 0, x_gro = 0, y_gro = 0 }
    
    for i, box in ipairs(box_list) do
        local x0       = space:read_i8(box.addr + 0x00)
        local x_growth = space:read_i8(box.addr + 0x01)
        local y0       = space:read_i8(box.addr + 0x02)
        local y_growth = space:read_i8(box.addr + 0x03)

        if i == 1 then
            first_box_debug = { x0 = x0, y0 = y0, x_gro = x_growth, y_gro = y_growth }
        end
        
        local anchor_x = screen_x
        local anchor_y = screen_y
        local scale    = 2 

        local right  = anchor_x - scale * (facing * x0) * zoom_x
        local left   = right - scale * (facing * x_growth) * zoom_x
        local top    = anchor_y - scale * y0 * zoom_x
        local bottom = top + scale * y_growth * zoom_x

        screen:draw_box(left, top, right, bottom, box.line, box.fill)
    end

    return first_box_debug
end

-- Process and draw active projectile slots individually based on their status flag (active = 0x0E)
local function draw_projectile_slots(space, screen, slots, facing, zoom_x)
    for _, slot in ipairs(slots) do
        local status = space:read_u8(slot.status_addr)
        
        -- Draw only if the slot status indicates an active projectile (0x0E)
        if status == 0x0E then
            local proj_x = space:read_i16(slot.x_addr)
            local proj_y = space:read_i16(slot.y_addr)
            local screen_x = proj_x
            local screen_y = 240 - proj_y

            -- 1. Draw Axis Cross for this active projectile slot
            screen:draw_line(screen_x - axis_size, screen_y, screen_x + axis_size, screen_y, colors.axis_color)
            screen:draw_line(screen_x, screen_y - axis_size, screen_x, screen_y + axis_size, colors.axis_color)

            -- 2. Read box offsets and draw hitbox
            local x0       = space:read_i8(slot.box_addr + 0x00)
            local x_growth = space:read_i8(slot.box_addr + 0x01)
            local y0       = space:read_i8(slot.box_addr + 0x02)
            local y_growth = space:read_i8(slot.box_addr + 0x03)

            local scale  = 2
            local right  = screen_x - scale * (facing * x0) * zoom_x
            local left   = right - scale * (facing * x_growth) * zoom_x
            local top    = screen_y - scale * y0 * zoom_x
            local bottom = top + scale * y_growth * zoom_x

            screen:draw_box(left, top, right, bottom, slot.line, slot.fill)
        end
    end
end

local function draw_hitboxes()
    local rom = emu.romname()
    if not rom:match("aof2") then 
        return 
    end

    local screen = manager.machine.screens[":screen"]
    local cpu = manager.machine.devices[":maincpu"]
    if not screen or not cpu then 
        return 
    end

    local space = cpu.spaces["program"]
    if not space then 
        return 
    end

-- Debug BG
--screen:draw_box(0, 0, 320, 240, 0xFF000000, 0xFF000000)

    -- 1. Read Raw Player Positions & Camera Scroll
    local P1_axis_x = space:read_i16(0x109010) -- 0x109290
    local P1_axis_y = space:read_i16(0x109018) -- 0x109298
    local P2_axis_x = space:read_i16(0x10A010) -- to change to 0x10A010? 0x109390
    local P2_axis_y = space:read_i16(0x10A018) -- to change to 0x10A018? 0x109398
    local P1_spos_x = space:read_i16(0x10900C) 
    local P1_spos_y = space:read_i16(0x10900E) 
    local P2_spos_x = space:read_i16(0x10A00C) 
    local P2_spos_y = space:read_i16(0x10A00E) 
       
    -- Other data
    local P1_zoom_x = space:read_u8(0x109064) / 255
    local P1_zoom_y = space:read_u8(0x109065) / 255
    local P2_zoom_x = space:read_u8(0x10A064) / 255
    local P2_zoom_y = space:read_u8(0x10A065) / 255
      
    local P1_teamside = space:read_u8(0x109ABE)
    local P2_teamside = space:read_u8(0x109BBE)
    local P1_sprite_facing = space:read_u8(0x1080BD)  -- TODO need to find out way to solve jumping over enemies->mirroring boxes
    local P2_sprite_facing = space:read_u8(0x10847D)  -- sprite facing may be actually face's teamside versus Character Axis??
    local P1_facing = (P1_teamside == 0) and -1 or 1
    local P2_facing = (P2_teamside == 0) and -1 or 1
    
    local cam_x = space:read_u16(cam_x_addr) or 0 -- placeholder until camera figured out
    local cam_y = space:read_i16(cam_y_addr) or 0



    -- 2. Convert Game Coordinates to Screen Space
    local P1_screen_x = P1_spos_x
    local P1_screen_y = 240 - P1_spos_y  
    local P2_screen_x = P2_spos_x 
    local P2_screen_y = 240 - P2_spos_y 
    

    -- 3. Process and Draw All Boxes and axis
    local hb1 = generate_boxes(space, screen, P1_boxes, P1_screen_x, P1_screen_y, P1_facing, P1_zoom_x)
    local hb2 = generate_boxes(space, screen, P2_boxes, P2_screen_x, P2_screen_y, P2_facing, P2_zoom_x)

    -- P1 Character Axis
    screen:draw_line(P1_screen_x - axis_size, P1_screen_y, P1_screen_x + axis_size, P1_screen_y, colors.axis_color)
    screen:draw_line(P1_screen_x, P1_screen_y - axis_size, P1_screen_x, P1_screen_y + axis_size, colors.axis_color)

    -- P2 Character Axis
    screen:draw_line(P2_screen_x - axis_size, P2_screen_y, P2_screen_x + axis_size, P2_screen_y, colors.axis_color)
    screen:draw_line(P2_screen_x, P2_screen_y - axis_size, P2_screen_x, P2_screen_y + axis_size, colors.axis_color)

    -- 4. Process and Draw Active Projectile Slots 
    draw_projectile_slots(space, screen, P1_proj_slots, P1_facing, P1_zoom_x)
    draw_projectile_slots(space, screen, P2_proj_slots, P2_facing, P2_zoom_x)
    
    -- 5. On-Screen Debug Text Overlay
    screen:draw_text(10, 20, string.format("P1 Screen: (%d, %d) | Game: (%d,%d)", P1_screen_x, P1_screen_y, P1_axis_x, P1_axis_y), 0xFFFF0000, 0x80000000)
    screen:draw_text(10, 27, string.format("P2 Screen: (%d, %d) | Game: (%d,%d)", P2_screen_x, P2_screen_y, P2_axis_x, P2_axis_y), 0xFFFFFF00, 0x80000000)
    screen:draw_text(10, 34, string.format("HB1 X0:%d Y0:%d x_gro:%d y_gro:%d", hb1.x0, hb1.y0, hb1.x_gro, hb1.y_gro), 0xFFFF0000, 0x80000000)
    screen:draw_text(10, 41, string.format("P1 facing:%d | P1 zoom: %.2f", P1_facing, P1_zoom_x), 0xFFFFFF00, 0x80000000)
    screen:draw_text(10, 48, string.format("CAM: (%d,%d)", cam_x, cam_y), 0xFFFFFFFF, 0x80000000)
end

-- Register frame hook
emu.register_frame_done(draw_hitboxes) -- draws the boxes one frame earlier than the screen
-- emu.register_frame(draw_hitboxes) -- draws the boxes only after the game is paused
