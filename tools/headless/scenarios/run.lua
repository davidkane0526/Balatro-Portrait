-- A bot plays a seeded run by touch until it has cleared BPM_HL_ANTES antes
-- (default 2) or lost, going through every kind of screen a run has: blind
-- select (one skip), hands played by button and by swipe, a swipe discard,
-- round end and cash out, the shop (buying a joker, a booster pack and
-- picking from it, a reroll, selling and using cards), boss blinds, Run Info
-- and Options mid-run, and at the end quit to the title and Continue.
--
-- BPM_HL_SEED (default BPMTEST1) fixes the deck, so a failure reproduces.
-- BPM_HL_RICH=0 plays with the real money; by default the shop tops it up to
-- $40 so every shop button gets pressed.

local ANTES = tonumber(os.getenv('BPM_HL_ANTES') or '') or 2
local SEED = os.getenv('BPM_HL_SEED') or 'BPMTEST1'
local RICH = os.getenv('BPM_HL_RICH') ~= '0'

local seen = {}
local function first(tag)
    if seen[tag] then return end
    seen[tag] = true
    screen_check(tag)
end

local function settle(extra)
    wait_until(input_ready, 20, 'input ready')
    wait(extra or 0.6)
end

-- Steamodded opens every booster in a state of its own.
PACK_STATES = {'TAROT_PACK', 'PLANET_PACK', 'SPECTRAL_PACK', 'STANDARD_PACK', 'BUFFOON_PACK', 'SMODS_BOOSTER_OPENED'}

local function state_is(...)
    for _, name in ipairs({...}) do
        if G.STATE == G.STATES[name] then return true end
    end
    return false
end

local function card_center(card)
    local x, y, w, h = rect(card)
    return x + w / 2, y + h / 2
end

local function select_cards(cards)
    G.hand:unhighlight_all()
    frames(3)
    for _, c in ipairs(cards) do
        tap_node(c)
        wait(0.12)
    end
    wait(0.3)
end

---------------------------------------------------------------------------

wait_title()
milestone('title')
G.FUNCS.start_run(nil, {stake = 1, seed = SEED})
log('run seed', SEED)

local hands_played, used_swipe_play, used_swipe_discard, used_button_discard = 0, false, false, false
local skipped_blind, opened_run_info, opened_options = false, false, false
local bought_joker, opened_pack, rerolled, sold, used_consumable, redeemed = false, false, false, false, false, false
local result = 'running'
local continued = false
local deadline = love.timer.getTime() + 60

while result == 'running' do
    -- Wait for the next screen that wants a decision, closing unlock popups.
    wait_until(function()
        if G.OVERLAY_MENU and input_ready() and not state_is('GAME_OVER') then
            return true
        end
        return G.STATE_COMPLETE and state_is('BLIND_SELECT', 'SELECTING_HAND', 'ROUND_EVAL', 'SHOP',
            'GAME_OVER', unpack(PACK_STATES))
            and input_ready()
    end, 60, 'next decision (state ' .. tostring(G.STATE) .. ')')

    -- Save and continue, once, at the first blind select of ante 2: quit to
    -- the title and resume the run that was saved.
    if not continued and state_is('BLIND_SELECT') and G.GAME.round_resets.ante == 2 then
        continued = true
        step('save and continue', function()
            -- The save written on leaving the shop goes through the save thread;
            -- quitting the same frame resumes from the one before it (the shop).
            wait(3)
            local ante, dollars, jokers = G.GAME.round_resets.ante, plain_number(G.GAME.dollars), #G.jokers.cards
            G.FUNCS.go_to_menu()
            wait_title()
            tap_ui({id = 'main_menu_play'})
            wait(1.2)
            screen_check('continue_offer')
            tap_ui({button = 'start_setup_run'})
            wait_until(function()
                dismiss_popups()
                return G.STAGE == G.STAGES.RUN and not G.OVERLAY_MENU and G.STATE_COMPLETE
                    and (find({button = 'select_blind'}) ~= nil or find({id = 'next_round_button'}) ~= nil)
            end, 40, 'continued run')
            settle(1.5)
            check(G.GAME.round_resets.ante == ante, 'continued run is on the same ante (' .. ante .. ')')
            check(plain_number(G.GAME.dollars) == dollars, 'continued run kept its money ($' .. dollars .. ')')
            check(#G.jokers.cards == jokers, 'continued run kept its jokers (' .. jokers .. ')')
            screen_check('continued')
            milestone('saved and continued (' .. (state_is('SHOP') and 'shop' or 'blind select') .. ')')
        end)
    end

    if dismiss_popups() then
        first('unlock_popup')
        goto continue
    end

    if G.GAME.round_resets and G.GAME.round_resets.ante > ANTES and state_is('BLIND_SELECT') then
        result = 'cleared'
        break
    end

    if state_is('GAME_OVER') then
        settle(2)
        first('game_over')
        milestone('game over at ante ' .. G.GAME.round_resets.ante)
        result = 'lost'
        break

    elseif state_is('BLIND_SELECT') then
        wait_until(function() return find({button = 'select_blind'}) end, 15, 'blind choices')
        settle(1)
        first('blind_select_ante' .. G.GAME.round_resets.ante)
        local on_deck = G.GAME.blind_on_deck
        if on_deck == 'Big' and not skipped_blind and find({button = 'skip_blind'}) then
            step('skip blind', function()
                local tags = #G.GAME.tags
                tap_ui({button = 'skip_blind'})
                wait_until(function() return G.GAME.blind_on_deck ~= 'Big' end, 15, 'blind skipped')
                check(#G.GAME.tags > tags, 'skipping the Big Blind gave a tag')
                milestone('skipped big blind')
            end)
            skipped_blind = true
        else
            if on_deck == 'Boss' then first('boss_select') end
            tap_ui({button = 'select_blind'})
            wait_until(function() return not state_is('BLIND_SELECT') end, 20, 'blind selected')
            milestone(on_deck .. ' blind ante ' .. G.GAME.round_resets.ante)
        end

    elseif state_is('SELECTING_HAND') then
        wait_until(function() return #G.hand.cards > 0 end, 15, 'cards in hand')
        settle(0.8)
        first('hand')

        if not opened_run_info and find({button = 'run_info'}) then
            opened_run_info = true
            step('run info', function()
                tap_ui({button = 'run_info'})
                wait(1)
                screen_check('run_info')
                tap_tabs = nil
                back()
                settle()
            end)
        end
        if not opened_options and find({button = 'options'}) then
            opened_options = true
            step('options in run', function()
                tap_ui({button = 'options'})
                wait(1)
                screen_check('options_in_run')
                check_on_screen({button = 'open_portrait_support'}, 'Support button in a run')
                back()
                settle()
            end)
        end

        -- One swipe discard and one button discard per run, on a hand that has
        -- discards to spare: the two weakest cards.
        local discards = G.GAME.current_round.discards_left
        if discards > 0 and ((not used_swipe_discard and G.F_PORTRAIT) or not used_button_discard) and hands_played >= 1 then
            local sorted = {unpack(G.hand.cards)}
            table.sort(sorted, function(a, b) return a:get_chip_bonus() < b:get_chip_bonus() end)
            local pick = {sorted[1], sorted[2]}
            if not used_swipe_discard and G.F_PORTRAIT then
                used_swipe_discard = true
                step('swipe discard', function()
                    select_cards(pick)
                    check(#G.hand.highlighted == 2, 'two cards selected for the swipe discard')
                    local x, y = card_center(G.hand.highlighted[1])
                    swipe(x, y, x, y + 160, 0.15)
                    wait_until(function() return G.GAME.current_round.discards_left < discards end, 10,
                        'swipe down discards')
                    check(true, 'swipe down on a selected card discards')
                    milestone('swipe discard')
                end)
            else
                used_button_discard = true
                step('button discard', function()
                    select_cards(pick)
                    tap_ui({id = 'discard_button'})
                    wait_until(function() return G.GAME.current_round.discards_left < discards end, 10,
                        'discard button')
                end)
            end
            wait_until(function() return state_is('SELECTING_HAND') and G.STATE_COMPLETE end, 30, 'redraw')
            settle(0.8)
        end

        if state_is('SELECTING_HAND') then
            local cards, est = best_hand()
            local before_hands = G.GAME.current_round.hands_left
            step('play hand', function()
                select_cards(cards)
                check(#G.hand.highlighted == #cards,
                    string.format('touch selected %d/%d cards', #G.hand.highlighted, #cards))
                if hands_played == 0 then first('selected') end
                if not used_swipe_play and G.F_PORTRAIT then
                    used_swipe_play = true
                    local x, y = card_center(G.hand.highlighted[1])
                    swipe(x, y, x, y - 170, 0.15)
                    wait_until(function() return G.GAME.current_round.hands_left < before_hands end, 10,
                        'swipe up plays')
                    check(true, 'swipe up on a selected card plays the hand')
                    milestone('swipe play')
                else
                    tap_ui({id = 'play_button'})
                    wait_until(function() return G.GAME.current_round.hands_left < before_hands end, 10,
                        'play button')
                end
            end)
            hands_played = hands_played + 1
            log(string.format('hand %d: %d cards, est %d, chips %s / %s', hands_played, #cards, est,
                tostring(G.GAME.chips), tostring(G.GAME.blind and G.GAME.blind.chips)))
        end

    elseif state_is('ROUND_EVAL') then
        wait_until(function() return find({button = 'cash_out'}) end, 30, 'cash out button')
        settle(1)
        first('round_eval')
        local money = plain_number(G.GAME.dollars)
        tap_ui({button = 'cash_out'})
        wait_until(function() return state_is('SHOP') or plain_number(G.GAME.dollars) ~= money end, 20, 'cash out')
        milestone('cashed out ante ' .. G.GAME.round_resets.ante)

    elseif state_is('SHOP') then
        -- Stocked, not just built: the jokers, vouchers and packs are dealt in
        -- by events after the panel appears.
        wait_until(function()
            return find({id = 'next_round_button'}) and G.shop_jokers and #G.shop_jokers.cards > 0
                and G.shop_booster and #G.shop_booster.cards > 0 and G.shop_vouchers and #G.shop_vouchers.cards > 0
                and G.shop_jokers.cards[1].states.visible ~= false
        end, 20, 'shop stocked')
        settle(1.2)
        first('shop')
        if RICH and plain_number(G.GAME.dollars) < 40 then
            G.GAME.dollars = to_big and to_big(40) or 40
            log('shop: money topped up to $40 (BPM_HL_RICH)')
        end

        if not bought_joker and G.shop_jokers and #G.shop_jokers.cards > 0
            and #G.jokers.cards < G.jokers.config.card_limit then
            bought_joker = true
            step('buy joker', function()
                local n = #G.jokers.cards + #G.consumeables.cards
                tap_node(G.shop_jokers.cards[1])
                wait(0.5)
                first('shop_card_selected')
                tap_ui({button = 'buy_from_shop'})
                wait_until(function() return #G.jokers.cards + #G.consumeables.cards > n end, 10, 'bought card arrives')
                milestone('bought a card')
                settle()
            end)
        end

        if not opened_pack and G.shop_booster and #G.shop_booster.cards > 0 then
            opened_pack = true
            step('booster pack', function()
                local pack = G.shop_booster.cards[1]
                tap_node(pack)
                wait(0.5)
                -- The game renames the Open button to use_card every frame.
                tap_ui({button = 'use_card', card = pack})
                wait_until(function()
                    return state_is(unpack(PACK_STATES)) and G.pack_cards and #G.pack_cards.cards > 0
                end, 20, 'pack opened')
                settle(1.5)
                screen_check('pack')
                milestone('opened pack')
                local pick = G.pack_cards.cards[1]
                tap_node(pick)
                wait(0.6)
                screen_check('pack_card_selected')
                local use = find({button = 'use_card', card = pick})
                if use then
                    tap_node(use)
                else
                    tap_ui({button = 'skip_booster'})
                end
                wait_until(function() return state_is('SHOP') end, 20, 'back to shop after the pack')
                settle(1)
            end)
        end

        if not redeemed and G.shop_vouchers and #G.shop_vouchers.cards > 0 then
            redeemed = true
            step('redeem voucher', function()
                local voucher = G.shop_vouchers.cards[1]
                tap_node(voucher)
                wait(0.5)
                tap_ui({button = 'use_card', card = voucher})
                wait_until(function() return #G.shop_vouchers.cards == 0 end, 15, 'voucher redeemed')
                milestone('redeemed voucher')
                settle()
            end)
        end

        if not rerolled and find({button = 'reroll_shop'}) then
            rerolled = true
            step('reroll', function()
                local money = plain_number(G.GAME.dollars)
                tap_ui({button = 'reroll_shop'})
                wait_until(function() return plain_number(G.GAME.dollars) < money end, 10, 'reroll paid')
                settle()
            end)
        end

        if not used_consumable and #G.consumeables.cards > 0 then
            used_consumable = true
            step('use consumable', function()
                local item = G.consumeables.cards[1]
                tap_node(item)
                wait(0.6)
                screen_check('consumable_selected')
                local use = find({button = 'use_card', card = item})
                if use then
                    local n = #G.consumeables.cards
                    tap_node(use)
                    wait_until(function() return #G.consumeables.cards < n end, 10, 'consumable used')
                    milestone('used consumable')
                else
                    tap_node(G.consumeables.cards[1])
                    log('consumable needs targets, left unused')
                end
                settle()
            end)
        end

        if not sold and G.GAME.round_resets.ante >= 2 and #G.jokers.cards > 0 then
            sold = true
            step('sell joker', function()
                tap_node(G.jokers.cards[1])
                wait(0.6)
                screen_check('joker_selected')
                local n = #G.jokers.cards
                tap_ui({button = 'sell_card'})
                wait_until(function() return #G.jokers.cards < n end, 10, 'joker sold')
                milestone('sold joker')
                settle()
            end)
        end

        tap_ui({id = 'next_round_button'})
        wait_until(function() return not state_is('SHOP') end, 20, 'leave shop')

    else
        -- A pack opened by a skip tag, outside the shop.
        settle(1)
        first('pack_from_tag')
        local skip = find({button = 'skip_booster'})
        if skip then tap_node(skip) end
        wait(1)
    end
    ::continue::
end

milestone('run ' .. result)
check(result ~= 'running', 'the run ended in a known state')

check(used_swipe_play or not G.F_PORTRAIT, 'the swipe-to-play gesture was exercised (portrait only)')
check(opened_pack or result == 'lost' and G.GAME.round_resets.ante == 1, 'a booster pack was opened')
check(continued or result == 'lost', 'save and continue was exercised')
