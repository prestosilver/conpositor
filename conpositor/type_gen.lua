_GenerateType = function(methods, getters, setters)
    -- TODO: instances dosent work
    local instances = {}

    return {
        __index = (function(self, index)
            if getters[index] then
                return getters[index](self.instance)
            end

            if methods[index] then
                return function(parent, ...)
                    return methods[index](parent.instance, ...)
                end
            end

            if instances[self.instance] then
                return instances[self.instance][index]
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

            if instances[self.instance] == nil then
                instances[self.instance] = {}
            end

            instances[self.instance][index] = value
        end)
    }
end
