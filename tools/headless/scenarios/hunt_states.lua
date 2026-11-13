-- Language plays no part here: every state of a run, with what a player can do at
-- any moment. The layout and the other seats of the Game tab changed on the spot,
-- Options opened and closed, the back key, the app sent away and brought back,
-- then the run left and continued from its save.

local SEED = os.getenv('BPM_HL_SEED') or 'BPMTEST1'

local function settle(extra)
    wait_until(input_ready, 20, 'input ready')
    wait(extra or 0.8)
end

local PACK_STATES = {'TAROT_PACK', 'PLANET_PACK', 'SPECTRAL_PACK', 'STANDARD_PACK', 'BUFFOON_PACK', 'SMODS_BOOSTER_OPENED'}
local function state_is(...)
    for _, s in ipairs({...}) do
        if G.STATE == G.STATES[s] then return true end
    end
    return false
end

-- What has to stay reachable in each state, whatever was changed.
local function key_check(tag, what)
    for _, q in ipairs(what) do
        local node = find(q)
        check(node ~= nil, tag .. ': ' .. tostring(q.button or q.id) .. ' still there')
        if node then
            local ok, where = on_screen(node)
            check(ok, tag .. ': ' .. tostring(q.button or q.id) .. ' on screen ' .. where)
        end
    end
end

local function hand_on_screen(tag)
    if not (G.hand and G.hand.cards) then return end
    for i, card in ipairs(G.hand.cards) do
        local ok, where = on_screen(card)
        if not ok and G.STATE == G.STATES.SELECTING_HAND then check(false, tag .. ': hand card ' .. i .. ' on screen ' .. where) end
    end
end

local function shake(tag, what)
    local start_layout = G.SETTINGS.portrait_layout
    for layout = 1, #PORTRAIT_LAYOUTS do
        step(tag .. ' layout ' .. layout, function()
            G.FUNCS.change_portrait_layout({to_key = layout})
            wait(3)
            key_check(tag .. ' layout ' .. layout, what)
            hand_on_screen(tag .. ' layout ' .. layout)
            frame_check(tag .. ' layout ' .. layout)
            overlap_check(tag .. ' layout ' .. layout)
            screen_check(tag .. '_layout' .. layout)
        end)
        for _, on in ipairs({true, false}) do
            step(tag .. ' swipe ' .. tostring(on), function()
                G.SETTINGS.swipe_only_mode = on
                on_swipe_only_setting_changed(on)
                wait(3)
                key_check(tag .. ' swipe ' .. tostring(on), what)
                screen_check(tag .. '_swipe')
            end)
        end
        for hand = 1, 2 do
            step(tag .. ' main hand ' .. hand, function()
                G.FUNCS.change_play_main_hand({to_key = hand})
                wait(3)
                key_check(tag .. ' main hand ' .. hand, what)
                screen_check(tag .. '_hand' .. hand)
            end)
        end
    end
    for pos = 1, 3 do
        step(tag .. ' run info position ' .. pos, function()
            G.FUNCS.change_runinfo_options_position({to_key = pos})
            wait(0.5)
            screen_check(tag .. '_runinfo' .. pos)
        end)
    end
    G.FUNCS.change_runinfo_options_position({to_key = 1})
    G.FUNCS.change_portrait_layout({to_key = start_layout})
    wait(0.6)

    step(tag .. ' options', function()
        G.FUNCS.options()
        wait(1)
        G.FUNCS.exit_overlay_menu()
        wait(1)
        key_check(tag .. ' after Options', what)
    end)
    step(tag .. ' back key', function()
        love.keypressed('escape')
        love.keyreleased('escape')
        wait(0.6)
        if G.OVERLAY_MENU then
            screen_check(tag .. '_back_key')
            love.keypressed('escape')
            love.keyreleased('escape')
            wait(0.6)
            if G.OVERLAY_MENU then G.FUNCS.exit_overlay_menu() wait(1) end
        end
        key_check(tag .. ' after the back key', what)
    end)
    step(tag .. ' app away', function()
        if love.focus then love.focus(false) end
        if love.visible then love.visible(false) end
        wait(0.3)
        if love.visible then love.visible(true) end
        if love.focus then love.focus(true) end
        local w, h = love.graphics.getDimensions()
        if love.resize then love.resize(w, h) end
        wait(0.8)
        key_check(tag .. ' back in the app', what)
        hand_on_screen(tag .. ' back in the app')
        screen_check(tag .. '_returned')
    end)
end

local function continue_run(tag, what)
    step(tag .. ' save and continue', function()
        wait(3)
        local ante, jokers = G.GAME.round_resets.ante, #G.jokers.cards
        G.FUNCS.go_to_menu()
        wait_title()
        tap_ui({id = 'main_menu_play'})
        wait(1.2)
        tap_ui({button = 'start_setup_run'})
        wait_until(function()
            dismiss_popups()
            return G.STAGE == G.STAGES.RUN and not G.OVERLAY_MENU and G.STATE_COMPLETE
        end, 40, 'continued run')
        settle(1.5)
        check(G.GAME.round_resets.ante == ante, tag .. ': continued on the same ante')
        check(#G.jokers.cards == jokers, tag .. ': continued with its jokers')
        screen_check(tag .. '_continued')
    end)
end

wait_title(120)
milestone('title')
unlock_all()
if not G.F_PORTRAIT then done() end

local layout = tonumber(os.getenv('BPM_HL_LAYOUT')) or 1
G.SETTINGS.portrait_layout = layout
G.FUNCS.start_run(nil, {stake = 1, seed = SEED})
wait_state('BLIND_SELECT', 30)
wait_until(function() dismiss_popups() return find({button = 'select_blind'}) end, 20, 'blind choices')
settle(1.5)
milestone('blind select')
shake('blind_select', {{button = 'select_blind'}})
continue_run('blind_select', {{button = 'select_blind'}})

select_blind()
wait_state('SELECTING_HAND', 30)
wait_until(function() return #G.hand.cards > 0 end, 15, 'cards in hand')
settle(1)
milestone('hand')
G.hand:unhighlight_all()
tap_node(G.hand.cards[1])
tap_node(G.hand.cards[2])
wait(0.4)
shake('hand', {})
G.hand:unhighlight_all()

G.GAME.dollars = to_big and to_big(40) or 40
G.GAME.chips = G.GAME.blind.chips - 1
local hands = G.GAME.current_round.hands_left
for _, c in ipairs(best_hand()) do tap_node(c) wait(0.12) end
G.FUNCS.play_cards_from_highlighted()
wait_until(function() return G.GAME.current_round.hands_left < hands end, 10, 'hand played')
wait_state('ROUND_EVAL', 40)
wait_until(function() return find({button = 'cash_out'}) end, 30, 'cash out button')
settle(1.5)
milestone('round eval')
shake('round_eval', {{button = 'cash_out'}})

tap_ui({button = 'cash_out'})
wait_until(function()
    return G.STATE == G.STATES.SHOP and find({id = 'next_round_button'}) and G.shop_jokers and #G.shop_jokers.cards > 0
end, 30, 'shop stocked')
settle(1.5)
milestone('shop')
shake('shop', {{id = 'next_round_button'}})
continue_run('shop', {{id = 'next_round_button'}})

local pack = G.shop_booster.cards[1]
if pack then
    tap_node(pack)
    wait(0.5)
    pack.cost = 0
    G.GAME.dollars = to_big and to_big(40) or 40
    G.FUNCS.use_card({config = {ref_table = pack}})
    wait_until(function() return state_is(unpack(PACK_STATES)) and G.pack_cards and #G.pack_cards.cards > 0 end, 20, 'pack opened')
    settle(1.5)
    milestone('pack')
    shake('pack', {})
    G.FUNCS.skip_booster()
    wait_until(function() return state_is('SHOP') end, 20, 'back in the shop')
    settle(1)
end

tap_ui({id = 'next_round_button'})
wait_state('BLIND_SELECT', 30)
settle(1)

done()
