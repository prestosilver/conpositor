--- @class funcs
local M = {}

local function pt(pixels)
    return pixels * 1.3333
end

--- Set the font size in points.
--- @param name string The name of the font to use.
--- @param size number The size (in points) to use
function M.set_font_pt(name, size)
    session:set_font(name, pt(size))
end

--- Set the font size in pixels.
--- @param name string The name of the font to use.
--- @param size number The size (in pixels) to use
function M.set_font_pixels(name, size)
    session:set_font(name, size)
end

--- Creates a callback that reloads Conpositor
--- @return fun() # Returns a function callback
function M.reload()
    return function()
        package.loaded["init"] = nil
        require("init")
    end
end

--- Creates a callback that sets the active client border to size
--- @param size number The size (in pixels) of the client border
--- @return fun() # Returns a function that sets the client border to size
function M.set_client_border(size)
    local size = size
    return function()
        local client = session:active_client()
        if client then
            client.border = size
        end
    end
end

--- Creates a callback that toggles the floating state of the active client
--- @return fun() # Returns a function callback
function M.toggle_floating()
    return function()
        local client = session:active_client()
        if client then
            client.floating = not client.floating
        end
    end
end

--- Creates a callback that toggles the fullscreen state of the active client
--- @return fun() # Returns a function callback
function M.toggle_fullscreen()
    return function()
        local client = session:active_client()
        if client then
            client.fullscreen = not client.fullscreen
        end
    end
end

--- Creates a callback that kills the active client
--- @return fun() # Returns a function callback
function M.kill_client()
    return function()
        local client = session:active_client()
        if client then
            client:close()
        end
    end
end

--- Creates a callback that sets the tag of the active monitor
--- @param tag number The tag to set
--- @return fun() # Returns a function callback
function M.set_monitor_tag(tag)
    local tag = tag
    return function()
        local monitor = session:active_monitor()
        if monitor then
            monitor.active_tag = tag
        end
    end
end

--- Creates a callback that sets the tag of the active client
--- @param tag number The tag to set
--- @return fun() # Returns a function callback
function M.set_client_tag(tag)
    local tag = tag
    return function()
        local client = session:active_client()
        if client then
            client.tag = tag
        end
    end
end

--- Creates a callback that sets the stack of the active client
--- @param stack number The stack to set
--- @return fun() # Returns a function callback
function M.set_client_stack(stack)
    local stack = stack
    return function()
        local client = session:active_client()
        if client then
            client.stack = stack
        end
    end
end

function M.cycle_layout(direction, lists)
    local direction = direction
    local lists = lists
    return function()
        local monitor = session:active_monitor()
        local current_layout = monitor.layout
        if monitor then
            for _, list in pairs(lists) do
                for i, v in pairs(list) do
                    if v == current_layout then
                        local idx = i + direction - 1
                        while idx < 0 do
                            idx = idx + #list
                        end

                        monitor.layout = list[(idx % #list) + 1]
                        return
                    end
                end
            end
        end

        print("didnt cycle")
    end
end

---Creates a callback that cycles the focus in the active stack
---@param direction number The direction to cycle -1 is backwards 1 is forwards
---@return fun() # Returns a function callback
function M.cycle_focus(direction)
    -- TODO: make direction a string
    local direction = direction
    return function()
        session:cycle_focus(direction)
    end
end

---Creates a callback that spawns a command
---@param ... string The program to call
---@return fun() func The new spawn function
function M.spawn(...)
    local count = select('#', ...)

    local program = select(1, ...)
    local args = {}

    if count > 1 then
        for i = 2, count do
            local value = select(i, ...)
            args[i - 1] = value
        end
    end

    return function()
        session:spawn(program, args)
    end
end

--- Creates a callback that quits Conpositor
--- @return fun() # Returns a function callback
function M.quit()
    return function()
        session:quit()
    end
end

return M
