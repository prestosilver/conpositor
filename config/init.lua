-- This is required to initialize LSP properly
--- @module 'types.all'
local gaps = require("lib.gaps") --- @class gaps
local funcs = require("lib.funcs") --- @class funcs
local mouse = require("lib.mouse") --- @class mouse

-- add an escape first in case of a lua crash
session:bind("AS", "Escape", funcs.quit())

-- load a colorscheme
-- TODO: impl

function reload_colors()
    -- TODO
end

-- Define the mod key
local mod = "L"

-- setup libraries
gaps.setup { inc = 4, toggle = true, value = 4, ratio = 2, outer = 20 }
mouse.setup {}

-- Create default tags
local stacks = { a = 1, b = 2, c = 3, d = 4, e = 5 }
local tags = { "F1", "F2", "F3", "F4" }

for tag, name in pairs(tags) do
    session.tags[tag].name = name
end

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
        a_container.stack = stacks.b
        b_container.stack = stacks.a

        c_container.stack = stacks.d
        d_container.stack = stacks.c
    else
        a_container.stack = stacks.a
        b_container.stack = stacks.b

        c_container.stack = stacks.c
        d_container.stack = stacks.d
    end
end

local default_layout = session:new_layout("] > [")
local center_layout = session:new_layout("] | [")
local lefty_layout = session:new_layout("] < [")
local default_layout_b = session:new_layout("[ > ]")
local center_layout_b = session:new_layout("[ | ]")
local lefty_layout_b = session:new_layout("[ < ]")

setup_abcd(default_layout.root, 0.7, 0.2, 0.4, false)
setup_abcd(center_layout.root, 0.5, 0.2, 0.4, false)
setup_abcd(lefty_layout.root, 0.3, 0.2, 0.4, false)

setup_abcd(lefty_layout_b.root, 0.7, 0.2, 0.4, true)
setup_abcd(center_layout_b.root, 0.5, 0.2, 0.4, true)
setup_abcd(default_layout_b.root, 0.3, 0.2, 0.4, true)

local lefty_cycle = {
    { lefty_layout,   center_layout,   default_layout, },  -- normal
    { lefty_layout_b, center_layout_b, default_layout_b, } -- flip
}

local flip_cycle = {
    { lefty_layout,   lefty_layout_b },  -- lefty
    { center_layout,  center_layout_b }, -- center
    { default_layout, default_layout_b } -- default
}

session:hook("add_monitor", function(monitor)
    monitor:set_layout(default_layout)
end)

--- Setup mouse config

--- @type Client?
local mouse_client = nil
local mouse_client_position = {}
local mouse_floating = false
local mouse_resize = {}
mouse_resize.start = function(client, position)
    mouse_client = client
    mouse_client_position = client.position
end
mouse_resize.move = function(position)
    mouse_client_position.width = position.x - mouse_client_position.x
    mouse_client_position.height = position.y - mouse_client_position.y

    mouse_client.position = mouse_client_position
end

local mouse_move = {}
mouse_move.start = function(client, position)
    mouse_client = client
    mouse_floating = client.floating
    if mouse_floating then
        mouse_client_position = client.position
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

        mouse_client.position = pos
    else
        local monitor = session:active_monitor()
        local size = monitor.position
        mouse_client.monitor = monitor
        if position.y - size.y < 0.5 * size.height then
            if position.x - size.x < 0.5 * size.width then
                mouse_client.stack = stacks.a
            else
                mouse_client.stack = stacks.b
            end
        else
            if position.x - size.x < 0.5 * size.width then
                mouse_client.stack = stacks.c
            else
                mouse_client.stack = stacks.d
            end
        end
    end
end


-- mousebinds
mouse.addBind("resize", mouse_resize)
mouse.addBind("move", mouse_move)

session:add_mouse_bind("L", "Left", mouse.bind("move"))
session:add_mouse_bind("L", "Right", mouse.bind("resize"))

-- programs
session:bind("L", "Return", funcs.spawn("foot"))

-- Floating
session:bind("L", "Space", funcs.toggle_floating())
session:bind("L", "F", funcs.toggle_fullscreen())
session:bind("L", "Q", funcs.kill_client())

-- tags
for tag, name in pairs(tags) do
    session:bind(super, name, funcs.set_monitor_tag(tag))
    session:bind(super .. "S", name, funcs.set_client_tag(tag))
end

-- stacks
for _, stack in pairs(stacks) do
    session:bind(super .. "S", "" .. stack, funcs.set_client_stack(stack))
end

-- debug tools
session:bind("L", "P", funcs.reload())
session:bind("L", "G", gaps.increase)
session:bind("LS", "G", gaps.decrease)
session:bind("LS", "V", gaps.toggle)

-- title modules
local icon_module = TextModule.new(function(client)
    return client.icon or ""
end)

local title_module = TextModule.new(function(client)
    return client.label or client.title or ""
end)

local default_modules = {
    left = { icon_module },
    center = { title_module },
    right = {}
}

-- default modules
session:add_rule({}, function(client)
    client.modules = default_modules
end)

-- module switch bind
session:bind(super .. "S", "L", debug_window_set(false))
session:bind(super, "L", debug_window_set(true))

-- default rule
session:add_rule({}, function(client)
    client.stack = stacks.c
    client.floating = true
    client.border = 6
end)

-- Other rules should go here. Rules apply to all clients
-- in order of creation. So if you have one before the
-- default rules it will be overridden.

session:hook("startup", function(startup)
    -- Run startup commands here
    -- Example:
    -- session:spawn("waybar", {})
end)
