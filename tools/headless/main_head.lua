-- Prepended to the staged main.lua by tools/headless/run.py. It runs after
-- LOVE has loaded its modules and before any game code, so the game sees the
-- phone it is being tested as from its very first line.
--
-- run.py squashes this file onto main.lua's first line (so the game's line
-- numbers in tracebacks stay right) and drops everything after "--" on each
-- line: no "--" inside strings here, and every statement ends its own line.

-- BPM_HL_OS=Android/iOS takes the mobile code paths (safe area, fullscreen,
-- FPS cap, touch handling) that never run on a Windows desktop otherwise.
local fake_os = os.getenv('BPM_HL_OS')
if fake_os and fake_os ~= '' then
    love.system.getOS = function() return fake_os end
    love._os = fake_os
end

-- BPM_HL_INSETS="top,bottom" in points: what an iPhone's notch / Dynamic
-- Island and home indicator take, as getSafeArea reports them on the device.
local insets = os.getenv('BPM_HL_INSETS')
if insets and insets ~= '' then
    local top, bottom = insets:match('^(%d+),(%d+)$')
    top, bottom = tonumber(top) or 0, tonumber(bottom) or 0
    love.window.getSafeArea = function()
        local w, h = love.graphics.getDimensions()
        return 0, top, w, h - top - bottom
    end
end

-- A crash while the game's files load (before the harness is in) would show
-- LOVE's error screen on the hidden desktop and wait there until the runner's
-- timeout. Write a failing report and quit at once instead; the harness puts
-- its own handler in place once it loads.
love.errorhandler = function(msg)
    local text = 'game failed to load: ' .. tostring(msg) .. debug.traceback('', 2)
    local bs = string.char(92)
    text = text:gsub('[%c"' .. bs .. bs .. ']', function(c) return string.format(bs .. 'u%04x', c:byte()) end)
    local f = io.open((os.getenv('BPM_HL_OUT') or '.') .. '/report.json', 'wb')
    if f then
        f:write('{"ok":false,"checks":[],"shots":[],"warnings":[],"issues":[],"milestones":[],"errors":["' .. text .. '"]}')
        f:close()
    end
    return function() return 2 end
end
