-- Goes after the module's chunk for --source zygisk, and does what the native
-- side does on a phone: chunks come from portrait_game/ when it has them. A
-- mount gives the same result here, for threads too. The harness then goes into
-- the built main.lua the way run.py puts it into every other source's.

BPM_RESTORE_READ()
assert(love.filesystem.mount('portrait_game', '', false), 'the module chunk built no game')

package.preload['main'] = function(...)
    local first, rest = love.filesystem.read('main.lua'):match('^([^\n]*\n)[ \t]*\n(.*)$')
    local code = first .. BPM_MAIN_HEAD .. '\n' .. rest .. "\nrequire('bpm_headless')\n"
    return assert(loadstring(code, '@main.lua'))(...)
end

package.preload['luasteam'] = function()
    local noop = function() return true end
    local any = {__index = function() return noop end}
    return setmetatable({init = noop, shutdown = noop, userStats = setmetatable({}, any),
        friends = setmetatable({}, any)}, any)
end

local module_conf = love.conf
function love.conf(t)
    module_conf(t)
    t.identity = os.getenv('BPM_HL_IDENTITY') or 'balatro-portrait-headless'
    t.appendidentity = false
    t.window.width = tonumber(os.getenv('BPM_HL_W')) or 412
    t.window.height = tonumber(os.getenv('BPM_HL_H')) or 915
    t.window.resizable = false
    t.window.vsync = 0
end
