-- Appended to the staged conf.lua by tools/headless/run.py, after the game's
-- own love.conf is defined, so its settings are kept and these land on top.

-- The Windows build talks to Steam on start-up and quits when Steam is not
-- there. A test run needs neither the Steam client nor achievements.
package.preload['luasteam'] = function()
    local noop = function() return true end
    local any = {__index = function() return noop end}
    return setmetatable({
        init = noop,
        shutdown = noop,
        userStats = setmetatable({}, any),
        friends = setmetatable({}, any),
    }, any)
end

local _headless_game_conf = love.conf
function love.conf(t)
    _headless_game_conf(t)
    -- Its own save folder: a test run must never write into the real
    -- %APPDATA%\Balatro profile.
    t.identity = os.getenv('BPM_HL_IDENTITY') or 'balatro-portrait-headless'
    t.appendidentity = false
    t.window.width = tonumber(os.getenv('BPM_HL_W')) or 412
    t.window.height = tonumber(os.getenv('BPM_HL_H')) or 915
    t.window.resizable = false
    t.window.vsync = 0
    -- Nothing else to hide: run.py starts the game on a desktop of its own
    -- that is never shown, so the window is not on the user's screen at all.
end
