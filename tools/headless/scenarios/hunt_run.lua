-- A run through what the other scenarios pass by, in each layout style: every boss
-- in the blind panel and the HUD, every poker hand's name, each boss's warning,
-- the round's end with every kind of row, every pack, the shop, Run Info and the
-- deck view, then losing and winning. Text out of place is noted by the audit
-- (tools/headless/audit.py).

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

local PACK_STATES = {'TAROT_PACK', 'PLANET_PACK', 'SPECTRAL_PACK', 'STANDARD_PACK', 'BUFFOON_PACK', 'SMODS_BOOSTER_OPENED'}

local function boss_keys()
    local keys = {}
    for key, blind in pairs(G.P_BLINDS) do
        if blind.boss then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

local function overlay_tabs(tag)
    settle_ui()
    shot(tag)
    hover_all(tag)
    local _, nodes = find({button = 'change_tab'})
    for i = 1, #(nodes or {}) do
        local _, now = find({button = 'change_tab'})
        if now and now[i] then
            tap_node(now[i])
            settle_ui()
            shot(tag .. '_tab' .. i)
            hover_all(tag .. '_tab' .. i)
        end
    end
    back()
end

local function win_round()
    G.GAME.chips = G.GAME.blind.chips - 1
    local hands = G.GAME.current_round.hands_left
    G.hand:unhighlight_all()
    for _, c in ipairs(best_hand()) do tap_node(c) wait(0.1) end
    G.FUNCS.play_cards_from_highlighted()
    wait_until(function() return G.GAME.current_round.hands_left < hands end, 10, 'hand played')
    wait_state('ROUND_EVAL', 40)
    wait_until(function() return find({button = 'cash_out'}) end, 30, 'cash out button')
    settle(1.5)
end

wait_title(120)
milestone('title')
unlock_all()
if not G.F_PORTRAIT then done() end

for i, name in ipairs(PORTRAIT_LAYOUT_NAMES) do
    local tag = PORTRAIT_LAYOUTS[i]
    step(name, function()
        G.SETTINGS.portrait_layout = i
        G.FORCE_TAG = 'tag_investment'
        G.FUNCS.start_run(nil, {stake = 1, seed = SEED})
        wait_state('BLIND_SELECT', 30)
        wait_until(function() dismiss_popups() return find({button = 'select_blind'}) end, 20, 'blind choices')
        settle(1.5)
        shot(tag .. '_blind_select')
        hover_all(tag .. '_blind_select')

        -- Every boss in the panel, through the game's own reroll.
        G.GAME.dollars = to_big and to_big(100000) or 100000
        for _, key in ipairs(boss_keys()) do
            G.FORCE_BOSS = key
            G.FUNCS.reroll_boss()
            wait_until(function() return not G.CONTROLLER.locks.boss_reroll end, 10, 'boss reroll')
            wait(0.5)
            text_audit(tag .. '_panel_' .. key)
        end
        G.FORCE_BOSS = nil
        shot(tag .. '_panel_last_boss')

        -- Skipping both small blinds leaves two tags for the round's end.
        for _ = 1, 2 do
            G.FUNCS.skip_blind(find({button = 'skip_blind'}) or {UIBox = G.blind_select_opts.small, config = {ref_table = {}}})
            wait(1.5)
            settle(0.5)
        end
        shot(tag .. '_skipped')
        hover_all(tag .. '_skipped')

        select_blind()
        wait_state('SELECTING_HAND', 30)
        wait_until(function() return #G.hand.cards > 0 end, 15, 'cards in hand')
        settle(1)
        shot(tag .. '_round')
        hover_all(tag .. '_round')

        -- Every boss in the HUD, with its warning.
        for _, key in ipairs(boss_keys()) do
            G.GAME.blind:set_blind(G.P_BLINDS[key], nil, true)
            frames(6)
            text_audit(tag .. '_hud_' .. key)
            G.GAME.blind:wiggle()
            G.GAME.blind:alert_debuff(true)
            wait(0.4)
            text_audit(tag .. '_warning_' .. key)
            -- One at a time here; in a game one shows at most every few seconds.
            for _, box in pairs(G.I.UIBOX) do
                if box.attention_text then box.states.visible = false end
            end
        end
        shot(tag .. '_hud_last_boss')

        -- Every hand's name where the hand shows, at the level that takes most room.
        for key in pairs(G.GAME.hands) do
            G.GAME.hands[key].visible = true
            G.GAME.hands[key].played = 3
            update_hand_text({immediate = true, nopulse = true, delay = 0},
                {handname = localize(key, 'poker_hands'), level = 100, mult = 99999, chips = 99999})
            frames(6)
            text_audit(tag .. '_hand_' .. key)
        end
        update_hand_text({immediate = true, nopulse = true, delay = 0}, {handname = '', level = '', mult = 0, chips = 0})

        G.FUNCS.run_info()
        overlay_tabs(tag .. '_run_info')
        G.FUNCS.deck_info()
        overlay_tabs(tag .. '_deck_info')
        G.FUNCS.options()
        overlay_tabs(tag .. '_options')

        -- The attention texts the game puts over the table.
        attention_text({text = localize('k_no_space_ex'), scale = 0.9, hold = 1, align = 'cm', major = G.play, offset = {x = 0, y = 0}})
        attention_text({text = localize('ph_boss_disabled'), scale = 0.9, hold = 1, align = 'cm', major = G.play, offset = {x = 0, y = 0}})
        attention_text({text = localize('ph_mr_bones'), scale = 0.9, hold = 1, align = 'cm', major = G.play, offset = {x = 0, y = 0}})
        wait(0.4)
        text_audit(tag .. '_attention')

        -- A round's end with one row of each kind.
        for _, key in ipairs({'j_golden', 'j_cloud_9', 'j_rocket', 'j_satellite', 'j_delayed_grat'}) do
            local card = Card(G.jokers.T.x, G.jokers.T.y, G.CARD_W, G.CARD_H, nil, G.P_CENTERS[key], {bypass_discovery_center = true, bypass_discovery_ui = true})
            card:add_to_deck()
            G.jokers:emplace(card)
        end
        G.GAME.modifiers.money_per_discard = 1
        G.GAME.dollars = to_big and to_big(100) or 100
        win_round()
        shot(tag .. '_round_eval')
        hover_all(tag .. '_round_eval')

        tap_ui({button = 'cash_out'})
        wait_until(function()
            return G.STATE == G.STATES.SHOP and find({id = 'next_round_button'}) and G.shop_jokers and #G.shop_jokers.cards > 0
        end, 30, 'shop stocked')
        settle(1.5)
        shot(tag .. '_shop')
        hover_all(tag .. '_shop')

        -- Every voucher and pack in the shop's own slots.
        for _, center in ipairs(G.P_CENTER_POOLS.Voucher) do
            local card = Card(G.shop_vouchers.T.x, G.shop_vouchers.T.y, G.CARD_W, G.CARD_H, nil, center, {bypass_discovery_center = true, bypass_discovery_ui = true})
            create_shop_card_ui(card, 'Voucher', G.shop_vouchers)
            G.shop_vouchers:emplace(card)
            frames(3)
            card:hover()
            frames(3)
            text_audit(tag .. '_voucher_' .. center.key)
            card:stop_hover()
            card:remove()
        end
        for _, kind in ipairs({'p_arcana_normal_1', 'p_arcana_mega_1', 'p_celestial_jumbo_1', 'p_spectral_normal_1',
                               'p_standard_mega_1', 'p_buffoon_jumbo_1'}) do
            local card = Card(G.shop_booster.T.x, G.shop_booster.T.y, G.CARD_W * 1.27, G.CARD_H * 1.27, G.P_CARDS.empty, G.P_CENTERS[kind], {bypass_discovery_center = true, bypass_discovery_ui = true})
            create_shop_card_ui(card, 'Booster', G.shop_booster)
            card.ability.booster_pos = 1
            G.shop_booster:emplace(card)
            frames(3)
            card:hover()
            frames(3)
            text_audit(tag .. '_pack_' .. kind)
            card:stop_hover()
            card.cost = 0
            G.FUNCS.use_card({config = {ref_table = card}})
            wait_until(function() return state_is(unpack(PACK_STATES)) and G.pack_cards and #G.pack_cards.cards > 0 end, 20, 'pack opened')
            settle(1.5)
            shot(tag .. '_open_' .. kind)
            hover_all(tag .. '_open_' .. kind)
            G.FUNCS.skip_booster()
            wait_until(function() return state_is('SHOP') end, 20, 'back in the shop')
            settle(1)
        end

        -- Losing, with a seed to show.
        G.STATE = G.STATES.GAME_OVER
        G.STATE_COMPLETE = false
        wait(1)
        wait_until(function() return G.OVERLAY_MENU end, 10, 'game over screen')
        wait(4)
        shot(tag .. '_game_over')
        hover_all(tag .. '_game_over')
        back()
        wait(0.5)
    end)
end

step('winning', function()
    G.SETTINGS.portrait_layout = 1
    G.FUNCS.start_run(nil, {stake = 1, seed = SEED})
    wait_state('BLIND_SELECT', 30)
    select_blind()
    wait_state('SELECTING_HAND', 30)
    settle(1)
    win_game()
    wait(1)
    wait_until(function() return G.OVERLAY_MENU end, 10, 'win screen')
    wait(4)
    shot('win')
    hover_all('win')
    back()
end)

done()
