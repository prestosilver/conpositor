-- require some builtin libraries
local gaps = require("lib.gaps") --- @class gaps
local funcs = require("lib.funcs") --- @class funcs
local mouse = require("lib.mouse") --- @class mouse

local mondo = require("mondo.colors") --- @class mondo

--- @module 'types.all'

-- add this first in case of crash
session:add_bind("AS", "Escape", funcs.quit())

local terminal = "kitty"

local ab_split = 0.7
local ac_split = 0.2
local bd_split = 0.4

-- add this first in case of crash
session:bind("AS", "Escape", funcs.quit())

-- setup libraries
gaps.setup { inc = 4, toggle = true, value = 4, ratio = 2, outer = 20 }
mouse.setup {}

-- set my super key
local super = force_debug or session.is_debug() and "A" or "L"

-- create my containers
local stacks = { a = 1, b = 2, c = 3, d = 4, e = 5 }
local tags = { "F1", "F2", "F3", "F4" }

for tag, name in pairs(tags) do
    session.tags[tag].name = name
end

local function layout(align, reverse)
    local align_id = 0
    local reverse_id = 0

    if align == "right" then align_id = 1 end
    if align == "center" then align_id = 2 end
    if align == "left" then align_id = 3 end

    if reverse == true then reverse_id = 0 end
    if reverse == false then reverse_id = 1 end

    return reverse_id * 3 + align_id
end

-- setup the base split system
local function setup_abcd(layout, ab_split, in_ac_split, in_bd_split, flip)
    local ac_split = flip and in_bd_split or in_ac_split
    local bd_split = flip and in_ac_split or in_bd_split

    session.layouts[layout].children = {
        { -- bd
            bounds = { ab_split, 0.0, 1.0, 1.0 },
            children = {
                { -- b
                    bounds = { 0.0, 0.0, 1.0, bd_split },
                    container = flip and stacks.d or stacks.b
                },
                { -- d
                    bounds = { 0.0, bd_split, 1.0, 1.0 },
                    container = flip and stacks.b or stacks.d
                }
            }
        },
        { -- ac
            bounds = { 0.0, 0.0, ab_split, 1.0 },
            children = {
                { -- a
                    bounds = { 0.0, 0.0, 1.0, ac_split },
                    container = flip and stacks.c or stacks.a
                },
                { -- c
                    bounds = { 0.0, ac_split, 1.0, 1.0 },
                    container = flip and stacks.a or stacks.c
                }
            }
        }
    }
end

local align_cycle = { {}, {} }
local reverse_cycle = { {}, {}, {} }
local layouts = {}
for align_index, align in ipairs { "right", "center", "left" } do
    local align_text
    if align == "right" then align_text = ">" end
    if align == "center" then align_text = "|" end
    if align == "left" then align_text = "<" end
    for reverse_index, reverse in ipairs { true, false } do
        local brackets
        if reverse == false then brackets = { "[", "]" } end
        if reverse == true then brackets = { "]", "[" } end

        local layout_index = layout(align, reverse)
        session.layouts[layout_index].name = brackets[1] .. " " .. align_text .. " " .. brackets[2]

        local aligned_ab_split = ab_split
        if align == "center" then aligned_ab_split = 0.5 end
        if align == "left" then aligned_ab_split = 1.0 - ab_split end

        setup_abcd(session.layouts[layout_index].root, aligned_ab_split, ac_split, bd_split, reverse)

        align_cycle[reverse_index][align_index] = session.layouts[layout_index]
        reverse_cycle[align_index][reverse_index] = session.layouts[layout_index]
    end
end

-- mouse functions
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
        local size = monitor.size
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

-- title modules
local icon_module = {}
icon_module.text = function(client)
    return client.icon or ""
end

local title_module = {}
title_module.text = function(client)
    return client.label or client.title or ""
end

local debug_module = {}
debug_module.text = function(client)
    local label = client.label or "(none)"
    local title = client.title or "(none)"
    local appid = client.appid or "(none)"
    return "[" .. label .. "] title: '" .. title .. "' appid: '" .. appid .. "'"
end

local close_icon = Texture:new("close.png")
local close_module = {}
close_module.image = function(client) close_icon end
close_module.on_click = function(client) client:close() end

local default_modules = {
    top = {
        left = {},
        center = { icon_module, title_module },
        right = { close_module }
    }
}

local debug_modules = {
    top = {
        left = { icon_module, title_module },
        center = { debug_module },
        right = { close_module }
    }
}

local function debug_window_set(value)
    local modules = value and default_modules or debug_modules

    return function()
        local client = session:active_client()
        if client then client.modules = modules end
    end
end

-- add the bar
local time_module = {}
time_module.text = function(monitor)
    return "TIME O CLOCK"
end

local active_layout_module = {}
active_layout_module.palette = mondo.inactive
active_layout_module.text = function(monitor)
    return monitor.layout.name
end

local active_tag_module = {}
active_tag_module.text = function(monitor)
    return monitor.layout.name
end

local active_client_icon_module = {}
active_client_icon_module.text = function(monitor)
    local client = monitor:active_client()

    if client then return client.icon end
    return "󰍹"
end

local active_client_module = {}
active_client_module.palette = mondo.inactive
active_client_module.text = function(monitor)
    local client = monitor:active_client()

    if client then return client.title end
    return "Desktop"
end

local default_bars = {
    top = {
        palette = mondo.active,

        left = { active_layout_module, tag_module, },
        center = { active_client_icon_module, active_client_module },
        right = { time_module }
    }
}

-- mouse binds
local mouse_resize_action = mouse.create_bind(mouse_resize)
local mouse_move_action = mouse.create_bind(mouse_move)

session:mouse("client", super, "Left", mouse_move_action)
session:mouse("client_frame", "", "Left", mouse_move_action)

session:mouse("client", super, "Right", mouse_resize_action)
session:mouse("client_frame", "", "Right", mouse_resize_action)

-- programs
session:bind(super, "Return", funcs.spawn(terminal, "--class=termA"))
session:bind(super .. "S", "Return", funcs.spawn(terminal, "--class=termB"))
session:bind(super .. "C", "Return", funcs.spawn(terminal, "--class=termB"))
session:bind(super, "I", funcs.spawn(terminal, "--class=htop", "-e", "htop"))
session:bind(super, "M", funcs.spawn(terminal, "--class=music", "-e", "kew"))
session:bind(super, "R", funcs.spawn(terminal, "--class=filesD", "-e", "ranger"))
session:bind(super .. "S", "R", funcs.spawn(terminal, "--class=filesB", "-e", "ranger"))
session:bind(super, "V", funcs.spawn(terminal, "--class=cava", "-e", "cava"))

session:bind(super .. "S", "S", funcs.spawn("ss.sh"))
session:bind(super, "W", funcs.spawn("vivaldi", "--ozone-platform=wayland"))
session:bind(super, "A", funcs.spawn("pavucontrol"))

-- launchers
session:bind(super, "D", funcs.spawn("bemenu-launcher"))
session:bind(super .. "S", "D", funcs.spawn("j4-dmenu-desktop", "--dmenu=menu"))
session:bind(super .. "S", "W", funcs.spawn("bwpcontrol", "menu"))
session:bind(super, "T", funcs.spawn("mondocontrol", "menu"))

-- misc session mgmt
session:bind(super, "H", funcs.cycle_layout(1, align_cycle))
session:bind(super .. "S", "H", funcs.cycle_layout(1, reverse_cycle))
session:bind(super, "Tab", funcs.cycle_focus(1))
session:bind(super .. "S", "Tab", funcs.cycle_focus(-1))
session:bind(super, "Space", funcs.toggle_floating())
session:bind(super .. "S", "Escape", funcs.quit())
session:bind(super, "Q", funcs.kill_client())
session:bind(super, "F", funcs.toggle_fullscreen())

-- tags
for name, tag in pairs(tags) do
    session:bind(super, "F" .. tag, funcs.set_monitor_tag(tag))
    session:bind(super .. "S", "F" .. tag, funcs.set_client_tag(tag))
end

-- stacks
for name, stack in pairs(stacks) do
    session:bind(super .. "S", "" .. stack, funcs.set_client_stack(stack))
end

-- debug tools
session:bind(super, "P", funcs.reload())
session:bind(super, "G", gaps.increase(2))
session:bind(super .. "S", "G", gaps.decrease(2))
session:bind(super .. "S", "V", gaps.toggle())

-- module switch bind
session:bind(super .. "S", "L", debug_window_set(false))
session:bind(super, "L", debug_window_set(true))

-- More specific rules
local client_rule = function(in_filter, in_rule)
    local filter = in_filter
    local rule = in_rule
    session:add_rule(filter, function(client)
        if rule.stack then client.floating = false end

        for key, value in pairs(rule) do
            client[key] = value
        end
    end)
end

-- some client rules
client_rule({ appid = "termA" }, { stack = stacks.a, icon = "" })
client_rule({ appid = "termB" }, { stack = stacks.b, icon = "" })
client_rule({ appid = "termF" }, { icon = "" })
client_rule({ appid = "filesB" }, { stack = stacks.b, icon = "", title = "Files" })
client_rule({ appid = "filesD" }, { stack = stacks.d, icon = "", title = "Files" })
client_rule({ appid = "music" }, { stack = stacks.d, icon = "", title = "Music" })
client_rule({ appid = "discord" }, { stack = stacks.c, icon = "DC", title = "Chat" })
client_rule({ appid = "htop" }, { stack = stacks.c, icon = "", title = "Tasks" })
client_rule({ appid = "Sxiv" }, { stack = stacks.b, icon = "", title = "Image" })
client_rule({ appid = "imv" }, { stack = stacks.b, icon = "", title = "Image" })
client_rule({ appid = "Chromium" }, { stack = stacks.c, icon = "" })
client_rule({ appid = "vivaldi-stable" }, { stack = stacks.c, icon = "" })
client_rule({ appid = "gimp" }, { stack = stacks.c, icon = "" })
client_rule({ appid = "pavucontrol" }, { stack = stacks.b, icon = "", title = "Volume" })
client_rule({ appid = "neovide" }, { stack = stacks.c, icon = "" })
client_rule({ appid = "PrestoEdit" }, { stack = stacks.c, icon = "" })
client_rule({ appid = "code-insiders" }, { stack = stacks.c, icon = "" })
client_rule({ appid = "cava" }, { stack = stacks.b, icon = "", title = "Vis" })
client_rule({ appid = "SandEEE" }, { stack = stacks.c })
client_rule({ appid = "steam" }, { stack = stacks.c })

session:add_hooks {
    startup = function(status)
        session:spawn("wlr-randr",
            "--output", "eDP-1", "--pos", "2560,0",
            "--output", "DP-4", "--mode", "2560x1080", "--pos", "0,0", "--preferred")
        session:spawn("swww-daemon")
        session:spawn("dunst")
        session:spawn("waybar")
        session:spawn("blueman-applet")
        session:spawn("nm-applet")
        session:spawn("/usr/lib/gsd-xsettings")
    end

    new_monitor = function(monitor)
        monitor.layout = default_layout
        monitor.bars = default_bars
    end

    new_client = function(client)
        client.modules = default_modules
        client.stack = stacks.c
        client.floating = true
        client.icon = "?"
        client.border = 3
        client.palette["active"] = mondo.active
        client.palette["inactive"] = mondo.inactive
    end
}

function reload_colors()
    package.loaded["mondo.colors"] = nil
    require("mondo.colors")
end

