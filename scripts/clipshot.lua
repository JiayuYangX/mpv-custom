---Screenshot the video and copy it to the clipboard
---@author ObserverOfTime
---@license 0BSD

---@class ClipshotOptions
---@field name string
---@field type string
local o = {
    name = 'mpv-screenshot.jpeg',
    type = '' -- defaults to jpeg
}
require('mp.options').read_options(o, 'clipshot')

local file, cmd

local platform = mp.get_property_native('platform')
if platform == 'windows' then
    file = os.getenv('TEMP')..'\\'..o.name
    cmd = {
        'powershell', '-NoProfile', '-Command',
        'Add-Type -Assembly System.Windows.Forms, System.Drawing;',
        string.format(
            "[Windows.Forms.Clipboard]::SetImage([Drawing.Image]::FromFile('%s'))",
            file:gsub("'", "''")
        )
    }
elseif platform == 'darwin' then
    file = os.getenv('TMPDIR')..'/'..o.name
    -- png: «class PNGf»
    local type = o.type ~= '' and o.type or 'JPEG picture'
    cmd = {
        'osascript', '-e', string.format(
            'set the clipboard to (read (POSIX file %q) as %s)',
            file, type
        )
    }
else
    file = '/tmp/'..o.name
    if os.getenv('XDG_SESSION_TYPE') == 'wayland' then
        cmd = {'sh', '-c', ('wl-copy < %q'):format(file)}
    else
        local type = o.type ~= '' and o.type or 'image/jpeg'
        cmd = {'xclip', '-sel', 'c', '-t', type, '-i', file}
    end
end

---@param arg string
---@return fun()
local function clipshot(arg)
    return function()
        mp.commandv('screenshot-to-file', file, arg)
        mp.command_native_async({'run', unpack(cmd)}, function(suc, _, err)
            if arg == 'subtitles' then
                mp.osd_message(suc and '已复制截图到剪贴板 (带字幕)' or err, 1)
            elseif arg == 'video' then
                mp.osd_message(suc and '已复制截图到剪贴板 (不带字幕)' or err, 1)
            elseif arg == 'window' then
                mp.osd_message(suc and '已复制截图到剪贴板 (窗口)' or err, 1)
            end
        end)
    end
end

mp.add_key_binding('c',     'clipshot-subs',   clipshot('subtitles'))
mp.add_key_binding('C',     'clipshot-video',  clipshot('video'))
mp.add_key_binding('Alt+c', 'clipshot-window', clipshot('window'))
