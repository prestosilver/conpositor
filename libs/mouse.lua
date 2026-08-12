---@class mouse
---@field current_bind mouse.Bind
local M = {}

---@class mouse.Bind
---@field start ?fun(client: Client, position: any)
---@field move ?fun(position: any)
---@field release ?fun()

function M.addBind(name, bind)
    M.binds[name] = bind
end

---Creates a new mouse bind for the specified action
function M.bind(action_name)
    local action_name = action_name

    return function(client, position)
        M.current_bind = M.binds[action_name]

        if M.current_bind.start then
            M.current_bind.start(client, position)
        end
    end
end

local function move_mouse(move_data)
    if M.current_bind == nil then
        return false
    end

    if M.current_bind.move then
        M.current_bind.move(move_data)
    end

    return true
end

local function release_mouse()
    if M.current_bind == nil then
        return
    end

    if M.current_bind.release then
        M.current_bind.release()
    end

    M.current_bind = nil

    return true
end

function M.setup(config)
    session:hook("mouse_move", move_mouse)
    session:hook("mouse_release", release_mouse)

    M.binds = M.binds or {}
    M.current_bind = M.current_bind or nil
end

return M
