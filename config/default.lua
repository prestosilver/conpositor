gaps = require("conpositor.gaps")   -- A gap utility library
funcs = require("conpositor.funcs") -- Helper functions for bindings
mouse = require("conpositor.mouse") -- Some usual mouse binds so you dont have to implement them

-- add an escape first in case of a lua crash
session:add_bind("AS", "Escape", funcs.quit())

-- load a colorscheme
-- TODO: impl

function reload_colors()
    -- TODO
end

-- Define the mod key
local mod = "L"

-- setup libraries
gaps.setup { inc = 2, toggle = true, value = 8, ratio = 2, outer = 30 }
mouse.setup {}

-- Create default tags
stacks = { a = 1, b = 2, c = 3, d = 4, e = 5 }
tags = { session:new_tag("F1"), session:new_tag("F2"), session:new_tag("F3"), session:new_tag("F4") }

-- Create default layouts
local function setup_abcd(root_container, ab_split, in_ac_split, in_bd_split, flip)
    local ac_split = in_ac_split
    local bd_split = in_bd_split
    if flip then
        ac_split = in_bd_split
        bd_split = in_ac_split
    end

    local bd_container = root_container:add_child(ab_split, 0.0, 1.0, 1.0)
    local ac_container = root_container:add_child(0.0, 0.0, ab_split, 1.0)

    local b_container = bd_container:add_child(0.0, 0.0, 1.0, bd_split)
    local d_container = bd_container:add_child(0.0, bd_split, 1.0, 1.0)

    local a_container = ac_container:add_child(0.0, 0.0, 1.0, ac_split)
    local c_container = ac_container:add_child(0.0, ac_split, 1.0, 1.0)
    if flip then
        a_container:set_stack(stacks.b)
        b_container:set_stack(stacks.a)

        c_container:set_stack(stacks.d)
        d_container:set_stack(stacks.c)
    else
        a_container:set_stack(stacks.a)
        b_container:set_stack(stacks.b)

        c_container:set_stack(stacks.c)
        d_container:set_stack(stacks.d)
    end
end

local default_layout = session:add_layout("] > [")
local center_layout = session:add_layout("] | [")
local lefty_layout = session:add_layout("] < [")
local default_layout_b = session:add_layout("[ > ]")
local center_layout_b = session:add_layout("[ | ]")
local lefty_layout_b = session:add_layout("[ < ]")

setup_abcd(default_layout:root(), 0.7, 0.2, 0.4, false)
setup_abcd(center_layout:root(), 0.5, 0.2, 0.4, false)
setup_abcd(lefty_layout:root(), 0.3, 0.2, 0.4, false)

setup_abcd(lefty_layout_b:root(), 0.7, 0.2, 0.4, true)
setup_abcd(center_layout_b:root(), 0.5, 0.2, 0.4, true)
setup_abcd(default_layout_b:root(), 0.3, 0.2, 0.4, true)

local lefty_cycle = {
    { lefty_layout,   center_layout,   default_layout, },  -- normal
    { lefty_layout_b, center_layout_b, default_layout_b, } -- flip
}

local flip_cycle = {
    { lefty_layout,   lefty_layout_b },  -- lefty
    { center_layout,  center_layout_b }, -- center
    { default_layout, default_layout_b } -- default
}

session:add_hook("add_monitor", function(monitor)
    monitor:set_layout(default_layout)
end)

-- Setup mouse config
local mouse_client = nil
local mouse_client_position = {}
local mouse_floating = false

mouse_resize = {}
mouse_resize.start = function(client, position)
    mouse_client = client
    mouse_client_position = client:get_position()
end
mouse_resize.move = function(position)
    mouse_client_position.width = position.x - mouse_client_position.x
    mouse_client_position.height = position.y - mouse_client_position.y

    mouse_client:set_position(mouse_client_position)
end

mouse_move = {}
mouse_move.start = function(client, position)
    mouse_client = client
    mouse_floating = client:get_floating()
    if mouse_floating then
        mouse_client_position = client:get_position()
        mouse_client_position.x = mouse_client_position.x - position.x
        mouse_client_position.y = mouse_client_position.y - position.y
    end
end

mouse_move.move = function(position)
    if mouse_floating then
        local pos = {}
        pos.x = mouse_client_position.x + position.x
        pos.y = mouse_client_position.y + position.y
        pos.width = mouse_client_position.width
        pos.height = mouse_client_position.height

        mouse_client:set_position(pos)
    else
        local monitor = session:active_monitor()
        local size = monitor:get_size()
        mouse_client:set_monitor(monitor)
        if position.y - size.y < 0.5 * size.height then
            if position.x - size.x < 0.5 * size.width then
                mouse_client:set_stack(stacks.a)
            else
                mouse_client:set_stack(stacks.b)
            end
        else
            if position.x - size.x < 0.5 * size.width then
                mouse_client:set_stack(stacks.c)
            else
                mouse_client:set_stack(stacks.d)
            end
        end
    end
end

-- mousebinds
mouse.addBind("resize", mouse_resize)
mouse.addBind("move", mouse_move)

session:add_mouse("L", "Left", mouse.bind("move"))
session:add_mouse("L", "Right", mouse.bind("resize"))

-- programs
session:add_bind("L", "Return", funcs.spawn("foot"))

-- Floating
session:add_bind("L", "Space", funcs.toggle_floating())
session:add_bind("L", "F", funcs.toggle_fullscreen())
session:add_bind("L", "Q", funcs.kill_client())

-- tags
for idx, tag in pairs(tags) do
    session:add_bind("L", "F" .. idx, funcs.set_monitor_tag(tag))
    session:add_bind("LS", "F" .. idx, funcs.set_client_tag(tag))
end

-- stacks
for name, stack in pairs(stacks) do
    session:add_bind("LS", "" .. stack, funcs.set_client_stack(stack))
end

-- debug tools
session:add_bind("L", "P", funcs.reload())
session:add_bind("L", "G", gaps.increase)
session:add_bind("LS", "G", gaps.decrease)
session:add_bind("LS", "V", gaps.toggle)

-- title modules
local icon_module = Module.new(function(client)
    return client:get_icon() or ""
end)

local title_module = Module.new(function(client)
    return client:get_label() or client:get_title() or ""
end)

local debug_module = Module.new(function(client)
    local label = client:get_label() or "(none)"
    local title = client:get_title() or "(none)"
    local appid = client:get_appid() or "(none)"
    return "[" .. label .. "] title: '" .. title .. "' appid: '" .. appid .. "'"
end)

local default_modules = {
    left = {},
    center = { icon_module, title_module },
    right = {}
}

local debug_modules = {
    left = { icon_module },
    center = { debug_module },
    right = { title_module }
}

-- default modules
session:add_rule({}, function(client)
    client:set_modules(default_modules)
end)

-- module switch bind
session:add_bind(super .. "S", "L", debug_window_set(false))
session:add_bind(super, "L", debug_window_set(true))

-- default container
session:add_rule({}, function(client)
    client:set_stack(nil)
end)

-- default border width
session:add_rule({}, function(client)
    client:set_border(3)
end)

-- Other rules should go here. Rules apply to all clients
-- in order of creation. So if you have one before the
-- default rules it will be overridden.

session:add_hook("startup", function(startup)
    -- Run startup commands here
    -- Example:
    -- session:spawn("waybar", {})
end)
