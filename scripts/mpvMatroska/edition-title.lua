-- 获取 Edition 标题并写入 user-data/edition-list

local mk = require "matroska"
local mkp = require "matroskaparser"
local mp = require "mp"

local function update_edition_list()
    local path = mp.get_property("path", "")
    if path == "" then return end

    local parser = mkp.Matroska_Parser:new(path)
    if parser and parser.is_valid and parser.Chapters then
        local editions = {}
        local edition, next_e = parser.Chapters:find_child(mk.chapters.EditionEntry)
        local id = 0
        while edition do
            local title = parser:get_edition_name(edition)
            if title == "" then title = nil end
            table.insert(editions, {
                id = id,
                title = title,
                default = edition:get_child(mk.chapters.EditionFlagDefault).value == 1
            })
            id = id + 1
            edition, next_e = parser.Chapters:find_next_child(next_e)
        end
        mp.set_property_native("user-data/edition-list", editions)
        parser:close()
    else
        if parser then parser:close() end
        local native = mp.get_property_native("edition-list")
        if native then
            mp.set_property_native("user-data/edition-list", native)
        end
    end
end

mp.register_event("file-loaded", update_edition_list)