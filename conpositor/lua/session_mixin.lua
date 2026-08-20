-- Make a table to store tags in
session.tags = {}
local tags_mt = {
    __index = function(_, index)
        return session:_get_tag(index)
    end,

    __newindex = function()
        error("Cant set a read only value")
    end
}

setmetatable(session.tags, tags_mt)
