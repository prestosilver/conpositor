local M = {}

-- TODO: Make this per monitor

local function update_gaps()
    local set_gaps_value = 0
    local set_gaps_valuei = 0
    if M.gaps_toggle then
        set_gaps_value = M.gaps_value
        set_gaps_valuei = set_gaps_value * M.gaps_ratio + M.gaps_outer
    end

    local monitor = session:active_monitor()
    if monitor then
        monitor.inner_gaps = set_gaps_value
        monitor.outer_gaps = set_gaps_valuei
    end
end

--- Toggles gaps on the active monitor
function M.toggle()
    M.gaps_toggle = not M.gaps_toggle

    update_gaps()
end

--- Gets the current gaps radius on the active monitor
--- @return number The size of the gaps
function M.get()
    return M.gaps_value
end

--- Sets the current gaps radius on the active monitor
--- @param value number The size of the gaps
function M.set(value)
    M.gaps_value = value
    if M.gaps_value < 0 then
        M.gaps_value = 0
    end

    update_gaps()
end

--- Increases the current gaps radius on the active monitor
function M.increase()
    M.set(M.gaps_value + M.gaps_inc)
end

--- Increases the current gaps radius on the active monitor
function M.decrease()
    M.set(M.gaps_value - M.gaps_inc)
end

---@class GapsConfig
---@field inc ?string The size to increase and decrease gaps by
---@field value ?bool The default visibility of gaps
---@field toggle ?number The default gaps radius
---@field ratio ?number How many pixels increase the outer radius
---@field outer ?number How many pixels to add to the outer radius

--- Init gaps
--- @param config GapsConfig The module config
function M.setup(config)
    if M.init then
        return
    end

    M.gaps_inc = config.inc or 0
    M.gaps_toggle = config.toggle or false
    M.gaps_value = config.value or 20
    M.gaps_ratio = config.ratio or 1.0
    M.gaps_outer = config.outer or 0.0
    M.init = true

    session:hook("add_monitor", function(monitor)
        local set_gaps_value = 0
        local set_gaps_valuei = 0
        if M.gaps_toggle then
            set_gaps_value = M.gaps_value
            set_gaps_valuei = set_gaps_value * M.gaps_ratio + M.gaps_outer
        end

        monitor.inner_gaps = set_gaps_value
        monitor.outer_gaps = set_gaps_valuei
    end)

    update_gaps()
end

return M
