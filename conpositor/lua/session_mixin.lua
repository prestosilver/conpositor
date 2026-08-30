--- @module 'types.all'

session.tags = {}
local tags_mt = {
    __index = function(_, index)
        return Session._get_tag(session, index)
    end,

    __newindex = function()
        error("Cant set a read only value")
    end
}

setmetatable(session.tags, tags_mt)
