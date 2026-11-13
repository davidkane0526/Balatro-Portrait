-- Clips for the README, not a test: each layout plays a hand by touch with a
-- few jokers on the shelf, then one hand is played with the swipe gesture and
-- the layout is switched live mid-hand. Recorded frames land in the run's
-- folder as rec_<clip>_NNNN.png; tools/headless/make_gif.py turns them into
-- GIFs. Run it at the game's normal pace:
--
--   python tools/headless/run.py --scenario showcase --device phone --gamespeed 2

local SEED = os.getenv('BPM_HL_SEED') or 'BPMSHOW1'
local JOKERS = {'j_joker', 'j_jolly', 'j_greedy_joker', 'j_blue_joker'}

local function settle(extra)
    wait_until(input_ready, 20, 'input ready')
    wait(extra or 0.8)
end

local function card_center(card)
    local s = G.TILESCALE * G.TILESIZE
    return (card.T.x + card.T.w / 2 + G.ROOM.T.x) * s, (card.T.y + card.T.h / 2 + G.ROOM.T.y) * s
end

local function new_hand(layout)
    G.SETTINGS.portrait_layout = layout
    G.FUNCS.start_run(nil, {stake = 1, seed = SEED})
    wait_state('BLIND_SELECT', 30)
    wait_until(function() dismiss_popups() return find({button = 'select_blind'}) end, 20, 'blind choices')
    for _, key in ipairs(JOKERS) do
        local card = create_card('Joker', G.jokers, nil, nil, nil, nil, key)
        card:add_to_deck()
        G.jokers:emplace(card)
    end
    ease_dollars(23)
    settle(1)
    select_blind()
    wait_state('SELECTING_HAND', 30)
    -- A target the hand cannot reach, so the clip ends on a fresh hand being
    -- dealt (and loops) instead of the round's end.
    G.GAME.blind.chips = 30000
    G.GAME.blind.chip_text = number_format(G.GAME.blind.chips)
    wait_until(function() return #G.hand.cards > 0 end, 15, 'cards in hand')
    settle(1.2)
end

local function pick(cards)
    G.hand:unhighlight_all()
    for _, c in ipairs(cards) do
        tap_node(c)
        wait(0.45)
    end
    wait(0.6)
end

local function scored(before)
    wait_until(function() return G.GAME.current_round.hands_left < before end, 10, 'hand played')
    wait_until(function()
        return G.STATE == G.STATES.SELECTING_HAND and G.STATE_COMPLETE and #G.hand.cards >= G.hand.config.card_limit
    end, 40, 'hand scored and dealt again')
    settle(0.6)
end

for i, name in ipairs(PORTRAIT_LAYOUT_NAMES) do
    step('clip ' .. name, function()
        new_hand(i)
        local clip = PORTRAIT_LAYOUTS[i]
        record_start(clip, 20)
        wait(0.8)
        pick(best_hand())
        local before = G.GAME.current_round.hands_left
        tap_ui({id = 'play_button'})
        scored(before)
        record_stop()
        milestone('recorded ' .. clip)
    end)
end

local function set_swipe(on)
    G.SETTINGS.swipe_only_mode = on
    on_swipe_only_setting_changed(on)
end

local function flick(dy)
    local x, y = card_center(G.hand.highlighted[1])
    swipe(x, y, x, y + dy, 0.25)
end

-- Swipe Only in the three styles: play by flicking up, discard by flicking down.
step('clip swipe', function()
    set_swipe(true)
    new_hand(2)
    record_start('swipe', 20)
    wait(0.8)
    pick(best_hand())
    local before = G.GAME.current_round.hands_left
    flick(-170)
    scored(before)

    G.FUNCS.change_portrait_layout({to_key = 3})
    wait(0.6 * (G.SPEEDFACTOR or 1))
    local cards = {unpack(G.hand.cards)}
    table.sort(cards, function(a, b) return a:get_chip_bonus() < b:get_chip_bonus() end)
    pick({cards[1], cards[2], cards[3]})
    local discards = G.GAME.current_round.discards_left
    flick(160)
    wait_until(function() return G.GAME.current_round.discards_left < discards end, 10, 'discarded')
    wait_until(function() return G.STATE == G.STATES.SELECTING_HAND and G.STATE_COMPLETE end, 20, 'dealt again')
    settle(0.6)

    G.FUNCS.change_portrait_layout({to_key = 1})
    wait(0.6 * (G.SPEEDFACTOR or 1))
    pick(best_hand())
    before = G.GAME.current_round.hands_left
    flick(-170)
    wait_until(function() return G.GAME.current_round.hands_left < before end, 10, 'hand played')
    wait(1.6 * (G.SPEEDFACTOR or 1))
    record_stop()
    set_swipe(false)
    milestone('recorded swipe')
end)

-- Layouts switched mid-hand, then Swipe Only turned on and off.
step('clip switch', function()
    new_hand(1)
    record_start('switch', 20)
    wait(1)
    -- wait() counts game time, which runs at the game speed; each state is
    -- held for 1.6 s as seen.
    local hold = 1.6 * (G.SPEEDFACTOR or 1)
    for _, to in ipairs({2, 3, 1, 2}) do
        G.FUNCS.change_portrait_layout({to_key = to})
        wait(hold)
    end
    set_swipe(true)
    wait(hold)
    set_swipe(false)
    wait(hold)
    record_stop()
    milestone('recorded switch')
end)
