-- Every layout style under what stretches a layout most: the longest numbers
-- the game prints (99,999,999,999 just under the e-notation switch, then
-- naneinf from an overflowed score), 12 jokers plus negatives over the slot
-- limit, 6 consumables, a 12-card hand, 8 tags, a boss with a long debuff,
-- ante 39 / round 999 / 99 hands and discards / $9,999,999,999. Each is checked
-- on screen, on its frame, clear of the others and readable, then a hand is
-- played with it all and the round's end and the shop are checked too.
-- Run it with --lang to try the longest labels (de, fr) and other fonts (zh_CN).

local SEED = os.getenv('BPM_HL_SEED') or 'BPMTEST1'
-- Counters shrink to stay in their tiles at these extremes; the layouts
-- scenario holds normal play to 9 px, this one only to legible.
local MIN_TEXT_PX = tonumber(os.getenv('BPM_HL_MIN_TEXT_PX')) or 7

local JOKERS = {'j_hanging_chad', 'j_mr_bones', 'j_ancient', 'j_blueprint', 'j_brainstorm', 'j_hologram',
    'j_invisible', 'j_perkeo', 'j_triboulet', 'j_yorick', 'j_caino', 'j_burnt'}
local CONSUMABLES = {'c_fool', 'c_black_hole', 'c_soul', 'c_wraith', 'c_ankh', 'c_pluto'}
local HUD_IDS = {'chip_UI_count', 'hand_chips', 'hand_mult', 'dollar_text_UI', 'hand_UI_count',
    'discard_UI_count', 'ante_UI_count', 'round_UI_count', 'run_info_button', 'HUD_blind_count'}

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

local function all_on_screen(area, label)
    local bad = 0
    for _, card in ipairs(area.cards) do
        local ok = on_screen(card)
        if not ok then bad = bad + 1 end
    end
    check(bad == 0, string.format('%s: all %d %s on screen (%d off)', label, #area.cards, area == G.hand and 'hand cards' or 'cards', bad))
end

local function measure(name, tag)
    for _, id in ipairs(HUD_IDS) do check_on_screen({id = id}, name .. ': ' .. id) end
    frame_check(name)
    overlap_check(name)
    smallest_text(name, portrait_layout() ~= 'classic' and MIN_TEXT_PX or nil)
    all_on_screen(G.jokers, name .. ' jokers')
    all_on_screen(G.consumeables, name .. ' consumables')
    all_on_screen(G.hand, name .. ' hand')
    local hud = G.HUD.T
    for k, t in ipairs(G.HUD_tags or {}) do
        local ok = on_screen(t)
        check(ok, string.format('%s: tag %d on screen', name, k))
        check(t.T.y >= hud.y + hud.h - 0.05, string.format('%s: tag %d below the HUD', name, k))
    end
    shot(tag)
    layout_report(tag)
    check(offscreen_check(tag) == 0, name .. ': no text or button cut off at the screen edge (' .. tag .. ')')
end

local function load_up()
    -- Over the limit on purpose: negatives add slots of their own.
    G.jokers.config.card_limit = #JOKERS
    for k, key in ipairs(JOKERS) do
        local card = create_card('Joker', G.jokers, nil, nil, nil, nil, key)
        if k % 4 == 0 then card:set_edition({negative = true}, true, true) end
        card:add_to_deck()
        G.jokers:emplace(card)
    end
    G.consumeables.config.card_limit = #CONSUMABLES
    for _, key in ipairs(CONSUMABLES) do
        local card = create_card('Tarot', G.consumeables, nil, nil, nil, nil, key)
        card:add_to_deck()
        G.consumeables:emplace(card)
    end
    for _ = 1, 8 do add_tag(Tag('tag_double')) end
    G.hand:change_size(12 - G.hand.config.card_limit)
    G.FUNCS.draw_from_deck_to_hand()
end

local function long_numbers(value)
    -- Under Talisman the game's numbers are its big-number type.
    if to_big then value = to_big(value) end
    G.GAME.dollars = 9999999999
    G.GAME.round_resets.ante = 39
    G.GAME.round = 999
    G.GAME.current_round.hands_left = 99
    G.GAME.current_round.discards_left = 99
    G.GAME.chips = value
    G.GAME.blind.chips = value
    G.GAME.blind.chip_text = number_format(value)
    G.FUNCS.blind_chip_UI_scale(G.hand_text_area.blind_chips)
    update_hand_text({immediate = true, nopulse = true, delay = 0},
        {handname = localize('Straight Flush', 'poker_hands'), chips = value, mult = value, level = 99})
end

wait_title()

if not G.F_PORTRAIT then
    log('landscape window: layout styles do not apply, nothing to check')
    return
end

for i, name in ipairs(PORTRAIT_LAYOUT_NAMES) do
    local tag = name:lower():gsub('%W', '')
    step('stress ' .. name, function()
        G.SETTINGS.portrait_layout = i
        G.FUNCS.start_run(nil, {stake = 1, seed = SEED})
        wait_state('BLIND_SELECT', 30)
        leak_check(name .. ' new run')

        select_blind()
        wait_until(function() return #G.hand.cards > 0 end, 15, 'cards in hand')
        settle(1)

        load_up()
        wait_until(function() return #G.hand.cards >= 12 and G.STATE_COMPLETE end, 20, '12 cards in hand')
        -- A boss with a two-line debuff, on top of everything else.
        G.GAME.blind:set_blind(G.P_BLINDS.bl_final_leaf, nil, true)
        settle(1.5)
        log(name .. ':', #G.jokers.cards, 'jokers (limit ' .. G.jokers.config.card_limit .. '),',
            #G.consumeables.cards, 'consumables,', #G.hand.cards, 'in hand,', #G.HUD_tags, 'tags')

        long_numbers(99999999999)
        wait(1)
        log(name .. ': round score text', tostring(G.GAME.chips_text), 'blind', tostring(G.GAME.blind.chip_text))
        measure(name .. ' 99,999,999,999', tag .. '_long_numbers')

        long_numbers(math.huge)
        wait(1)
        log(name .. ': round score text', tostring(G.GAME.chips_text), 'blind', tostring(G.GAME.blind.chip_text))
        measure(name .. ' naneinf', tag .. '_naneinf')

        -- Talisman makes scores past the float limit reachable: e1000.
        if to_big then
            long_numbers(to_big(10) ^ 1000)
            wait(1)
            log(name .. ': round score text', tostring(G.GAME.chips_text), 'blind', tostring(G.GAME.blind.chip_text))
            measure(name .. ' e1000', tag .. '_e1000')
        end

        -- Play it: scoring, the round's end and the shop with all of it. The
        -- score goes back to a number first: the game's own chip easing turns
        -- an infinite score into NaN, which never beats a blind.
        G.GAME.blind.chips = to_big and to_big(300) or 300
        G.GAME.blind.chip_text = number_format(G.GAME.blind.chips)
        G.GAME.chips = to_big and to_big(299) or 299
        local before = G.GAME.current_round.hands_left
        G.hand:unhighlight_all()
        for _, c in ipairs(best_hand()) do tap_node(c) wait(0.12) end
        wait(0.4)
        shot(tag .. '_selected')
        tap_ui({id = 'play_button'})
        wait_until(function() return G.GAME.current_round.hands_left < before end, 10, 'Play button plays')
        wait(1)
        shot(tag .. '_scoring')
        wait_state('ROUND_EVAL', 60)
        wait_until(function() return find({button = 'cash_out'}) end, 30, 'cash out button')
        settle(1)
        check_on_screen({button = 'cash_out'}, name .. ': Cash Out')
        check(offscreen_check(tag .. '_round_eval') == 0, name .. ': round end, nothing cut off')
        shot(tag .. '_round_eval')
        tap_ui({button = 'cash_out'})
        wait_until(function()
            return state_is('SHOP') and find({id = 'next_round_button'}) and G.shop_jokers and #G.shop_jokers.cards > 0
                and G.shop_jokers.cards[1].states.visible ~= false
        end, 30, 'shop stocked')
        settle(1)
        check_on_screen({id = 'next_round_button'}, name .. ': Next Round')
        all_on_screen(G.jokers, name .. ' shop jokers shelf')
        all_on_screen(G.consumeables, name .. ' shop consumables shelf')
        all_on_screen(G.shop_jokers, name .. ' shop offers')
        overlap_check(name .. ' shop')
        check(offscreen_check(tag .. '_shop') == 0, name .. ': shop, nothing cut off')
        shot(tag .. '_shop')
    end)
end
