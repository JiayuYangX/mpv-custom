-- sub-secondary-adjust.lua
-- 动态修改字幕位置，实现上下双字幕的效果
-- 通过创建 OSD 叠加层并同步尽可能多的 ASS 样式模拟默认字幕，以获取次字幕渲染高度；
-- 重新计算主字幕避让距离，实时监测变动并设置位置，避免因自动换行导致的主次字幕重叠

local mp = require "mp"

local overlay = mp.create_osd_overlay("ass-events")

local function get_rendered_height(text)
    if not text or text == "" then
        return nil
    end

    local font         = mp.get_property("sub-font", "sans-serif")
    local font_size    = mp.get_property_number("sub-font-size", 38)
    local scale        = mp.get_property_number("sub-scale", 1)
    local spacing      = mp.get_property_number("sub-spacing", 0)
    local bold         = mp.get_property_number("sub-bold", 0)
    local italic       = mp.get_property_number("sub-italic", 0)
    local align_x      = mp.get_property_number("sub-align-x", 0)
    local justify      = mp.get_property_number("sub-justify", 0)
    local line_spacing = mp.get_property_number("sub-line-spacing", 0)

    local an = align_x + 8
    local scaled_size = font_size * scale

    overlay.data = string.format(
        "{\\fn%s\\fs%g\\fsp%g\\b%d\\i%d\\an%d\\q%d}%s",
        font, scaled_size, spacing,
        bold, italic, an, justify,
        text:gsub("\\", "\\\\"):gsub("{", "\\{"):gsub("}", "\\}"):gsub("\n", "\\N")
    )
    overlay.compute_bounds = true
    overlay.hidden = true
    local res = overlay:update()

    if res and res.y0 and res.y1 then
        local rows = math.max(math.floor((res.y1 - res.y0) / scaled_size + 0.5), 1)
        local height = (rows + 0.2) * (scaled_size + line_spacing)
        return 100 * height / 720
    else
        return nil
    end
end

local function adjust_primary_sub_pos()
    local secondary_loaded = mp.get_property("secondary-sid") ~= "no"
    local secondary_visible = mp.get_property_native("secondary-sub-visibility")
    local secondary_text = mp.get_property("secondary-sub-text")
    local sub_pos = mp.get_property_number("secondary-sub-pos", 100)

    if not (secondary_loaded and secondary_visible) then
        mp.set_property_number("sub-pos", sub_pos)
        return
    end

    local height = get_rendered_height(secondary_text)

    if height then
        mp.set_property_number("sub-pos", sub_pos - height)
    end
end

mp.set_property_number("secondary-sub-pos", 100)
mp.observe_property("secondary-sid", "string", adjust_primary_sub_pos)
mp.observe_property("secondary-sub-visibility", "bool", adjust_primary_sub_pos)
mp.observe_property("secondary-sub-text", "string", adjust_primary_sub_pos)
mp.observe_property("secondary-sub-pos", "number", adjust_primary_sub_pos)
mp.observe_property("osd-width", "number", adjust_primary_sub_pos)
mp.observe_property("osd-height", "number", adjust_primary_sub_pos)
mp.register_event("file-loaded", adjust_primary_sub_pos)