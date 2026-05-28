-- osd-msg.lua
-- 提供一些可自定义格式的 OSD 消息，并修复默认消息可能存在的属性获取滞后问题
-- show-edition, show-chapter, show-filename, show-time

local mp = require "mp"
local utils = require "mp.utils"

local function show_edition(msg, def)
    local id = mp.get_property("edition")
    local title = def or "(不可用)"
    local edition_list = mp.get_property_native("user-data/edition-list", {})
    if id == "auto" then
        for _, edition in ipairs(edition_list) do
            if edition.default == true then
                title = string.format("默认 (%s)", edition.title or (edition.id + 1))
                break
            end
        end
    elseif id then
        local edition = edition_list[id + 1]
        title = edition and edition.title or (id + 1)
    end
    mp.osd_message(string.format(msg or "版本: %s", title))
end

local function show_chapter(msg, fmt, def)
    local id = mp.get_property_number("chapter")
    local title = def or "(不可用)"
    if id then
        fmt = fmt or "(%d) %s"
        local chapter_list = mp.get_property_native("chapter-list", {})
        local chapter_title = chapter_list[id + 1].title
        local num = id + 1
        local result = string.gsub(fmt, "(%%[^%%]-)([ds])", function(prefix, spec)
            if spec == "d" then
                return string.format(prefix .. "d", num)
            else
                return string.format(prefix .. "s", chapter_title)
            end
        end)
        title = result
    end
    mp.osd_message(string.format(msg or "章节: %s", title))
end

local function show_filename(msg)
    local id = mp.get_property_number("playlist-pos")
    local playlist = mp.get_property_native("playlist", {})
    local _, filename = utils.split_path(playlist[id + 1].filename)
    mp.osd_message(string.format(msg or "%s", filename))
end

local function show_time(msg)
    local function show()
        local t = mp.get_property_number("playback-time")
        if not t then return end
        local hours = math.floor(t / 3600)
        local mins = math.floor((t % 3600) / 60)
        local secs = t % 60
        mp.osd_message(string.format(msg or "%d:%02d:%02d", hours, mins, secs))
    end

    show(mp.get_property_number("playback-time"))
    if mp.get_property_bool("seeking") then
        local function on_seeking(_, s)
            if s then return end
            mp.unobserve_property(on_seeking)
            show()
        end
        mp.observe_property("seeking", "bool", on_seeking)
    else
        local skip = true
        local function on_time()
            if skip then skip = false; return end
            mp.unobserve_property(on_time)
            show()
        end
        mp.observe_property("playback-time", "number", on_time)
    end
end

mp.register_script_message("show-edition", show_edition)
mp.register_script_message("show-chapter", show_chapter)
mp.register_script_message("show-filename", show_filename)
mp.register_script_message("show-time", show_time)