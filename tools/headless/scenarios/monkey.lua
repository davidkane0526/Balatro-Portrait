-- Random play: taps on whatever can be tapped, swipes, the back key, the app sent
-- away, settings changed mid-run, for BPM_HL_MONKEY_S seconds of wall clock. A
-- crash fails the run through the harness; a game that stops taking input fails
-- here. The seed is logged, and BPM_HL_MONKEY_SEED plays the same run again.

local LIMIT = tonumber(os.getenv('BPM_HL_MONKEY_S')) or 240
local seed = tonumber(os.getenv('BPM_HL_MONKEY_SEED')) or (os.time() + (love.graphics.getWidth() * 7919) % 100000)
math.randomseed(seed)
log('monkey seed', seed)

-- Things that would end the test rather than the game.
love.system.openURL = function() return true end
love.system.setClipboardText = function() end
G.FUNCS.quit = function() end
local SKIP = {
    quit = true, open_portrait_support = true, change_lang = true, reset_achievements = true,
    delete_profile = true, load_profile = true, change_screen_mode = true, wipe_on = true,
}

local function buttons()
    local found = {}
    local _, all = find({})
    for _, node in ipairs(all or {}) do
        local b = node.config and node.config.button
        if b and not SKIP[b] then found[#found + 1] = node end
    end
    return found
end

local function some_card()
    local pools = {G.hand, G.jokers, G.consumeables, G.shop_jokers, G.shop_booster, G.shop_vouchers, G.pack_cards}
    local area = pools[math.random(#pools)]
    if area and area.cards and #area.cards > 0 then return area.cards[math.random(#area.cards)] end
end

local function card_px(card)
    local s = G.TILESCALE * G.TILESIZE
    return (card.T.x + card.T.w / 2 + G.ROOM.T.x) * s, (card.T.y + card.T.h / 2 + G.ROOM.T.y) * s
end

local acts = {
    {12, 'button', function()
        local all = buttons()
        if #all > 0 then
            local node = all[math.random(#all)]
            log('monkey button', tostring(node.config.button))
            tap_node(node)
        end
    end},
    {10, 'card', function()
        local card = some_card()
        if card and not card.REMOVED then tap_node(card) end
    end},
    {4, 'swipe', function()
        local card = some_card()
        if card and not card.REMOVED then
            local x, y = card_px(card)
            local up = math.random() < 0.5
            swipe(x, y, x + math.random(-30, 30), y + (up and -170 or 170), 0.12)
        end
    end},
    {3, 'tap anywhere', function()
        local w, h = love.graphics.getDimensions()
        tap(math.random(0, w - 1), math.random(0, h - 1))
    end},
    {1, 'back key', function()
        love.keypressed('escape')
        love.keyreleased('escape')
    end},
    {1, 'app away', function()
        if love.visible then love.visible(false) end
        if love.focus then love.focus(false) end
        frames(2)
        if love.visible then love.visible(true) end
        if love.focus then love.focus(true) end
    end},
    {1, 'layout', function()
        G.FUNCS.change_portrait_layout({to_key = math.random(#PORTRAIT_LAYOUTS)})
    end},
    {1, 'swipe mode', function()
        local on = math.random() < 0.5
        G.SETTINGS.swipe_only_mode = on
        on_swipe_only_setting_changed(on)
    end},
    {1, 'main hand', function()
        G.FUNCS.change_play_main_hand({to_key = math.random(2)})
    end},
}
local total = 0
for _, a in ipairs(acts) do total = total + a[1] end

local function pick()
    local n = math.random(total)
    for _, a in ipairs(acts) do
        n = n - a[1]
        if n <= 0 then return a end
    end
    return acts[1]
end

wait_title(120)
milestone('title')
unlock_all()

local started = love.timer.getTime()
local stuck_since, last_mark = G.TIMERS.REAL, nil
local count = 0
local leaks = 0
while love.timer.getTime() - started < LIMIT do
    local a = pick()
    count = count + 1
    a[3]()
    wait(0.1 + math.random() * 0.3)

    -- What left a removed box's elements moving, as it happens.
    local n, sample = leak_count()
    if n > leaks then
        log(string.format('monkey leak %d -> %d after %s in state %s: %s', leaks, n, a[2], tostring(G.STATE), tostring(sample)))
    end
    leaks = n

    -- On the title with no menu open, start a run: the title itself has little to tap.
    if G.STAGE == G.STAGES.MAIN_MENU and not G.OVERLAY_MENU and not G.screenwipe and input_ready() and math.random() < 0.3 then
        G.FUNCS.start_run(nil, {stake = math.random(1, 3)})
        wait(1)
    end

    -- A locked controller that outlives every animation is a game that stopped.
    local mark = tostring(G.STATE) .. '|' .. tostring(G.STATE_COMPLETE) .. '|' .. tostring(G.CONTROLLER.locked)
    if mark ~= last_mark or not G.CONTROLLER.locked then
        stuck_since, last_mark = G.TIMERS.REAL, mark
    elseif G.TIMERS.REAL - stuck_since > 45 then
        local names = {}
        for k, v in pairs(G.CONTROLLER.locks) do if v then names[#names + 1] = k end end
        check(false, 'input locked for 45 s in state ' .. tostring(G.STATE) .. ' (' .. table.concat(names, ',') .. ')')
        shot('stuck')
        break
    end
end
log(string.format('monkey: %d actions, seed %d', count, seed))
check(true, 'played ' .. count .. ' actions')
done()
