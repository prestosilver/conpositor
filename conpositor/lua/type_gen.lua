-- Creates a global type
_GenerateType = function(functions, methods, getters, setters)
    -- Stores instance fields, this is seperated out so that if a
    -- new ref to an obj at a different address it is still associated with the same data
    local instances = {}

    local result = {

        -- it is VERY IMPORTANT that _destroy is called when zig
        -- types go out of scope as otherwise lua will silently
        -- leak instance values
        _destroy = function(self)
            local hash = self:_hash()
            instances[hash] = nil
        end,

        __index = (function(self, index)
            -- Search for a getter first
            if getters[index] then
                -- Call it
                return getters[index](self.instance)
            end

            -- Now a method
            if methods[index] then
                -- Wrap with userdata
                return function(parent, ...)
                    return methods[index](parent.instance, ...)
                end
            end

            -- now check if the instance has fields created
            local hash = self:_hash()
            if instances[hash] then
                return instances[hash][index]
            end

            return nil
        end),

        __newindex = (function(self, index, value)
            -- Dont allow overwriting methods
            if methods[index] then
                error "Cant set a method"
            end

            -- Check for a setter
            if setters[index] then
                setters[index](self.instance, value)
                return
            end

            -- Setters arent required for getters
            -- but should fail if there isnt one
            if getters[index] then
                error "Cant set a ro value"
            end

            local hash = self:_hash()

            -- now check if the instance exists and create a field
            if instances[hash] == nil then
                instances[hash] = {}
            end

            instances[hash][index] = value
        end)
    }

    -- Static functions in classes, mostly intended for
    -- constructors like .new
    setmetatable(result, {
        __index = functions,
    });

    return result;
end
