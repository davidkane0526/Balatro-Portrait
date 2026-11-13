-- The black ellipse: on some phones the CRT shader's noise, the one place that
-- multiplies tc.x by tc.y, drew everything past x * y = 0.17 black. No desktop GPU
-- does this, and an emulation of half precision passed on a fix that failed on a
-- Pixel 7, so this does not try to draw it. The noise has to be gone from the
-- shader the game ships, as it is from the official Android one.
wait_title()
wait(1)
G.SETTINGS.GRAPHICS.crt = 70

-- The Zygisk build keeps the app's own shader and patches it as it loads.
local shipped = love.filesystem.read('resources/shaders/CRT.fs')
local has_rules, rules = pcall(require, 'portrait_shaders')
if has_rules and type(rules) == 'table' and rules.patches then
    for _, rule in ipairs(rules.patches['CRT.fs'] or {}) do
        local first, last = shipped:find(rule.find, 1, true)
        if first then shipped = shipped:sub(1, first - 1) .. rule.replace .. shipped:sub(last + 1) end
    end
end

local code = shipped:gsub('//[^\n]*', '')
check(not code:find('mod(tc.x', 1, true), 'no noise seed in the CRT shader')
check(not code:find('* dx', 1, true), 'no noise added to the picture')
check(code:find('extern MY_HIGHP_OR_MEDIUMP number noise_fac;', 1, true) ~= nil, 'noise_fac is declared')

-- game.lua sends noise_fac every frame, and send() fails on a uniform the shader
-- does not use: the shader has to compile and still take it.
local shader = love.graphics.newShader(shipped)
check(shader:hasUniform('noise_fac'), 'the shader still takes noise_fac')
G.SHADERS['CRT'] = shader
frames(4)
shot('crt_shipped')
