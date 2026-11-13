-- Swipe Only mode (Options > Settings > Game) in each layout style: no Play or
-- Discard button, what each bar keeps still on screen and working, a hand
-- discarded and played by swipe, then Cash Out, the shop and blind select in
-- the hand's lower place. Finally the mode is switched off and on live.

local SEED = os.getenv('BPM_HL_SEED') or 'BPMTEST1'

local function settle(extra)
    wait_until(input_ready, 20, 'input ready')
    wait(extra or 0.8)
end

local function card_center(card)
    local s = G.TILESCALE * G.TILESIZE
    return (card.T.x + card.T.w / 2 + G.ROOM.T.x) * s, (card.T.y + card.T.h / 2 + G.ROOM.T.y) * s
end

local function set_swipe(on)
    G.SETTINGS.swipe_only_mode = on
    on_swipe_only_setting_changed(on)
end

local function bar_check(name)
    check(find({id = 'play_button'}) == nil, name .. ': no Play button')
    check(find({id = 'discard_button'}) == nil, name .. ': no Discard button')
    for _, card in ipairs(G.hand.cards) do
        local ok, where = on_screen(card)
        if not ok then check(false, name .. ': hand card on screen ' .. where) end
    end
    frame_check(name)
    overlap_check(name)
end

local function pick(cards)
    G.hand:unhighlight_all()
    for _, c in ipairs(cards) do tap_node(c) wait(0.12) end
    wait(0.5)
end

local function cue_nodes()
    local found = {}
    local function walk(node)
        if node.config and node.config.hint then found[#found + 1] = node end
        for _, child in pairs(node.children or {}) do walk(child) end
    end
    walk(G.buttons.UIRoot)
    return found
end

-- How far a card's drawn corners reach below the top of a cue, over its width.
local function cue_overlap(cue)
    local worst = -99
    for _, card in ipairs(G.hand.cards) do
        local w, h = card.VT.w * card.VT.scale / 2, card.VT.h * card.VT.scale / 2
        local cx, cy, r = card.VT.x + card.VT.w / 2, card.VT.y + card.VT.h / 2, card.VT.r or 0
        for _, p in ipairs({{-w, h}, {w, h}}) do
            local x = cx + p[1] * math.cos(r) - p[2] * math.sin(r)
            local y = cy + p[1] * math.sin(r) + p[2] * math.cos(r)
            if x >= cue.T.x and x <= cue.T.x + cue.T.w then worst = math.max(worst, y - cue.T.y) end
        end
    end
    return worst
end

-- The cue shows with cards selected, and the corners left down are the ones in
-- its way: each end of the hand, then the middle.
local function cue_check(name, tag)
    local n = #G.hand.cards
    local picks = {left = {1, 2}, right = {n - 1, n}, middle = {math.floor(n / 2), math.floor(n / 2) + 1}}
    for _, where in ipairs({'left', 'middle', 'right'}) do
        local cards = {}
        for _, k in ipairs(picks[where]) do cards[#cards + 1] = G.hand.cards[k] end
        pick(cards)
        wait(0.5)
        local cues = cue_nodes()
        check(#cues == 2, name .. ': both cues are there')
        for _, cue in ipairs(cues) do
            local over = cue_overlap(cue)
            check(over <= 0, string.format('%s: hand clear of the %s cue, %s picked (%.2f)', name, cue.config.hint, where, over))
        end
        shot(tag .. '_swipe_cue_' .. where)
    end
    G.hand:unhighlight_all()
    wait(0.3)
end

wait_title()

if not G.F_PORTRAIT then
    log('landscape window: Swipe Only does not apply, nothing to check')
    return
end

for i, name in ipairs(PORTRAIT_LAYOUT_NAMES) do
    local tag = name:lower():gsub('%W', '')
    step('swipe ' .. name, function()
        G.SETTINGS.portrait_layout = i
        set_swipe(true)
        G.FUNCS.start_run(nil, {stake = 1, seed = SEED})
        wait_state('BLIND_SELECT', 30)
        wait_until(function() dismiss_popups() return find({button = 'select_blind'}) end, 20, 'blind choices')
        settle(1)
        -- Measured where it stops, not on its way up from the bottom.
        wait_until(function() return math.abs(G.blind_select.VT.y - G.blind_select.T.y) < 0.05 end, 10, 'blind panel in place')
        check_on_screen({button = 'select_blind'}, name .. ': Select')
        screen_check(tag .. '_swipe_blind')
        select_blind()

        wait_state('SELECTING_HAND', 30)
        wait_until(function() return #G.hand.cards > 0 end, 15, 'cards in hand')
        settle(1)
        bar_check(name)
        screen_check(tag .. '_swipe_hand')
        cue_check(name, tag)

        if PORTRAIT_LAYOUTS[i] == 'one_thumb' then
            check_on_screen({id = 'thumb_menu_button'}, name .. ': Options stays in the bar')
            tap_ui({id = 'thumb_menu_button'})
            wait(1)
            check(G.OVERLAY_MENU ~= nil, name .. ': the menu button opens Options')
            back()
            settle()
        elseif PORTRAIT_LAYOUTS[i] == 'focus' then
            local before = PORTRAIT_SORT_STATE.next
            tap_ui({id = 'focus_sort_button'})
            wait(0.8)
            check(PORTRAIT_SORT_STATE.next ~= before, name .. ': sort toggle cycles')
        end

        local discards = G.GAME.current_round.discards_left
        local sorted = {unpack(G.hand.cards)}
        table.sort(sorted, function(a, b) return a:get_chip_bonus() < b:get_chip_bonus() end)
        pick({sorted[1], sorted[2]})
        check(#G.hand.highlighted == 2, name .. ': two cards selected')
        wait(0.5)
        screen_check(tag .. '_swipe_selected')
        if G.HUD_dock then
            local c = G.hand.highlighted[1]
            local grown = c.VT.h * (c.VT.scale / 0.95 - 1) / 2
            local bottom = G.HUD_dock.T.y + G.HUD_dock.T.h
            check(c.VT.y - grown >= bottom, string.format('%s: raised card clear of the score line (card top %.2f, line ends %.2f)', name, c.VT.y - grown, bottom))
        end
        local x, y = card_center(G.hand.highlighted[1])
        swipe(x, y, x, y + 160, 0.15)
        wait_until(function() return G.GAME.current_round.discards_left < discards end, 10, 'swipe down discards')
        check(true, name .. ': swipe down discards')
        wait_until(function() return G.STATE == G.STATES.SELECTING_HAND and G.STATE_COMPLETE end, 20, 'hand dealt again')
        settle(1)

        -- One point short of the blind, so the hand wins the round.
        local hands = G.GAME.current_round.hands_left
        G.GAME.chips = G.GAME.blind.chips - 1
        pick(best_hand())
        x, y = card_center(G.hand.highlighted[1])
        swipe(x, y, x, y - 170, 0.15)
        wait_until(function() return G.GAME.current_round.hands_left < hands end, 10, 'swipe up plays')
        check(true, name .. ': swipe up plays')
        wait(0.6)
        shot(tag .. '_swipe_scoring')

        wait_state('ROUND_EVAL', 40)
        wait_until(function() return find({button = 'cash_out'}) end, 30, 'cash out button')
        settle(1)
        check_on_screen({button = 'cash_out'}, name .. ': Cash Out')
        screen_check(tag .. '_swipe_round_eval')
        tap_ui({button = 'cash_out'})
        wait_until(function()
            return G.STATE == G.STATES.SHOP and find({id = 'next_round_button'}) and G.shop_jokers and #G.shop_jokers.cards > 0
        end, 30, 'shop stocked')
        settle(1)
        check_on_screen({id = 'next_round_button'}, name .. ': Next Round')
        screen_check(tag .. '_swipe_shop')
        tap_ui({id = 'next_round_button'})

        wait_state('BLIND_SELECT', 30)
        wait_until(function() dismiss_popups() return find({button = 'select_blind'}) end, 20, 'blind choices')
        settle(1)
        select_blind()
        wait_state('SELECTING_HAND', 30)
        wait_until(function() return #G.hand.cards > 0 end, 15, 'cards in hand')
        settle(1)

        -- Live, mid-hand: the buttons come back, then go again.
        set_swipe(false)
        wait(1)
        check(find({id = 'play_button'}) ~= nil, name .. ': Play back when the mode is off')
        frame_check(name .. ' mode off')
        overlap_check(name .. ' mode off')
        set_swipe(true)
        wait(1)
        bar_check(name .. ' mode on again')
        set_swipe(false)
    end)
end
