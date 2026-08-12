--- @module 'types.all'
local gaps = require("lib.gaps") --- @class gaps
local funcs = require("lib.funcs") --- @class funcs
local mouse = require("lib.mouse") --- @class mouse

-- load colorscheme and libraries
require("mondo.colors")

-- add this first in case of crash
session:add_bind("AS", "Escape", funcs.quit())

-- some usefull consts
local force_debug = false
local terminal = "kitty"

local ab_split = 0.7
local ac_split = 0.2
local bd_split = 0.4

-- setup libraries
gaps.setup { inc = 4, toggle = true, value = 4, ratio = 2, outer = 20 }
mouse.setup {}

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

local function setup_abcd(root_container, in_ab_split, in_ac_split, in_bd_split, flip)
    local new_ac_split = in_ac_split
    local new_bd_split = in_bd_split
    if flip then
        new_ac_split = in_bd_split
        new_bd_split = in_ac_split
    end

    local bd_container = root_container:add_child(in_ab_split, 0.0, 1.0, 1.0)
    local ac_container = root_container:add_child(0.0, 0.0, in_ab_split, 1.0)

    local b_container = bd_container:add_child(0.0, 0.0, 1.0, new_bd_split)
    local d_container = bd_container:add_child(0.0, new_bd_split, 1.0, 1.0)

    local a_container = ac_container:add_child(0.0, 0.0, 1.0, new_ac_split)
    local c_container = ac_container:add_child(0.0, new_ac_split, 1.0, 1.0)
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

        layouts[layout_index] = session:new_layout(brackets[1] .. " " .. align_text .. " " .. brackets[2])

        local aligned_ab_split = ab_split
        if align == "center" then aligned_ab_split = 0.5 end
        if align == "left" then aligned_ab_split = 1.0 - ab_split end

        setup_abcd(layouts[layout_index].root, aligned_ab_split, ac_split, bd_split, reverse)

        align_cycle[reverse_index][align_index] = layouts[layout_index]
        reverse_cycle[align_index][reverse_index] = layouts[layout_index]
    end
end

-- mouse functions
---@class Client
local mouse_client = nil
local mouse_client_position = {}
local mouse_floating = false
local mouse_resize = {
    start = function(client, _)
        mouse_client = client
        mouse_client_position = client.position
    end,

    move = function(position)
        mouse_client_position.width = position.x - mouse_client_position.x
        mouse_client_position.height = position.y - mouse_client_position.y

        mouse_client.position = mouse_client_position
    end
}

local mouse_move = {
    start = function(client, position)
        mouse_client = client
        mouse_floating = client.floating
        if mouse_floating then
            mouse_client_position = client.position
            mouse_client_position.x = mouse_client_position.x - position.x
            mouse_client_position.y = mouse_client_position.y - position.y
        end
    end,

    move = function(position)
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
}

local super = "L"
if force_debug or session.debug then
    super = "A"
end

-- mousebinds
mouse.addBind("resize", mouse_resize)
mouse.addBind("move", mouse_move)

session:add_mouse_bind(super, "Left", mouse.bind("move"))
session:add_mouse_bind(super, "Right", mouse.bind("resize"))

-- programs
session:add_bind(super, "Return", funcs.spawn(terminal, "--class=termA"))
session:add_bind(super .. "S", "Return", funcs.spawn(terminal, "--class=termB"))
session:add_bind(super .. "C", "Return", funcs.spawn(terminal, "--class=termB"))
session:add_bind(super, "I", funcs.spawn(terminal, "--class=htop", "-e", "htop"))
session:add_bind(super, "M", funcs.spawn(terminal, "--class=music", "-e", "kew"))
session:add_bind(super, "R", funcs.spawn(terminal, "--class=filesD", "-e", "ranger"))
session:add_bind(super .. "S", "R", funcs.spawn(terminal, "--class=filesB", "-e", "ranger"))
session:add_bind(super, "V", funcs.spawn(terminal, "--class=cava", "-e", "cava"))

session:add_bind(super .. "S", "S", funcs.spawn("ss.sh"))
session:add_bind(super, "W", funcs.spawn("vivaldi", "--ozone-platform=wayland"))
session:add_bind(super, "A", funcs.spawn("pavucontrol"))

-- launchers
session:add_bind(super, "D", funcs.spawn("bemenu-launcher"))
session:add_bind(super .. "S", "D", funcs.spawn("j4-dmenu-desktop", "--dmenu=menu"))
session:add_bind(super .. "S", "W", funcs.spawn("bwpcontrol", "menu"))
session:add_bind(super, "T", funcs.spawn("mondocontrol", "menu"))

-- misc session mgmt
session:add_bind(super, "H", funcs.cycle_layout(1, align_cycle))
session:add_bind(super .. "S", "H", funcs.cycle_layout(1, reverse_cycle))
session:add_bind(super, "Tab", funcs.cycle_focus(1))
session:add_bind(super .. "S", "Tab", funcs.cycle_focus(-1))
session:add_bind(super, "Space", funcs.toggle_floating())
session:add_bind(super .. "S", "Escape", funcs.quit())
session:add_bind(super, "Q", funcs.kill_client())
session:add_bind(super, "F", funcs.toggle_fullscreen())

-- tags
for tag, name in pairs(tags) do
    session:add_bind(super, name, funcs.set_monitor_tag(tag))
    session:add_bind(super .. "S", name, funcs.set_client_tag(tag))
end

-- stacks
for _, stack in pairs(stacks) do
    session:add_bind(super .. "S", "" .. stack, funcs.set_client_stack(stack))
end

-- debug tools
session:add_bind(super, "P", funcs.reload())
session:add_bind(super, "G", gaps.increase)
session:add_bind(super .. "S", "G", gaps.decrease)
session:add_bind(super .. "S", "V", gaps.toggle)

-- title modules
local icon_module = TextModule.new(function(client)
    return client.icon or ""
end)

local title_module = TextModule.new(function(client)
    return client.label or client.title or ""
end)

local debug_module = TextModule.new(function(client)
    local label = client.label or "(none)"
    local title = client.title or "(none)"
    local appid = client.appid or "(none)"
    return "[" .. label .. "] title: '" .. title .. "' appid: '" .. appid .. "'"
end)

local default_modules = {
    left = { icon_module },
    center = { title_module },
    right = {}
}

local debug_modules = {
    left = { icon_module },
    center = { debug_module },
    right = { title_module }
}

local popup_modules = {
    left = {},
    center = { title_module },
    right = {}
}

local function debug_window_set(value)
    if value then
        return function()
            local client = session:active_client()
            if client then
                client.modules = debug_modules
            end
        end
    else
        return function()
            local client = session:active_client()
            if client then
                client.modules = default_modules
            end
        end
    end
end

-- default modules
session:add_rule({}, function(client)
    client.modules = default_modules
end)

-- module switch bind
session:add_bind(super .. "S", "L", debug_window_set(false))
session:add_bind(super, "L", debug_window_set(true))

-- default rule
session:add_rule({}, function(client)
    client.stack = stacks.c
    client.floating = true
    client.border = 6
end)

local client_rule = function(in_filter, in_rule)
    local filter = in_filter
    local rule = in_rule
    session:add_rule(filter, function(client)
        for key, value in pairs(rule) do
            if key == "stack" then
                client.floating = false
            end
            client[key] = value
        end
    end)
end

-- some client rules
client_rule({ appid = "termA" }, { stack = stacks.a, icon = "" })
client_rule({ appid = "termB" }, { stack = stacks.b, icon = "" })
client_rule({ appid = "termF" }, { icon = "" })
client_rule({ appid = "filesB" }, { stack = stacks.b, icon = "", label = "Files" })
client_rule({ appid = "filesD" }, { stack = stacks.d, icon = "", label = "Files" })
client_rule({ appid = "music" }, { stack = stacks.d, icon = "", label = "Music" })
client_rule({ appid = "discord" }, { stack = stacks.c, label = "Chat" })
client_rule({ appid = "htop" }, { stack = stacks.c, icon = "", label = "Tasks" })
client_rule({ appid = "Sxiv" }, { stack = stacks.b, icon = "", label = "Image" })
client_rule({ appid = "imv" }, { stack = stacks.b, icon = "", label = "Image" })
client_rule({ appid = "Chromium" }, { stack = stacks.c, icon = "" })
client_rule({ appid = "vivaldi-stable" }, { stack = stacks.c, icon = "" })
client_rule({ appid = "gimp" }, { stack = stacks.c, icon = "" })
client_rule({ appid = "pavucontrol" }, { stack = stacks.b, icon = "", label = "Volume" })
client_rule({ appid = "neovide" }, { stack = stacks.c, icon = "" })
client_rule({ appid = "PrestoEdit" }, { stack = stacks.c, icon = "" })
client_rule({ appid = "code-insiders" }, { stack = stacks.c, icon = "" })
client_rule({ appid = "dev.zed.Zed" }, { stack = stacks.c, icon = "" })
client_rule({ appid = "cava" }, { stack = stacks.b, icon = "", label = "Vis" })
client_rule({ appid = "SandEEE" }, { stack = stacks.c })
client_rule({ appid = "steam" }, { stack = stacks.c })

-- popups
client_rule({ title = "Discord Updater" }, { stack = nil, modules = popup_modules })
client_rule({ title = "GIMP Startup" }, { stack = nil, modules = popup_modules })

session:hook("startup", function(_)
    session:spawn("wlr-randr", {
        "--output", "DP-3", "--mode", "2560x1080", "--left-of", "eDP-1",
        "--output", "eDP-1", "--right-of", "DP-3"
    })
    session:spawn("awww-daemon", {})
    session:spawn("dunst", {})
    session:spawn("waybar", {})
    session:spawn("blueman-applet", {})
    session:spawn("nm-applet", {})
    session:spawn("/usr/lib/gsd-xsettings", {})
end)

session:hook("add_monitor", function(monitor)
    monitor.layout = layouts[layout("right", false)]
end)

function reload_colors()
    package.loaded["mondo.colors"] = nil
    require("mondo.colors")
end

function get_memory()
    collectgarbage("collect")
    return string.format("%.0fb", 1000 * collectgarbage("count"))
end

function active_client_title()
    local client = session:active_client()
    if client == nil then
        return "󰍹 Desktop"
    end

    local icon = client.icon or "?"
    local label = client.label or client.title or "Unknown client"

    return icon .. " " .. label
end

function active_tag()
    return session:active_monitor().active_tag.name
end

function active_layout()
    return session:active_monitor().layout.name
end
