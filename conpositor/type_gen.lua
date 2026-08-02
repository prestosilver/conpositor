_GenerateType = function(methods, getters, setters)
    local instances = {}

    return {
        _destroy = function(self)
            local hash = self:_hash()
            instances[hash] = nil
        end,

        __index = (function(self, index)
            if getters[index] then
                return getters[index](self.instance)
            end

            if methods[index] then
                return function(parent, ...)
                    return methods[index](parent.instance, ...)
                end
            end

            local hash = self:_hash()
            if instances[hash] then
                return instances[hash][index]
            end

            return nil
        end),

        __newindex = (function(self, index, value)
            if methods[index] then
                print "Cant set a method"
                return
            end

            if setters[index] then
                setters[index](self.instance, value)
                return
            end

            if getters[index] then
                print "Cant set a ro value"
                return
            end

            local hash = self:_hash()

            if instances[hash] == nil then
                instances[hash] = {}
            end

            instances[hash][index] = value
        end)
    }
end
