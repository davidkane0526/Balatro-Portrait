-- The three layout styles (Options > Settings > Game > Layout) side by side:
-- for each, a seeded run through blind select, the dealt hand, two cards
-- selected, the hand scoring, Cash Out and the shop, with the HUD and the
-- bar's buttons checked on screen and pressed. Then the style is switched
-- live in the shop, at blind select and mid-hand, the way the option does it.

local SEED = os.getenv('BPM_HL_SEED') or 'BPMTEST1'

local function settle(extra)
    wait_until(input_ready, 20, 'input ready')
    wait(extra or 0.8)
end

local function state_is(...)
    for _, s in ipairs({...}) do
        if G.STATE == G.STATES[s] then return true end
    end
    return false
end

-- Every HUD counter on screen, the shelves below the HUD and above the hand.
local HUD_IDS = {'chip_UI_count', 'hand_chips', 'hand_mult', 'dollar_text_UI', 'hand_UI_count',
    'discard_UI_count', 'ante_UI_count', 'round_UI_count', 'run_info_button', 'HUD_blind_count'}
local function check_hud(name)
    for _, id in ipairs(HUD_IDS) do check_on_screen({id = id}, name .. ': ' .. id) end
    local hud_bottom = G.HUD.T.y + G.HUD.T.h
    check(G.consumeables.T.y >= hud_bottom - 0.05, name .. ': card shelf starts below the HUD')
    check(G.jokers.T.y + G.jokers.T.h <= G.play.T.y + 0.05, string.format('%s: play area below the jokers (jokers end %.2f, play starts %.2f, HUD %.2f tall)',
        name, G.jokers.T.y + G.jokers.T.h, G.play.T.y, G.HUD.T.h))
    -- The play area reaches into the resting hand's space in every style
    -- (the hand lifts while you pick): a note, not a failure.
    if G.play.T.y + G.play.T.h > G.hand.T.y + 0.05 then warn(name .. ': play area overlaps the resting hand') end
end

local MIN_TEXT_PX = tonumber(os.getenv('BPM_HL_MIN_TEXT_PX')) or 9
local function check_frame(name)
    frame_check(name)
    overlap_check(name)
end
-- Cards (where they are drawn) against a box. With a name it is a check;
-- without one it returns a description of the worst overlap, or nil.
function cards_clear_of(name, list, what, box)
    if not (box and box.T and box.states and box.states.visible ~= false) then
        if name then check(true, name .. ' clear of the ' .. what .. ' (not shown)') end
        return nil
    end
    local b = box.VT or box.T
    local worst, msg = 0.02, nil
    for _, c in ipairs(list) do
        local r = c.VT or c.T
        local dy = math.min(r.y + r.h, b.y + b.h) - math.max(r.y, b.y)
        local dx = math.min(r.x + r.w, b.x + b.w) - math.max(r.x, b.x)
        if dx > 0.02 and dy > worst then
            worst = dy
            msg = string.format('a card overlaps it by %.2f (card %.2f..%.2f, %s %.2f..%.2f)',
                dy, r.y, r.y + r.h, what, b.y, b.y + b.h)
        end
    end
    if name then check(not msg, name .. ' clear of the ' .. what .. (msg and (': ' .. msg) or '')) end
    return msg
end

local function smallest(name)
    smallest_text(name, portrait_layout() ~= 'classic' and MIN_TEXT_PX or nil)
end

local function wait_shop()
    wait_until(function()
        return state_is('SHOP') and find({id = 'next_round_button'}) and G.shop_jokers and #G.shop_jokers.cards > 0
            and G.shop_jokers.cards[1].states.visible ~= false
    end, 30, 'shop stocked')
    settle(1)
end

wait_title()

-- The styles are portrait layouts; a landscape window keeps the vanilla bar.
if not G.F_PORTRAIT then
    log('landscape window: layout styles do not apply, nothing to check')
    return
end

for i, name in ipairs(PORTRAIT_LAYOUT_NAMES) do
    local tag = name:lower():gsub('%W', '')
    step('layout ' .. name, function()
        G.SETTINGS.portrait_layout = i
        G.FUNCS.start_run(nil, {stake = 1, seed = SEED})
        wait_state('BLIND_SELECT', 30)
        leak_check(name .. ' new run')

        -- An unlock popup (mods unlock decks on the way) is closed while waiting.
        wait_until(function() dismiss_popups() return find({button = 'select_blind'}) end, 20, 'blind choices')
        settle(1)
        screen_check(tag .. '_blind')
        select_blind()

        wait_state('SELECTING_HAND', 30)
        wait_until(function() return #G.hand.cards > 0 end, 15, 'cards in hand')
        settle(1)
        check(portrait_layout() == PORTRAIT_LAYOUTS[i], name .. ': layout setting is active')
        check_on_screen({id = 'play_button'}, name .. ': Play button')
        check_on_screen({id = 'discard_button'}, name .. ': Discard button')
        for _, card in ipairs(G.hand.cards) do
            local ok, where = on_screen(card)
            if not ok then check(false, name .. ': hand card on screen ' .. where) end
        end
        check_hud(name)
        check_frame(name)
        smallest(name)
        screen_check(tag .. '_hand')

        local cards = best_hand()
        G.hand:unhighlight_all()
        for k = 1, math.min(2, #cards) do tap_node(cards[k]) wait(0.12) end
        wait(0.6)
        screen_check(tag .. '_selected')
        cards_clear_of(name .. ': 2 raised cards', {cards[1], cards[2]}, 'score line', G.HUD_dock)

        if PORTRAIT_LAYOUTS[i] == 'one_thumb' then
            check_on_screen({id = 'thumb_menu_button'}, name .. ': menu button')
            check_on_screen({id = 'thumb_dock'}, name .. ': score line')
            tap_ui({id = 'thumb_menu_button'})
            wait(1)
            check(G.OVERLAY_MENU ~= nil, name .. ': the menu button opens Options')
            screen_check(tag .. '_menu')
            back()
            settle()
        elseif PORTRAIT_LAYOUTS[i] == 'focus' then
            local sort = find({id = 'focus_sort_button'})
            check(sort ~= nil, name .. ': sort toggle exists')
            if sort then
                tap_node(sort)
                wait(0.8)
                tap_node(find({id = 'focus_sort_button'}))
                wait(0.8)
                check(PORTRAIT_SORT_STATE.next == 'suit' or PORTRAIT_SORT_STATE.next == 'rank', name .. ': sort toggle cycles')
            end
            screen_check(tag .. '_sorted')
        end

        -- One point short of the blind, so this hand wins the round and the
        -- round's end, Cash Out and the shop come up in this style too.
        local before = G.GAME.current_round.hands_left
        G.GAME.chips = G.GAME.blind.chips - 1
        G.hand:unhighlight_all()
        for _, c in ipairs(cards) do tap_node(c) wait(0.12) end
        wait(0.4)
        cards_clear_of(name .. ': ' .. #cards .. ' raised cards', cards, 'score line', G.HUD_dock)
        tap_ui({id = 'play_button'})
        wait_until(function() return G.GAME.current_round.hands_left < before end, 10, 'Play button plays')
        check(true, name .. ': Play button plays the hand')
        -- Where the played cards come to rest, while they score: in flight
        -- from the hand they cross the score line, once landed they must not.
        local landed, worst = false, nil
        for _ = 1, 80 do
            -- Scoring cards bob as they score, so "landed" allows a little.
            local settled = #G.play.cards > 0
            for _, c in ipairs(G.play.cards) do
                if math.abs(c.VT.y - c.T.y) > 0.1 then settled = false end
            end
            if settled then
                landed = true
                worst = cards_clear_of(nil, G.play.cards, 'score line', G.HUD_dock) or worst
            end
            wait(0.05)
            if #G.play.cards == 0 and landed then break end
        end
        check(landed, name .. ': played cards land in the play area')
        check(not worst, name .. ': played cards clear of the score line' .. (worst and (' (' .. worst .. ')') or ''))
        wait(0.3)
        shot(tag .. '_scoring')

        wait_state('ROUND_EVAL', 40)
        wait_until(function() return find({button = 'cash_out'}) end, 30, 'cash out button')
        settle(1)
        check_on_screen({button = 'cash_out'}, name .. ': Cash Out')
        screen_check(tag .. '_round_eval')
        tap_ui({button = 'cash_out'})
        wait_shop()
        check_on_screen({id = 'next_round_button'}, name .. ': Next Round')
        screen_check(tag .. '_shop')
    end)
end

-- Live switch: the HUD, blind panel and bar are rebuilt without leaving the
-- run, in the shop (shop sign), at blind select (blind prompt) and mid-hand.
local function switch_all(where, verify)
    for i, name in ipairs(PORTRAIT_LAYOUT_NAMES) do
        G.FUNCS.change_portrait_layout({to_key = i})
        wait(0.8)
        -- The HUD and the panels ease into place; measure them at rest.
        settle_ui()
        check(portrait_layout() == PORTRAIT_LAYOUTS[i], 'live switch to ' .. name .. ' (' .. where .. ')')
        if verify then verify(name) end
        screen_check('live_' .. where .. '_' .. name:lower():gsub('%W', ''))
    end
end

step('live switch', function()
    if not state_is('SHOP') then return end
    switch_all('shop', function(name) check_on_screen({id = 'next_round_button'}, name .. ': Next Round after switch') end)
    tap_ui({id = 'next_round_button'})
    wait_state('BLIND_SELECT', 30)
    -- An unlock popup (mods unlock decks on the way) is closed while waiting.
        wait_until(function() dismiss_popups() return find({button = 'select_blind'}) end, 20, 'blind choices')
    settle(1)
    switch_all('blind', function(name) check_on_screen({button = 'select_blind'}, name .. ': Select after switch') end)
    tap_ui({button = 'select_blind'})
    wait_state('SELECTING_HAND', 30)
    wait_until(function() return #G.hand.cards > 0 end, 15, 'cards in hand')
    settle(1)
    switch_all('hand', function(name)
        check(find({id = 'play_button'}) ~= nil, name .. ': bar rebuilt')
        check_hud(name)
        check_frame(name)
    end)
    -- The rebuilt HUD still scores: play a hand in the last style.
    local before = G.GAME.current_round.hands_left
    for _, c in ipairs(best_hand()) do tap_node(c) wait(0.12) end
    wait(0.4)
    tap_ui({id = 'play_button'})
    wait_until(function() return G.GAME.current_round.hands_left < before end, 10, 'play after switch')
    wait_until(function() return state_is('SELECTING_HAND', 'ROUND_EVAL', 'GAME_OVER') and G.STATE_COMPLETE end, 40, 'hand scored after switch')
    check(true, 'a hand scores after the live switches')
    G.FUNCS.change_portrait_layout({to_key = 1})
end)
