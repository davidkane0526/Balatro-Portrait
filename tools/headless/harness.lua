-- Headless test harness. tools/headless/run.py copies this next to the game's
-- main.lua in a staging folder and requires it at the end of main.lua, so it
-- runs after the game has defined love.load/update/draw but before love.run
-- starts the loop. Nothing here ships in a build.
--
-- A scenario is a Lua file whose body runs as a coroutine, one resume per
-- frame. It sees the game globals (G, love, ...) plus the helpers defined in
-- `api` below, so an agent can drive a run, take screenshots and check the
-- layout without anyone at the keyboard. Everything ends up in report.json in
-- the output folder, and the process exit code is 0 only when nothing failed.

local OUT = os.getenv('BPM_HL_OUT') or '.'
local SCENARIO = os.getenv('BPM_HL_SCENARIO')
local TIMEOUT = tonumber(os.getenv('BPM_HL_TIMEOUT') or '') or 180
local GAMESPEED = tonumber(os.getenv('BPM_HL_GAMESPEED') or '')
local DEVICE = os.getenv('BPM_HL_DEVICE') or 'custom'
local LANG = os.getenv('BPM_HL_LANG')
if LANG == '' then LANG = nil end
local lang_applied, pending_menu_rebuild = false, false

-- Time follows frames, not the wall clock: each frame is 1/30 s, nothing
-- sleeps, and the game runs as fast as the machine draws it. A run stops
-- waiting on a clock and gets the same steps every time. --realtime turns it off.
local FRAME_STEP = os.getenv('BPM_HL_REALTIME') ~= '1' and 1 / 30 or nil
local stepped_time = love.timer.getTime()
if FRAME_STEP then
    love.timer.getTime = function() return stepped_time end
    love.timer.sleep = function() end
end

local report = {
    ok = true,
    device = DEVICE,
    scenario = SCENARIO,
    checks = {},
    shots = {},
    warnings = {},
    errors = {},
    log = {},
}
local started_at = love.timer.getTime()
local finished = false

local function now() return love.timer.getTime() - started_at end

-- Game clock: seconds times the speed the game itself runs at
-- (G.SPEEDFACTOR, which BPM_HL_GAMESPEED raises during a run; menus and
-- paused screens stay at 1). Scenario waits count this clock, so "wait for
-- the cards to land" lasts as long as the landing does at any game speed,
-- while taps, swipes and timeouts keep their own pace.
local game_clock = 0
local function game_now() return game_clock end

local function log(...)
    local parts = {}
    for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local line = string.format('[%7.2f] %s', now(), table.concat(parts, ' '))
    report.log[#report.log + 1] = line
    print(line)
    io.stdout:flush()
end

-- Just enough JSON for the report: strings, numbers, booleans, arrays, maps.
local function json(v, indent)
    indent = indent or ''
    local t = type(v)
    if t == 'string' then
        return '"' .. v:gsub('[%c"\\]', function(c)
            local map = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
            return map[c] or string.format('\\u%04x', c:byte())
        end) .. '"'
    elseif t == 'number' then
        if v ~= v or v == math.huge or v == -math.huge then return 'null' end
        return (math.floor(v) == v and math.abs(v) < 1e15) and string.format('%d', v) or string.format('%.4f', v)
    elseif t == 'boolean' then
        return tostring(v)
    elseif t == 'table' then
        local inner = indent .. '  '
        if #v > 0 or next(v) == nil then
            if next(v) == nil then return '[]' end
            local items = {}
            for _, x in ipairs(v) do items[#items + 1] = inner .. json(x, inner) end
            return '[\n' .. table.concat(items, ',\n') .. '\n' .. indent .. ']'
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        local items = {}
        for _, k in ipairs(keys) do items[#items + 1] = inner .. json(k) .. ': ' .. json(v[k], inner) end
        return '{\n' .. table.concat(items, ',\n') .. '\n' .. indent .. '}'
    end
    return 'null'
end

local function write_file(name, data)
    local f = io.open(OUT .. '/' .. name, 'wb')
    if not f then return false end
    f:write(data)
    f:close()
    return true
end

local function screen_info()
    local w, h = love.graphics.getDimensions()
    return {
        width = w, height = h,
        os = love.system.getOS(),
        portrait = G and G.F_PORTRAIT or false,
        tilescale = G and G.TILESCALE,
        room = (G and G.ROOM) and {x = G.ROOM.T.x, y = G.ROOM.T.y, w = G.ROOM.T.w, h = G.ROOM.T.h} or nil,
        version = G and G.VERSION,
    }
end

local function finish(code)
    if finished then return end
    finished = true
    report.duration = now()
    report.screen = screen_info()
    write_file('report.json', json(report) .. '\n')
    log(report.ok and 'RESULT: PASS' or 'RESULT: FAIL')
    love.event.quit(code or (report.ok and 0 or 1))
end

local function fail(msg)
    report.ok = false
    report.errors[#report.errors + 1] = tostring(msg)
    log('ERROR', msg)
end

-- A crash anywhere in the game writes the report and exits instead of showing
-- the crash screen, which would sit there waiting for a click forever.
-- love.errorhandler wins over the game's love.errhand in LOVE 11.
love.errorhandler = function(msg)
    fail('game crashed: ' .. tostring(msg) .. '\n' .. debug.traceback('', 2))
    finished = false
    pcall(finish, 2)
    return function() return 2 end
end

-- At boot the game re-applies the desktop video settings (Borderless at the
-- monitor's resolution by default), which turns the phone-sized window into a
-- full-screen landscape one. Pin every mode change to the size under test.
local WANT_W = tonumber(os.getenv('BPM_HL_W')) or 412
local WANT_H = tonumber(os.getenv('BPM_HL_H')) or 915

local function pinned_flags(flags)
    flags = flags or {}
    flags.fullscreen = false
    flags.resizable = false
    flags.vsync = 0
    return flags
end

local real_setMode, real_updateMode = love.window.setMode, love.window.updateMode
love.window.setMode = function(_, _, flags) return real_setMode(WANT_W, WANT_H, pinned_flags(flags)) end
love.window.updateMode = function(_, _, flags) return real_updateMode(WANT_W, WANT_H, pinned_flags(flags)) end
love.window.setFullscreen = function() return true end

-- The 12 s intro (logo, card flip) is the game's own "Skip splash" setting
-- away; only the boot scenario, which tests it, keeps it (BPM_HL_SPLASH=1).
if os.getenv('BPM_HL_SPLASH') ~= '1' and Game and Game.splash_screen then
    local game_splash = Game.splash_screen
    Game.splash_screen = function(self, ...)
        self.SETTINGS.skip_splash = 'Yes'
        -- Skipping the intro builds the title right here, and it reads the
        -- tutorial state, so the tutorial skip below has to be in by now.
        if os.getenv('BPM_HL_TUTORIAL') ~= '1' then
            self.SETTINGS.tutorial_complete = true
        elseif G.FUNCS and G.FUNCS.tutorial_controller then
            -- Kept: the tutorial's state is made by its controller on the
            -- first update, which the skipped intro would otherwise precede.
            G.FUNCS.tutorial_controller()
        end
        return game_splash(self, ...)
    end
end

-- On the hidden desktop every window rebuild (setMode) is followed by a
-- "shown" event, and with BPM_HL_OS=Android the game answers each one with a
-- resize that calls setMode again: one frame every two seconds. A phone only
-- sends visible(true) when the app comes back, so only a change is passed on.
local game_visible = love.visible
local last_visible = true
report.suppressed_visible = 0
love.visible = function(v)
    if v == last_visible then
        report.suppressed_visible = report.suppressed_visible + 1
        return
    end
    last_visible = v
    if game_visible then return game_visible(v) end
end

---------------------------------------------------------------------------
-- Coordinates
--
-- Game objects live in room units; the controller turns a screen pixel into
-- cursor units by dividing by TILESCALE*TILESIZE, and the room is drawn shifted
-- by ROOM.T. So a node's pixel position is (VT + ROOM.T) * TILESCALE*TILESIZE.
---------------------------------------------------------------------------

local function unit_px() return G.TILESCALE * G.TILESIZE end

local function node_rect_px(node)
    -- A UIBox is where its contents are drawn, which its own T can differ from.
    local T = (node.UIRoot and node.UIRoot.VT) or node.VT or node.T
    local s = unit_px()
    return (T.x + G.ROOM.T.x) * s, (T.y + G.ROOM.T.y) * s, T.w * s, T.h * s
end

local function node_visible(node)
    if not (node and node.states and node.states.visible) then return false end
    local p = node.parent
    local depth = 0
    while p and depth < 64 do
        if p.states and p.states.visible == false then return false end
        p = p.parent
        depth = depth + 1
    end
    return true
end

-- Every UI element on screen: G.I.NODE only holds bare Nodes, the buttons live
-- in the element trees under each UIBox.
local function each_ui_element(fn)
    local seen = {}
    local function walk(node)
        if type(node) ~= 'table' or seen[node] then return end
        seen[node] = true
        fn(node)
        if type(node.children) == 'table' then
            for _, child in pairs(node.children) do walk(child) end
        end
    end
    for _, kind in ipairs({'UIBOX', 'POPUP', 'ALERT'}) do
        for _, box in pairs(G.I[kind] or {}) do
            if box.states and box.states.visible then walk(box.UIRoot) end
        end
    end
end

local function find_nodes(q)
    local found = {}
    each_ui_element(function(node)
        local c = node.config
        if c and node_visible(node) then
            local hit = true
            if q.button and c.button ~= q.button then hit = false end
            if q.id and c.id ~= q.id then hit = false end
            -- A card's own buttons point back at it; several share a button
            -- name (the shop's Open and Redeem both become use_card).
            if q.card and c.ref_table ~= q.card then hit = false end
            if q.text then
                local txt = c.text or (c.object and c.object.string)
                if type(txt) == 'table' then txt = txt[1] and (txt[1].string or txt[1]) end
                if not (type(txt) == 'string' and txt:lower():find(q.text:lower(), 1, true)) then hit = false end
            end
            if hit then found[#found + 1] = node end
        end
    end)
    return found
end

---------------------------------------------------------------------------
-- Scenario API
---------------------------------------------------------------------------

local api = {}
local touch_id = 0

function api.log(...) log(...) end

function api.wait(seconds)
    local t = game_now() + (seconds or 0)
    repeat coroutine.yield() until game_now() >= t
end

-- Seconds at no game speed, for what a finger does (touch hold, swipe timing).
function api.wait_real(seconds)
    local t = now() + (seconds or 0)
    repeat coroutine.yield() until now() >= t
end

function api.frames(n)
    for _ = 1, (n or 1) do coroutine.yield() end
end

function api.wait_until(cond, timeout, label)
    local limit = now() + (timeout or 30)
    while true do
        local ok, res = pcall(cond)
        if ok and res then return true end
        if now() > limit then
            error('timed out waiting for ' .. (label or 'condition'), 0)
        end
        coroutine.yield()
    end
end

function api.wait_state(name, timeout)
    return api.wait_until(function() return G.STATE == G.STATES[name] and G.STATE_COMPLETE == true end,
        timeout, 'state ' .. name)
end

function api.wait_stage(name, timeout)
    return api.wait_until(function() return G.STAGE == G.STAGES[name] end, timeout, 'stage ' .. name)
end

-- Waits for the event queue to run dry, which is how the game itself tells
-- an animation from a settled screen.
function api.wait_idle(timeout)
    return api.wait_until(function()
        if not G.E_MANAGER then return true end
        for _, q in pairs(G.E_MANAGER.queues or {}) do
            for _, ev in ipairs(q) do
                if not ev.no_delete then return false end
            end
        end
        return true
    end, timeout or 30, 'idle event queue')
end

function api.check(cond, msg)
    report.checks[#report.checks + 1] = {ok = cond and true or false, msg = msg}
    if cond then
        log('ok   -', msg)
    else
        report.ok = false
        log('FAIL -', msg)
    end
    return cond
end

function api.warn(msg)
    report.warnings[#report.warnings + 1] = msg
    log('warn -', msg)
end

function api.shot(name)
    api.text_audit(name)
    local done = false
    local file = string.format('%02d_%s.png', #report.shots + 1, name)
    love.graphics.captureScreenshot(function(img)
        write_file(file, img:encode('png'):getString())
        done = true
    end)
    repeat coroutine.yield() until done
    report.shots[#report.shots + 1] = file
    log('shot', file)
    return file
end

-- x/y in pixels, or 0..1 fractions of the window.
local function to_px(x, y)
    local w, h = love.graphics.getDimensions()
    if x <= 1 and y <= 1 then return x * w, y * h end
    return x, y
end

-- Taps go through the touch events, the same path a phone takes, so the
-- game's anti-jitter and gesture code is exercised too.
function api.tap(x, y, hold)
    x, y = to_px(x, y)
    touch_id = touch_id + 1
    local id = touch_id
    love.event.push('mousemoved', x, y, 0, 0, false)
    api.frames(2)
    love.event.push('touchpressed', id, x, y, 0, 0, 1)
    api.wait_real(hold or 0.08)
    love.event.push('touchreleased', id, x, y, 0, 0, 1)
    api.frames(3)
end

function api.swipe(x1, y1, x2, y2, duration)
    x1, y1 = to_px(x1, y1)
    x2, y2 = to_px(x2, y2)
    duration = duration or 0.15
    touch_id = touch_id + 1
    local id = touch_id
    love.event.push('touchpressed', id, x1, y1, 0, 0, 1)
    local t0 = now()
    local px, py = x1, y1
    while now() - t0 < duration do
        local f = (now() - t0) / duration
        local nx, ny = x1 + (x2 - x1) * f, y1 + (y2 - y1) * f
        love.event.push('touchmoved', id, nx, ny, nx - px, ny - py, 1)
        px, py = nx, ny
        coroutine.yield()
    end
    love.event.push('touchmoved', id, x2, y2, x2 - px, y2 - py, 1)
    love.event.push('touchreleased', id, x2, y2, 0, 0, 1)
    api.frames(3)
end

function api.key(k)
    love.event.push('keypressed', k, k, false)
    api.frames(1)
    love.event.push('keyreleased', k, k)
    api.frames(2)
end

-- q = {button = 'play_cards_from_highlighted'} / {id = 'main_menu_play'} / {text = 'Play'}
function api.find(q)
    local nodes = find_nodes(q)
    return nodes[1], nodes
end

-- Logs every element that has a button or an id, so a scenario writer (or an
-- agent) can see what there is to tap on the current screen.
function api.dump_ui()
    each_ui_element(function(node)
        local c = node.config
        if c and (c.button or c.id) then
            local x, y, w, h = node_rect_px(node)
            log(string.format('ui button=%s id=%s visible=%s rect=(%.0f,%.0f %.0fx%.0f)',
                tostring(c.button), tostring(c.id), tostring(node_visible(node)), x, y, w, h))
        end
    end)
end

function api.rect(node)
    return node_rect_px(node)
end

function api.tap_node(node)
    local x, y, w, h = node_rect_px(node)
    api.tap(x + w / 2, y + h / 2)
end

-- A panel still sliding in, or input locked by the game during a transition,
-- swallows the tap; a person would wait for the screen to settle, so do that.
-- The game's own rule (Controller:set_cursor_hover): input is taken while
-- the controller is locked only if the game is paused under an overlay
-- (unlock popups, menus) and no screen wipe is running.
local function input_ready()
    local c = G.CONTROLLER
    if not c then return false end
    if c.locked and not (G.SETTINGS.paused and not G.screenwipe) then return false end
    if c.locks and c.locks.frame then return false end
    return true
end
api.input_ready = input_ready

-- Shop and pack cards bob forever, so their buttons never sit exactly on
-- their target; what matters is that the element has stopped travelling.
local last_pos = setmetatable({}, {__mode = 'k'})
local function settled(node)
    local T, VT = node.T, node.VT
    if VT and T and (math.abs(VT.x - T.x) > 0.05 or math.abs(VT.y - T.y) > 0.05) then
        local prev = last_pos[node]
        last_pos[node] = {VT.x, VT.y}
        if not prev or math.abs(prev[1] - VT.x) > 0.01 or math.abs(prev[2] - VT.y) > 0.01 then return false end
    end
    if not input_ready() then return false end
    for k, v in pairs(G.CONTROLLER.locks or {}) do
        if v and k ~= 'frame' then return false end
    end
    return true
end

-- Why an element is not tappable yet, for the timeout message.
local function unsettled_reason(node)
    if not node then return 'not found' end
    local c = G.CONTROLLER
    if c and c.locked then return 'input locked' end
    local locks = {}
    for k, v in pairs(c and c.locks or {}) do if v then locks[#locks + 1] = tostring(k) end end
    if #locks > 0 then return 'controller locks: ' .. table.concat(locks, ',') end
    return 'still moving'
end

function api.tap_ui(q, timeout)
    local node
    local ok = pcall(api.wait_until, function()
        node = api.find(q)
        return node ~= nil and settled(node)
    end, timeout or 15)
    if not ok then
        error('UI element ' .. json(q):gsub('%s+', ' ') .. ' not tappable: ' .. unsettled_reason(node), 0)
    end
    api.frames(10)
    api.tap_node(node)
    return node
end

-- Is the node fully on screen? Returns ok plus the pixel rect for the message.
function api.on_screen(node, margin)
    margin = margin or 1
    local w, h = love.graphics.getDimensions()
    local x, y, nw, nh = node_rect_px(node)
    local ok = x >= -margin and y >= -margin and x + nw <= w + margin and y + nh <= h + margin
    return ok, string.format('(%.0f,%.0f %.0fx%.0f in %dx%d)', x, y, nw, nh, w, h)
end

function api.check_on_screen(q, label)
    local node = api.find(q)
    if not node then return api.check(false, (label or json(q)) .. ' exists') end
    local ok, where = api.on_screen(node)
    return api.check(ok, (label or json(q)) .. ' is on screen ' .. where)
end

-- Every visible UIBox that pokes out of the window, as warnings. Boxes that
-- are still sliding in are skipped, they are off screen on purpose.
function api.layout_report(tag)
    local w, h = love.graphics.getDimensions()
    local out = {}
    for _, box in pairs(G.I.UIBOX or {}) do
        if node_visible(box) and box.VT and box.T
            and math.abs(box.VT.x - box.T.x) < 0.05 and math.abs(box.VT.y - box.T.y) < 0.05 then
            local x, y, bw, bh = node_rect_px(box)
            local covers_screen = x <= 0 and y <= 0 and x + bw >= w and y + bh >= h
            if bw > 1 and bh > 1 and not covers_screen
                and (x < -2 or y < -2 or x + bw > w + 2 or y + bh > h + 2)
                and x < w and y < h and x + bw > 0 and y + bh > 0 then
                local id = (box.config and box.config.id) or (box.UIRoot and box.UIRoot.config and box.UIRoot.config.id) or '?'
                out[#out + 1] = string.format('%s %s pokes out: (%.0f,%.0f %.0fx%.0f) in %dx%d',
                    tag or '', tostring(id), x, y, bw, bh, w, h)
            end
        end
    end
    for _, line in ipairs(out) do api.warn(line) end
    return out
end

-- Tappable elements and text that end up outside the window are what a
-- player actually loses on a phone, so these are recorded as issues (with the
-- screen they were seen on) on top of the box warnings above. Elements of a
-- box that is itself still moving are skipped.
local function ui_text(node)
    local c = node.config or {}
    local t = c.text
    if not t and c.object and c.object.strings and c.object.strings[1] then
        t = c.object.strings[1].string
    end
    if type(t) == 'table' then t = t[1] end
    return type(t) == 'string' and t or nil
end

report.issues = {}
local issue_seen = {}
function api.offscreen_check(tag)
    local w, h = love.graphics.getDimensions()
    local found = 0
    each_ui_element(function(node)
        if not (node_visible(node) and node.config and node.VT) then return end
        local box = node.UIBox
        if box and box.VT and box.T and (math.abs(box.VT.x - box.T.x) > 0.05 or math.abs(box.VT.y - box.T.y) > 0.05) then
            return
        end
        local c = node.config
        local text = ui_text(node)
        if not (c.button or text) then return end
        local x, y, nw, nh = node_rect_px(node)
        if nw < 1 or nh < 1 then return end
        local out_l, out_r = -x, x + nw - w
        local out_t, out_b = -y, y + nh - h
        local worst = math.max(out_l, out_r, out_t, out_b)
        -- Completely off screen is a parked element, not a clipped one.
        if worst > 2 and x < w and y < h and x + nw > 0 and y + nh > 0 then
            local what = c.button and ('button ' .. c.button) or ('text "' .. text:sub(1, 30) .. '"')
            local key = (tag or '') .. '|' .. what
            if not issue_seen[key] then
                issue_seen[key] = true
                found = found + 1
                local msg = string.format('%s: %s cut off by %.0fpx (%.0f,%.0f %.0fx%.0f in %dx%d)',
                    tag or '?', what, worst, x, y, nw, nh, w, h)
                report.issues[#report.issues + 1] = msg
                log('issue -', msg)
            end
        end
    end)
    return found
end

-- A menu panel that runs up to the screen edge reads as cut off on a phone even
-- when nothing inside it is clipped, so the overlay's drawn panel has to keep a
-- clear margin on both sides. The full-screen backdrop behind it is left out.
local PANEL_MARGIN = 0.2
function api.panel_margin_check(tag)
    local box = G.OVERLAY_MENU
    if not (box and box.UIRoot and box.VT and box.T and not box.REMOVED) then return end
    if math.abs(box.VT.x - box.T.x) > 0.05 or math.abs(box.VT.y - box.T.y) > 0.05 then return end
    local w = love.graphics.getWidth()
    local s = unit_px()
    local l, r = math.huge, -math.huge
    local function walk(node)
        if type(node) ~= 'table' or not node.T then return end
        if node ~= box.UIRoot and node_visible(node) and node.T.w > 0.05 and node.T.w * s < w * 1.5 then
            local x, _, nw = node_rect_px(node)
            l, r = math.min(l, x), math.max(r, x + nw)
        end
        for _, c in pairs(node.children or {}) do walk(c) end
    end
    walk(box.UIRoot)
    if l == math.huge then return end
    local margin = math.min(l, w - r) / s
    log(string.format('panel %s: left %.0fpx right %.0fpx (margin %.2f)', tag or '?', l, w - r, margin))
    if margin < PANEL_MARGIN then
        local key = (tag or '') .. '|panel'
        if not issue_seen[key] then
            issue_seen[key] = true
            local msg = string.format('%s: menu panel %.0fpx from the left edge, %.0fpx from the right (needs %.0fpx)',
                tag or '?', l, w - r, PANEL_MARGIN * s)
            report.issues[#report.issues + 1] = msg
            log('issue -', msg)
        end
    end
end

-- What the checks above cannot see: text that fits the screen but not its place.
-- Every shot walks what is drawn, tooltips and alerts too, and notes text running
-- out of its panel, across the edge of a panel it does not belong to, into other
-- text, off the screen, or too small to read. Noted in the report, for
-- tools/headless/audit.py to gather across runs; a note fails nothing by itself.
report.audit = {}
local audit_seen = {}
local UI_TEXT_MIN_PX = 5.5

-- A cut that keeps the report valid UTF-8.
local function audit_cut(s)
    local cut = s:sub(1, 40)
    if #s > 40 then cut = cut:gsub('[\192-\255][\128-\191]*$', '') end
    return cut
end

local function audit_note(kind, tag, text, detail)
    local key = kind .. '|' .. text .. '|' .. (detail or '')
    if audit_seen[key] or #report.audit >= 600 then return end
    audit_seen[key] = true
    report.audit[#report.audit + 1] = {kind = kind, tag = tag or '?', text = text, detail = detail or ''}
end

local function drawn_colour(c)
    return type(c) == 'table' and (c[4] == nil or c[4] > 0.25)
end

local function depth_x(a, b) return math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x) end
local function depth_y(a, b) return math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y) end

local function inside(a, b, tol)
    return a.x >= b.x - tol and a.y >= b.y - tol and a.x + a.w <= b.x + b.w + tol and a.y + a.h <= b.y + b.h + tol
end

local function audit_collect(box, kind, out, nested)
    local function walk(node, chain)
        if type(node) ~= 'table' or not node.T or not node.VT then return end
        if node.states and node.states.visible == false then return end
        local c = node.config or {}
        local r = {x = node.VT.x, y = node.VT.y, w = node.VT.w, h = node.VT.h}
        if node.UIT == G.UIT.T then
            local s = c.text or (c.ref_table and c.ref_value and tostring(c.ref_table[c.ref_value] or '')) or ''
            if type(s) == 'string' and s:find('%S') and r.w > 0.01 then
                out.texts[#out.texts + 1] = {r = r, s = s, chain = chain, box = box, kind = kind}
            end
        elseif node.UIT == G.UIT.O and c.object then
            local o = c.object
            if o.UIRoot then
                nested[o] = true
                walk(o.UIRoot, chain)
            elseif o.is and o:is(DynaText) and o.VT and o.states and o.states.visible ~= false then
                local s = o.string
                if type(s) == 'string' and s:find('%S') and (o.config.W or 0) > 0.01 then
                    out.texts[#out.texts + 1] = {r = {x = o.VT.x, y = o.VT.y, w = o.config.W, h = o.config.H},
                        s = s, chain = chain, box = box, kind = kind}
                end
            end
        elseif node.UIT and drawn_colour(c.colour) and r.w > 0.05 and r.h > 0.05 then
            local panel = {r = r, node = node, box = box, kind = kind}
            out.panels[#out.panels + 1] = panel
            local more = {}
            for i = 1, #chain do more[i] = chain[i] end
            more[#more + 1] = panel
            chain = more
        end
        for _, child in pairs(node.children or {}) do
            if type(child) == 'table' and not child.UIRoot then walk(child, chain) end
        end
    end
    walk(box.UIRoot, {})
end

function api.text_audit(tag)
    if not (G and G.I and G.ROOM and G.ROOM.T) then return end
    local s = unit_px()
    local screen = {x = -G.ROOM.T.x, y = -G.ROOM.T.y, w = love.graphics.getWidth() / s, h = love.graphics.getHeight() / s}
    local out, nested = {texts = {}, panels = {}}, {}
    local function usable(box)
        return box.UIRoot and not box.REMOVED and box.states and box.states.visible and box.VT and box.T
            and math.abs(box.VT.x - box.T.x) < 0.05 and math.abs(box.VT.y - box.T.y) < 0.05
            and not (G.SETTINGS.paused and not box.created_on_pause)
    end
    -- Boxes held inside another box go with it, so that box's panels count.
    local function mark(node)
        if type(node) ~= 'table' then return end
        local o = node.config and node.config.object
        if o and o.UIRoot then nested[o] = true mark(o.UIRoot) end
        for _, child in pairs(node.children or {}) do
            if type(child) == 'table' and not child.UIRoot then mark(child) end
        end
    end
    for _, kind in ipairs({'UIBOX', 'POPUP', 'ALERT'}) do
        for _, box in pairs(G.I[kind] or {}) do if box.UIRoot then mark(box.UIRoot) end end
    end
    -- A tooltip's side panels are plain boxes hung off it, and float with it.
    local function floats(box)
        local p = box.config and box.config.parent
        for _ = 1, 8 do
            if not p then return false end
            local owner = p.UIBox or p
            if owner.config and owner.config.instance_type then return true end
            p = owner.config and owner.config.parent or nil
        end
        return false
    end
    for _, kind in ipairs({'UIBOX', 'POPUP', 'ALERT'}) do
        for _, box in pairs(G.I[kind] or {}) do
            if usable(box) and not nested[box] then
                audit_collect(box, floats(box) and 'POPUP' or kind, out, nested)
            end
        end
    end

    local function same_layer(a, b)
        if a.kind == 'UIBOX' and b.kind == 'UIBOX' then return true end
        return a.box == b.box
    end
    for i, t in ipairs(out.texts) do
        local r = t.r
        local label = audit_cut(t.s)
        local off = math.max(screen.x - r.x, r.x + r.w - screen.x - screen.w, screen.y - r.y, r.y + r.h - screen.y - screen.h)
        local parked = depth_x(r, screen) <= 0 or depth_y(r, screen) <= 0
        if off > 0.02 and not parked then
            audit_note('offscreen', tag, label, string.format('%.0fpx', off * s))
        end
        if r.h * s < UI_TEXT_MIN_PX then
            audit_note('tiny', tag, label, string.format('%.1fpx', r.h * s))
        end
        local own = t.chain[#t.chain]
        if own and not parked then
            local p = own.r
            local spill_x = math.max(p.x - r.x, r.x + r.w - p.x - p.w)
            local spill_y = math.max(p.y - r.y, r.y + r.h - p.y - p.h)
            if spill_x > 0.04 or spill_y > 0.12 then
                audit_note('spill', tag, label, string.format('x %.2f y %.2f (text %.2f wide in %.2f)', spill_x, spill_y, r.w, p.w))
            end
        end
        local mine = {}
        for _, p in ipairs(t.chain) do mine[p] = true end
        for _, q in ipairs(out.panels) do
            if not parked and not mine[q] and same_layer(t, q) and depth_x(r, q.r) > 0.05 and depth_y(r, q.r) > 0.08
                and not inside(r, q.r, 0.02) then
                local c = q.node.config or {}
                audit_note('cross', tag, label, tostring(c.id or c.button or (q.box.config and q.box.config.id) or 'panel')
                    .. string.format(' %.2fx%.2f', q.r.w, q.r.h))
            end
        end
        for j = i + 1, #out.texts do
            local u = out.texts[j]
            if not parked and same_layer(t, u) then
                local dx, dy = depth_x(r, u.r), depth_y(r, u.r)
                if dx > 0.05 and dy > 0.05 and dx * dy > 0.15 * math.min(r.w * r.h, u.r.w * u.r.h) then
                    audit_note('collide', tag, label, audit_cut(u.s))
                end
            end
        end
    end
end

-- Opens every tooltip on the screen in turn and audits it: UI elements that carry
-- one, sprites with a hover of their own (tags, blinds, stakes), and the cards
-- in view. A deck's face-down pile is left out.
function api.hover_all(tag)
    local targets, seen = {}, {}
    local function add(o)
        if o and not seen[o] and not o.REMOVED then
            seen[o] = true
            targets[#targets + 1] = o
        end
    end
    local function walk(node)
        if type(node) ~= 'table' or not node.T then return end
        if node.states and node.states.visible == false then return end
        local c = node.config or {}
        if c.tooltip or c.on_demand_tooltip or c.h_popup then add(node) end
        local o = c.object
        if o then
            if o.UIRoot then
                walk(o.UIRoot)
            elseif o.cards then
                for _, card in ipairs(o.cards) do add(card) end
            elseif o.is and not o:is(DynaText) and o.states and o.states.visible ~= false
                and (o.hover ~= Node.hover or (o.config and o.config.h_popup)) then
                add(o)
            end
        end
        for _, child in pairs(node.children or {}) do
            if type(child) == 'table' and not child.UIRoot then walk(child) end
        end
    end
    for _, box in pairs(G.I.UIBOX or {}) do
        if box.UIRoot and not box.REMOVED and box.states and box.states.visible
            and not (G.SETTINGS.paused and not box.created_on_pause) then
            walk(box.UIRoot)
        end
    end
    if not G.SETTINGS.paused then
        for _, area in pairs(G.I.CARDAREA or {}) do
            if area ~= G.deck and area ~= G.discard and area.cards and area.states and area.states.visible ~= false then
                for _, card in ipairs(area.cards) do add(card) end
            end
        end
    end
    for _, o in ipairs(targets) do
        if not o.REMOVED then
            local ok, err = pcall(o.hover, o)
            if not ok then
                report.audit[#report.audit + 1] = {kind = 'error', tag = tag or '?', text = tostring(err):sub(1, 120), detail = 'hover'}
            end
            api.frames(3)
            local before = #report.audit
            api.text_audit(tag)
            -- A picture of what the audit just noted, for a few of them.
            if #report.audit > before and #report.shots < 120 then
                local kind = report.audit[#report.audit].kind
                if kind == 'offscreen' or kind == 'spill' then api.shot(tag .. '_note') end
            end
            pcall(o.stop_hover, o)
        end
    end
    api.frames(2)
    return #targets
end

-- One call per screen worth looking at: screenshot plus the layout checks.
function api.screen_check(tag)
    api.shot(tag)
    api.layout_report(tag)
    api.offscreen_check(tag)
    api.panel_margin_check(tag)
end

-- The layout styles' rules, measured (portrait_layouts.lua): every block on
-- the frame's two edges, no text below a readable size, and the HUD, the
-- shelves, the stage and the controls never on top of one another.
local EDGE_TOL = 0.12
local function rect_of(m)
    if not (m and m.T and not m.REMOVED) then return nil end
    return {x = m.T.x, y = m.T.y, w = m.T.w, h = m.T.h}
end

function api.frame_check(name)
    if not (portrait_layout and portrait_frame) or portrait_layout() == 'classic' then return end
    local x0, W = portrait_frame()
    local blocks = {HUD = G.HUD, jokers = G.jokers, hand = G.hand, buttons = G.buttons, score_line = G.HUD_dock}
    for label, m in pairs(blocks) do
        local r = rect_of(m)
        if r then
            local dl, dr = r.x - x0, (r.x + r.w) - (x0 + W)
            api.check(math.abs(dl) <= EDGE_TOL and math.abs(dr) <= EDGE_TOL,
                string.format('%s: %s on the frame edges (left %+.2f, right %+.2f; w %.2f of %.2f)', name, label, dl, dr, r.w, W))
        end
    end
    local l = math.min(G.deck.T.x, G.consumeables.T.x)
    local r = math.max(G.deck.T.x + G.deck.T.w, G.consumeables.T.x + G.consumeables.T.w)
    api.check(math.abs(l - x0) <= EDGE_TOL and math.abs(r - (x0 + W)) <= EDGE_TOL,
        string.format('%s: deck/consumables shelf on the frame edges (left %+.2f, right %+.2f)', name, l - x0, r - x0 - W))
end

local function overlap(a, b)
    return a and b and a.x < b.x + b.w - 0.02 and b.x < a.x + a.w - 0.02 and a.y < b.y + b.h - 0.02 and b.y < a.y + a.h - 0.02
end

function api.overlap_check(name)
    local hud, dock = rect_of(G.HUD), rect_of(G.HUD_dock)
    local shelf = rect_of(G.consumeables)
    local deck = rect_of(G.deck)
    local jokers = rect_of(G.jokers)
    local pairs_to_check = {
        {'HUD', hud, 'consumables', shelf}, {'HUD', hud, 'deck', deck}, {'HUD', hud, 'jokers', jokers},
        {'consumables', shelf, 'jokers', jokers}, {'deck', deck, 'jokers', jokers},
        {'score line', dock, 'jokers', jokers},
    }
    for _, p in ipairs(pairs_to_check) do
        if p[2] and p[4] then
            api.check(not overlap(p[2], p[4]), string.format('%s: %s clear of %s', name, p[1], p[3]))
        end
    end
    local b = rect_of(G.buttons)
    if b and G.ROOM then
        -- The screen's bottom edge in room units (the room starts G.ROOM.T.y down).
        local bottom = love.graphics.getHeight() / unit_px() - G.ROOM.T.y
        api.check(b.y + b.h <= bottom + 0.05, string.format('%s: button bar on screen (bottom %.2f of %.2f)', name, b.y + b.h, bottom))
    end
end

function api.smallest_text(name, min_px)
    local px_per_unit = unit_px()
    local smallest, what = math.huge, nil
    local function walk(node)
        if node.states and node.states.visible == false then return end
        local cfg = node.config or {}
        if node.UIT == G.UIT.T and (cfg.scale or 0) > 0.01 then
            local s = cfg.text or (cfg.ref_table and tostring(cfg.ref_table[cfg.ref_value] or '')) or ''
            if s ~= '' and node.T.h * px_per_unit < smallest then smallest, what = node.T.h * px_per_unit, s end
        elseif cfg.object and cfg.object.is and cfg.object:is(DynaText) and cfg.object.T.h > 0.05 then
            if cfg.object.T.h * px_per_unit < smallest then smallest, what = cfg.object.T.h * px_per_unit, 'DynaText ' .. tostring(cfg.id) end
        end
        for _, c in pairs(node.children or {}) do if type(c) == 'table' and c.T then walk(c) end end
    end
    for _, box in ipairs({G.HUD, G.HUD_blind, G.buttons, G.HUD_dock}) do
        if box and box.UIRoot and not box.REMOVED and box.states.visible ~= false then walk(box.UIRoot) end
    end
    log(string.format('%s: smallest text %.1f px (%s)', name, smallest, tostring(what)))
    if min_px then
        api.check(smallest >= min_px, string.format('%s: smallest text %.1f px >= %d px', name, smallest, min_px))
    end
    return smallest
end

-- Elements left moving after their box was removed: a leak, and a crash as
-- soon as what the box hung off is gone too (a new run, the old hand).
function api.leak_count()
    local n, sample = 0, nil
    for _, m in pairs(G.MOVEABLES) do
        local box = m.UIBox
        local major = m.role and m.role.major
        -- A box's own elements outliving it, or anything still hung off a
        -- removed box or card area. (One vanilla box stays bound to a removed
        -- plain Moveable all game long; that one leads nowhere and is left.)
        local bad_major = major and major.REMOVED and major.is and (major:is(UIBox) or major:is(CardArea))
        if (box and box.REMOVED) or bad_major then
            n = n + 1
            if not sample then
                local kind = m.is and ((m:is(UIElement) and 'UIElement') or (m:is(DynaText) and 'DynaText') or (m:is(Sprite) and 'Sprite') or (m:is(UIBox) and 'UIBox') or (m:is(Card) and 'Card') or 'Moveable') or '?'
                local mk = major and major.is and ((major:is(UIBox) and 'UIBox') or (major:is(CardArea) and 'CardArea') or (major:is(Card) and 'Card') or (major:is(UIElement) and 'UIElement') or 'Moveable') or 'none'
                sample = string.format('%s %s, major %s%s', kind, tostring(m.config and (m.config.text or m.config.id or m.config.button)), mk, major and major.REMOVED and ' (removed)' or '')
            end
        end
    end
    return n, sample
end

function api.leak_check(name)
    local n, sample = api.leak_count()
    api.check(n == 0, string.format('%s: nothing left moving from removed boxes (%d%s)', name, n, sample and (', e.g. ' .. sample) or ''))
end

-- Ordered milestones, as in Hallway's walkthroughs: the report lists how far
-- a run got, so a failure reads as "reached shop, never left it".
report.milestones = {}
function api.milestone(name)
    report.milestones[#report.milestones + 1] = {name = name, t = now()}
    log('milestone', name)
end

-- Runs fn; an error is recorded as a failed check (with a screenshot) instead
-- of ending the scenario, so one broken screen does not hide the rest.
function api.step(name, fn)
    local co = coroutine.create(fn)
    while true do
        local ok, err = coroutine.resume(co)
        if not ok then
            api.check(false, 'step "' .. name .. '": ' .. tostring(err))
            pcall(api.shot, 'error_' .. name:gsub('%W+', '_'))
            return false
        end
        if coroutine.status(co) == 'dead' then return true end
        coroutine.yield()
    end
end

function api.set_language(key)
    if not G.LANGUAGES[key] then error('no language ' .. tostring(key), 2) end
    if G.SETTINGS.language == key then return end
    G.SETTINGS.language = key
    G:set_language()
    G:delete_run()
    G:init_item_prototypes()
    G:main_menu()
    api.wait(3)
end

-- Until every visible box has stopped moving for a few frames and input is
-- open: what "the screen has settled" means after a tap opens or closes a
-- menu, without guessing how long the slide takes.
function api.settle_ui(timeout)
    local still = 0
    api.frames(2)
    api.wait_until(function()
        local moving = false
        for _, box in pairs(G.I.UIBOX or {}) do
            if box.states and box.states.visible and box.VT and box.T
                and (math.abs(box.VT.x - box.T.x) > 0.01 or math.abs(box.VT.y - box.T.y) > 0.01) then
                moving = true
                break
            end
        end
        still = (moving or not input_ready()) and 0 or still + 1
        return still >= 4
    end, timeout or 8, 'screen settled')
end

-- The title screen with its menu built and settled (and rebuilt in the
-- language asked for, when BPM_HL_LANG is set): the menu box has stopped
-- sliding in and input is open, instead of a fixed pause.
function api.wait_title(timeout)
    api.wait_stage('MAIN_MENU', timeout or 60)
    -- A mod's first-launch intro (Cryptid's speech bubbles, then its gameset
    -- pick) stands between the splash and the title. Each screen is shot for
    -- review and answered with its own button, as a player would; a tap that
    -- does not move it on is reported, since a phone player would be stuck.
    local deadline = now() + (timeout or 60)
    local shot_for, taps = {}, 0
    local INTRO_BUTTONS = {'tut_next', 'cry_gameset_confirm', 'cry_mainline'}
    while not G.MAIN_MENU_UI and now() < deadline do
        local node, button
        for _, b in ipairs(INTRO_BUTTONS) do
            -- Cryptid's confirm only takes once a gameset is picked.
            if not ((b == 'cry_gameset_confirm' and not G.selectedGameset) or (b == 'cry_mainline' and G.selectedGameset)) then
                node = find_nodes({button = b})[1]
                if node then button = b break end
            end
        end
        if node then
            api.wait_real(1) -- it bobs, so it never looks settled
            if not shot_for[button] then
                shot_for[button] = true
                api.shot('mod_intro_' .. button)
                api.offscreen_check('mod_intro_' .. button)
            end
            local step = G.OVERLAY_TUTORIAL and G.OVERLAY_TUTORIAL.step
            api.tap_node(node)
            api.wait_real(1)
            taps = taps + 1
            if find_nodes({button = button})[1] == node and (G.OVERLAY_TUTORIAL and G.OVERLAY_TUTORIAL.step) == step then
                api.warn('mod intro: a tap on ' .. button .. ' did nothing; pressed it directly')
                G.FUNCS[node.config.button](node)
                api.wait_real(1)
            end
        else
            api.frames(1)
        end
    end
    if taps > 0 then log('mod intro clicked through in ' .. taps .. ' taps') end
    local still = 0
    api.wait_until(function()
        local ui = G.MAIN_MENU_UI
        if not (ui and not pending_menu_rebuild and (not LANG or lang_applied) and input_ready()) then
            still = 0
            return false
        end
        local moving = math.abs(ui.VT.y - ui.T.y) > 0.01 or math.abs(ui.VT.x - ui.T.x) > 0.01
        still = moving and 0 or still + 1
        return still >= 10
    end, timeout or 60, 'title menu')
end

-- What the profile screen's "Unlock all" does on its second tap, without the
-- screen: every card, blind and tag discovered, so collection and tooltip
-- layouts are tested with their real text instead of "?" placeholders.
function api.unlock_all()
    G.PROFILES[G.SETTINGS.profile].all_unlocked = true
    for _, pool in ipairs({G.P_CENTERS, G.P_BLINDS, G.P_TAGS}) do
        for _, v in pairs(pool) do
            if not v.demo and not v.wip then
                v.alerted, v.discovered, v.unlocked = true, true, true
            end
        end
    end
    set_profile_progress()
    set_discover_tallies()
    G:save_progress()
end

-- Strongest hand of up to five from G.hand, by the base score the game would
-- give it (hand level chips + scoring cards' chips, times mult). Ties go to
-- more cards, which also thins the hand for the next draw.
-- A plain number from the game's numbers, which Talisman turns into big-number
-- tables.
local function plain(x)
    if type(x) == 'table' then
        if to_number then x = to_number(x)
        elseif x.to_number then x = x:to_number()
        else return tonumber(tostring(x)) or 0 end
    end
    -- Amulet hands back LuaJIT FFI numbers.
    if type(x) == 'cdata' then return tonumber(x) or 0 end
    return x or 0
end
api.plain_number = plain

-- Runs fn to the end now. The scenario is a coroutine, and Talisman yields
-- from long calculations to spread them over frames: called straight from the
-- scenario, every hand it evaluated cost frames (best_hand took two minutes).
-- Its yields come back here instead and are resumed at once.
function api.run_sync(fn, ...)
    local co = coroutine.create(fn)
    local res = {coroutine.resume(co, ...)}
    while coroutine.status(co) ~= 'dead' do
        res = {coroutine.resume(co)}
    end
    if not res[1] then error(res[2], 2) end
    return unpack(res, 2)
end

function api.best_hand()
    local cards = G.hand.cards
    local best, best_score = nil, -1
    local sel = {}
    local function score()
        local text, _, _, scoring = api.run_sync(G.FUNCS.get_poker_hand_info, sel)
        local h = G.GAME.hands[text]
        if not h then return 0 end
        local chips = plain(h.chips)
        for _, c in ipairs(scoring) do chips = chips + plain(c:get_chip_bonus()) end
        return chips * plain(h.mult)
    end
    local function rec(start)
        if #sel > 0 then
            local s = score()
            if s > best_score or (s == best_score and #sel > #best) then
                best_score, best = s, {unpack(sel)}
            end
        end
        if #sel == 5 then return end
        for i = start, #cards do
            sel[#sel + 1] = cards[i]
            rec(i + 1)
            sel[#sel] = nil
        end
    end
    rec(1)
    return best or {}, best_score
end

-- Closes a popup the game put up on its own (an unlock, a discovery), the
-- way a player would: with its own button. Returns true when one was closed.
-- Its button is the bottom one of the overlay (Continue / Back), whatever the
-- popup calls it: unlocks and discoveries do not use exit_overlay_menu.
function api.dismiss_popups()
    if not G.OVERLAY_MENU or not input_ready() or G.STATE == G.STATES.GAME_OVER then return false end
    local best, best_y
    each_ui_element(function(node)
        if node.UIBox == G.OVERLAY_MENU and node.config and node.config.button and node_visible(node) then
            local _, y = node_rect_px(node)
            if not best_y or y > best_y then best, best_y = node, y end
        end
    end)
    if not best then return false end
    api.log('popup dismissed via', tostring(best.config.button))
    api.tap_node(best)
    api.settle_ui()
    return true
end

-- Taps Select on the blind on deck, again if the first tap landed while the
-- panel was still sliding in (a tap there misses, as it would on a phone).
-- Fails, as a hang would, when four taps never start the round.
function api.select_blind()
    api.wait_until(function() api.dismiss_popups() return api.find({button = 'select_blind'}) end, 20, 'blind choices')
    for _ = 1, 4 do
        api.wait_until(input_ready, 20, 'input ready')
        api.wait(1)
        api.tap_ui({button = 'select_blind'})
        local waited = 0
        while G.STATE ~= G.STATES.SELECTING_HAND and waited < 6 do api.wait(0.25) waited = waited + 0.25 end
        if G.STATE == G.STATES.SELECTING_HAND then return end
        -- The button is gone, so the tap took and the round is still starting.
        if not api.find({button = 'select_blind'}) then break end
        api.warn('Select did not take, tapping again')
    end
    api.wait_state('SELECTING_HAND', 10)
end

function api.back()
    if G.OVERLAY_MENU then
        G.FUNCS.exit_overlay_menu()
        api.settle_ui()
    end
end

function api.highlight(area, n)
    area = area or G.hand
    for i = 1, math.min(n or 1, #area.cards) do
        area:add_to_highlighted(area.cards[i])
    end
    api.frames(5)
end

function api.screen() return screen_info() end
function api.fail(msg) fail(msg) end
function api.done() finish() end

---------------------------------------------------------------------------
-- Driver
---------------------------------------------------------------------------

local scenario_co
local function load_scenario()
    if not SCENARIO then
        fail('BPM_HL_SCENARIO is not set')
        return nil
    end
    local f = io.open(SCENARIO, 'rb')
    if not f then
        fail('cannot open scenario ' .. SCENARIO)
        return nil
    end
    local src = f:read('*a'):gsub('^\239\187\191', '')
    f:close()
    local chunk, err = loadstring(src, '@' .. SCENARIO)
    if not chunk then
        fail('scenario does not compile: ' .. tostring(err))
        return nil
    end
    -- Helpers first, then the game's globals, so a scenario can say tap(...)
    -- and G.GAME.dollars alike.
    setfenv(chunk, setmetatable({}, {__index = function(_, k)
        local v = api[k]
        if v ~= nil then return v end
        return _G[k]
    end}))
    return coroutine.create(chunk)
end

local game_update = love.update
love.update = function(dt)
    -- While recording, the game steps a fixed 1/fps per frame however long the
    -- capture takes, so the clip keeps the game's pace (it caps movement at
    -- 1/20 s a frame, and a slow capture would play back in slow motion).
    dt = api.recording_step() or FRAME_STEP or dt
    stepped_time = stepped_time + dt
    game_update(dt)
    if finished then return end
    game_clock = game_clock + dt * ((G.SETTINGS and G.SETTINGS.paused) and 1 or (G.SPEEDFACTOR or 1))

    if LANG and G.SETTINGS and G.LANGUAGES and not lang_applied then
        lang_applied = true
        if G.SETTINGS.language ~= LANG then
            G.SETTINGS.language = LANG
            G:set_language()
            pending_menu_rebuild = true
        end
    end
    if pending_menu_rebuild and G.STAGE == G.STAGES.MAIN_MENU and G.MAIN_MENU_UI then
        pending_menu_rebuild = false
        G:delete_run()
        G:init_item_prototypes()
        G:main_menu()
    end

    -- The test profile is new every time, so the game would open every run with
    -- Jimbo's tutorial, which blocks the table. BPM_HL_TUTORIAL=1 keeps it.
    if G.SETTINGS and not G.SETTINGS.tutorial_complete and os.getenv('BPM_HL_TUTORIAL') ~= '1' then
        G.SETTINGS.tutorial_complete = true
    end

    if GAMESPEED and G.SETTINGS and G.SETTINGS.GAMESPEED ~= GAMESPEED then
        G.SETTINGS.GAMESPEED = GAMESPEED
    end

    if now() > TIMEOUT then
        fail(string.format('scenario timed out after %ds', TIMEOUT))
        return finish()
    end

    if not scenario_co then
        scenario_co = load_scenario()
        if not scenario_co then return finish() end
        log('screen', json(screen_info()):gsub('%s+', ' '))
    end

    local ok, err = coroutine.resume(scenario_co)
    if not ok then
        fail('scenario error: ' .. tostring(err) .. '\n' .. debug.traceback(scenario_co))
        return finish()
    end
    if coroutine.status(scenario_co) == 'dead' then finish() end
    api.record_frame()
end

-- Clips for the README: while a recording runs every frame is captured, and
-- the game is stepped 1/fps per frame (see love.update above), so frame n is
-- n/fps seconds of game time; tools/headless/make_gif.py plays them back so.
-- fps 20 matches the game's movement cap.
local rec = nil
function api.record_start(name, fps)
    rec = {name = name, every = 1 / (fps or 20), clock = 0, n = 0, pending = 0, lines = {}}
    log('recording', name)
end

function api.recording_step()
    return rec and rec.every or nil
end

function api.record_frame()
    if not rec then return end
    rec.clock = rec.clock + rec.every
    local t = rec.clock
    rec.n = rec.n + 1
    local r, file = rec, string.format('rec_%s_%04d.png', rec.name, rec.n)
    r.pending = r.pending + 1
    love.graphics.captureScreenshot(function(img)
        write_file(file, img:encode('png'):getString())
        r.lines[#r.lines + 1] = string.format('%s %.4f', file, t)
        r.pending = r.pending - 1
    end)
end

function api.record_stop()
    if not rec then return end
    local r = rec
    rec = nil
    repeat coroutine.yield() until r.pending == 0
    table.sort(r.lines)
    write_file('rec_' .. r.name .. '.txt', table.concat(r.lines, '\n') .. '\n')
    log('recorded', r.name, r.n, 'frames')
end
