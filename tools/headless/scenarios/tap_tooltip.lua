-- A tap on a card outside the hand opens its description and leaves it open, so the
-- finger is out of the way; another tap on it, or a press anywhere else, closes it.
-- A finger held still works as before, and cards in the hand still go up on a tap.

local SEED = os.getenv('BPM_HL_SEED') or 'BPMTEST1'

local function popup_of(card) return card.children.h_popup end

-- The description comes a moment after the press, as it does for a held finger.
local function settle() wait_real(0.35) frames(4) end

-- Finger events only: the harness's tap moves a mouse first, and a mouse is not a
-- finger to the game.
local function press_at(x, y)
    love.event.push('mousemoved', x, y, 0, 0, true)
    frames(2)
    love.event.push('touchpressed', 901, x, y, 0, 0, 1)
end

local function release(x, y)
    love.event.push('touchreleased', 901, x, y, 0, 0, 1)
    frames(4)
end

local function tap_at(x, y)
    press_at(x, y)
    wait_real(0.08)
    release(x, y)
end

local function press(card)
    local s = G.TILESCALE * G.TILESIZE
    local x = (card.T.x + card.T.w / 2 + G.ROOM.T.x) * s
    local y = (card.T.y + card.T.h / 2 + G.ROOM.T.y) * s
    press_at(x, y)
    return x, y
end

local function tap_card(card)
    local x, y = press(card)
    wait_real(0.08)
    release(x, y)
    settle()
end

local function opens_and_closes(name, tag, card)
    tap_card(card)
    local popup = popup_of(card)
    check(popup ~= nil, name .. ': a tap opens the description')
    if popup then
        local ok, where = on_screen(popup, 0)
        check(ok, name .. ': its description is on the screen ' .. where)
    end
    shot(tag .. '_open')
    wait_real(1)
    check(popup_of(card) ~= nil, name .. ': the description stays with the finger off')
    tap_card(card)
    check(popup_of(card) == nil, name .. ': a second tap closes it')
end

local function nothing_left(name, cards)
    for _, card in ipairs(cards) do
        if card.area and popup_of(card) then
            check(false, name .. ': a description left open on ' .. tostring(card.ability and card.ability.name))
        end
    end
end

local function joker_checks(name, tag)
    -- Not next to each other: a raised joker's Sell button lies over its neighbour.
    local a, b = G.jokers.cards[1], G.jokers.cards[3]

    opens_and_closes(name .. ': joker', tag .. '_joker', a)
    check(not a.highlighted, name .. ': the second tap also lowers the joker')

    tap_card(a)
    check(a.highlighted and find({button = 'sell_card'}) ~= nil, name .. ': the tap still offers Sell')
    tap_card(b)
    check(popup_of(a) == nil, name .. ': a tap on another joker closes the first description')
    check(popup_of(b) ~= nil, name .. ': and opens its own')
    -- Cryptid raises how many jokers can be up at once.
    local moved = G.jokers.config.highlighted_limit > 1 or not a.highlighted
    check(b.highlighted and moved, name .. ': the highlight moves with it')
    if a.highlighted then tap_card(a) end

    -- Nowhere near a card: the middle of the gap above the hand.
    local s = G.TILESCALE * G.TILESIZE
    tap_at((G.ROOM.T.x + G.ROOM.T.w * 0.5) * s, (G.hand.T.y - 0.25 + G.ROOM.T.y) * s)
    settle()
    check(popup_of(b) == nil, name .. ': a tap elsewhere closes the description')
    if b.highlighted then tap_card(b) end
    if popup_of(b) then tap_card(b) end
    check(not b.highlighted and popup_of(b) == nil, name .. ': the joker can be lowered again')

    -- A finger held: open while it is down, gone with it, nothing selected.
    local x, y = press(a)
    wait_real(0.8)
    check(popup_of(a) ~= nil, name .. ': a held finger opens the description')
    release(x, y)
    settle()
    check(popup_of(a) == nil, name .. ': and lifting it closes it')
    check(not a.highlighted, name .. ': a held finger selects nothing')

    -- Dragged to the other side: no description left behind.
    x, y = press(a)
    wait_real(0.15)
    local to_x = (b.T.x + b.T.w / 2 + G.ROOM.T.x) * s
    for i = 1, 8 do
        local nx = x + (to_x - x) * i / 8
        love.event.push('touchmoved', 901, nx, y, (to_x - x) / 8, 0, 1)
        frames(1)
    end
    release(to_x, y)
    settle()
    check(popup_of(a) == nil, name .. ': a drag leaves no description open')
    if a.highlighted then tap_card(a) end

    -- With a description open, a drag of that same card still ends it.
    tap_card(a)
    x, y = press(a)
    wait_real(0.15)
    to_x = (G.jokers.cards[#G.jokers.cards].T.x + G.ROOM.T.x) * s
    for i = 1, 8 do
        love.event.push('touchmoved', 901, x + (to_x - x) * i / 8, y, (to_x - x) / 8, 0, 1)
        frames(1)
    end
    release(to_x, y)
    settle()
    check(popup_of(a) == nil, name .. ': dragging an open card closes its description')
    if a.highlighted then tap_card(a) end
end

local function hand_checks(name)
    local card = G.hand.cards[3]
    tap_card(card)
    check(card.highlighted, name .. ': a tap in the hand selects the card')
    check(popup_of(card) == nil, name .. ': and opens no description')
    tap_card(card)
    check(not card.highlighted, name .. ': a second tap puts it back')
    local x, y = press(card)
    wait_real(0.8)
    check(popup_of(card) ~= nil, name .. ': a held finger on the hand opens the description')
    release(x, y)
    settle()
    check(popup_of(card) == nil, name .. ': and lifting it closes it')
    if card.highlighted then tap_card(card) end
end

local function sell_check(name)
    local card = G.jokers.cards[#G.jokers.cards]
    local count = #G.jokers.cards
    tap_card(card)
    check(popup_of(card) ~= nil, name .. ': description open before selling')
    tap_ui({button = 'sell_card'})
    wait_until(function() return #G.jokers.cards < count end, 5, 'joker sold')
    settle()
    check(G.CONTROLLER.hovering.target ~= card, name .. ': a sold joker is not held on to')
end

local function overlay_check(name)
    local card = G.jokers.cards[1]
    tap_card(card)
    check(popup_of(card) ~= nil, name .. ': description open before the menu')
    G.FUNCS.options()
    wait_real(0.5)
    check(popup_of(card) == nil, name .. ': a menu opening closes it')
    G.FUNCS.exit_overlay_menu()
    wait_until(function() return not G.OVERLAY_MENU end, 5, 'menu gone')
    settle()
    check(popup_of(card) == nil, name .. ': and it stays closed afterwards')
    if card.highlighted then tap_card(card) end
end

local function add_joker(key)
    local card = create_card('Joker', G.jokers, nil, nil, nil, nil, key)
    card:add_to_deck()
    G.jokers:emplace(card)
    return card
end

local function reach_shop()
    G.GAME.chips = G.GAME.blind.chips - 1
    local hands = G.GAME.current_round.hands_left
    for _, c in ipairs(best_hand()) do tap_node(c) wait(0.12) end
    G.FUNCS.play_cards_from_highlighted()
    wait_until(function() return G.GAME.current_round.hands_left < hands end, 10, 'hand played')
    wait_state('ROUND_EVAL', 40)
    tap_ui({button = 'cash_out'}, 30)
    wait_state('SHOP', 30)
    wait_until(function() return G.shop_jokers and #G.shop_jokers.cards > 0 and input_ready() end, 20, 'shop stocked')
    wait(1)
end

local function option_node()
    local _, toggles = find({button = 'toggle_button'})
    for _, node in ipairs(toggles) do
        if node.config.ref_table.ref_value == 'tap_descriptions' then return node end
    end
end

-- From the pause menu to the Game tab, where the option is, and back to the table.
local function with_settings(work)
    tap_ui({button = 'options'})
    settle_ui()
    tap_ui({button = 'settings'})
    settle_ui()
    work()
    G.FUNCS.exit_overlay_menu()
    wait_until(function() return not G.OVERLAY_MENU and input_ready() end, 5, 'settings closed')
    settle()
end

local function option_checks()
    check(G.SETTINGS.tap_descriptions == true, 'the option is on by default')
    local label = portrait_tap_descriptions_label()
    check(PORTRAIT_TAP_DESCRIPTIONS_LABELS[G.SETTINGS.language] ~= nil, 'the option has a label in ' .. G.SETTINGS.language)
    check(G.LANG.font.FONT:hasGlyphs(label), "the game's font has every letter of " .. label)

    G.SETTINGS.portrait_layout = 1
    G.FUNCS.start_run(nil, {stake = 1, seed = SEED})
    wait_state('BLIND_SELECT', 30)
    wait_until(function() dismiss_popups() return find({button = 'select_blind'}) end, 20, 'blind choices')
    wait(1)
    select_blind()
    wait_state('SELECTING_HAND', 30)
    wait_until(function() return #G.hand.cards > 0 and input_ready() end, 15, 'cards in hand')
    local joker = add_joker('j_joker')
    wait(1.5)

    with_settings(function()
        local node = option_node()
        check(node ~= nil, 'the Game tab has the option')
        if not node then return end
        local ok, where = on_screen(node, 0)
        check(ok, 'the option is on the screen ' .. where)
        shot('option_on')
        screen_check('option_on')
        tap_node(node)
        frames(4)
        check(G.SETTINGS.tap_descriptions == false, 'a tap turns it off')
        shot('option_off')
    end)

    -- Off is the way it was: a tap only raises the joker, a held finger shows the text.
    tap_card(joker)
    check(joker.highlighted, 'off: a tap still raises the joker')
    check(popup_of(joker) == nil, 'off: a tap opens no description')
    tap_card(joker)
    check(not joker.highlighted, 'off: a second tap lowers it')
    local x, y = press(joker)
    wait_real(0.8)
    check(popup_of(joker) ~= nil, 'off: a held finger opens the description')
    release(x, y)
    settle()
    check(popup_of(joker) == nil, 'off: lifting it closes it')

    with_settings(function()
        tap_node(option_node())
        frames(4)
        check(G.SETTINGS.tap_descriptions == true, 'a tap turns it back on')
    end)
    tap_card(joker)
    check(popup_of(joker) ~= nil, 'on again: a tap opens the description')
    tap_card(joker)
    check(popup_of(joker) == nil, 'on again: a second tap closes it')
end

wait_title(120)
milestone('title')
if not G.F_PORTRAIT then done() end
unlock_all()

step('option', option_checks)

for i, name in ipairs(PORTRAIT_LAYOUT_NAMES) do
    local tag = PORTRAIT_LAYOUTS[i]
    step(name, function()
        G.SETTINGS.portrait_layout = i
        G.FUNCS.start_run(nil, {stake = 1, seed = SEED})
        wait_state('BLIND_SELECT', 30)
        wait_until(function() dismiss_popups() return find({button = 'select_blind'}) end, 20, 'blind choices')
        wait(1)
        select_blind()
        wait_state('SELECTING_HAND', 30)
        wait_until(function() return #G.hand.cards > 0 and input_ready() end, 15, 'cards in hand')

        add_joker('j_joker')
        add_joker('j_blueprint')
        add_joker('j_mime')
        local tarot = create_card('Tarot', G.consumeables, nil, nil, nil, nil, 'c_fool')
        tarot:add_to_deck()
        G.consumeables:emplace(tarot)
        wait(1.5)

        joker_checks(name, tag)
        opens_and_closes(name .. ': consumable', tag .. '_consumable', tarot)
        hand_checks(name)
        overlay_check(name)
        sell_check(name)
        nothing_left(name, G.jokers.cards)

        G.GAME.dollars = to_big and to_big(200) or 200
        reach_shop()
        opens_and_closes(name .. ': shop joker', tag .. '_shop', G.shop_jokers.cards[1])
        opens_and_closes(name .. ': shop voucher', tag .. '_voucher', G.shop_vouchers.cards[1])
        opens_and_closes(name .. ': shop pack', tag .. '_booster', G.shop_booster.cards[1])

        -- A tap on an open description closes it, whatever lies under it: not a
        -- way out of the shop by a button it hides.
        for _, card in ipairs(G.shop_jokers.cards) do
            tap_card(card)
            local popup = popup_of(card)
            check(popup ~= nil, name .. ': shop description open to tap on')
            if popup then
                local dollars, rerolls = G.GAME.dollars, G.GAME.current_round.reroll_cost
                local s = G.TILESCALE * G.TILESIZE
                local x0, y0 = popup.T.x, popup.T.y
                local x1, y1 = x0 + popup.T.w, y0 + popup.T.h
                local spot
                for _, button in ipairs({'toggle_shop', 'reroll_shop'}) do
                    local node = find({button = button})
                    if node then
                        local cx, cy = node.T.x + node.T.w / 2, node.T.y + node.T.h / 2
                        if cx > x0 and cx < x1 and cy > y0 and cy < y1 then spot = {cx, cy, button} end
                    end
                end
                log(string.format('%s: description %.2f,%.2f to %.2f,%.2f, %s', name, x0, y0, x1, y1, spot and ('over ' .. spot[3]) or 'over no shop button'))
                spot = spot or {x0 + popup.T.w / 2, y0 + popup.T.h / 2}
                tap_at((spot[1] + G.ROOM.T.x) * s, (spot[2] + G.ROOM.T.y) * s)
                settle()
                check(G.STATE == G.STATES.SHOP, name .. ': a tap on the description stays in the shop')
                check(G.GAME.dollars == dollars and G.GAME.current_round.reroll_cost == rerolls, name .. ': and buys nothing')
                check(popup_of(card) == nil, name .. ': and closes it')
                if G.STATE ~= G.STATES.SHOP then error('left the shop through a description', 0) end
                if card.highlighted then tap_card(card) end
            end
        end

        -- The buy button under an open description still takes the tap.
        local jokers = #G.jokers.cards
        local stock = G.shop_jokers.cards[1]
        tap_card(stock)
        check(popup_of(stock) ~= nil, name .. ': description open before buying')
        shot(tag .. '_shop_buy')
        tap_ui({button = 'buy_from_shop'})
        wait_until(function() return #G.jokers.cards > jokers end, 5, 'joker bought')
        settle()
        check(popup_of(stock) == nil, name .. ': a bought joker closes its description')

        local pack = G.shop_booster.cards[1]
        tap_card(pack)
        tap_ui({button = 'use_card'})
        wait_until(function() return G.pack_cards and #G.pack_cards.cards > 0 and input_ready() end, 20, 'pack open')
        wait(1.5)
        local choice = G.pack_cards.cards[1]
        -- Cards can't be touched until they have dealt in.
        wait_until(function() return choice.states.hover.can end, 10, 'pack card dealt')
        opens_and_closes(name .. ': pack card', tag .. '_pack', choice)
        tap_card(choice)
        shot(tag .. '_pack_selected')
        if choice.highlighted then tap_card(choice) end
        G.FUNCS.skip_booster()
        wait_state('SHOP', 20)
        wait_until(input_ready, 20, 'back in the shop')

        -- Nothing to highlight in the collection, and it toggles all the same.
        G.FUNCS.your_collection_jokers()
        wait_until(function() return G.your_collection and G.your_collection[1] and G.your_collection[1].cards[1] end, 10, 'collection')
        wait_real(1)
        opens_and_closes(name .. ': collection', tag .. '_collection', G.your_collection[1].cards[1])
        G.FUNCS.exit_overlay_menu()
        wait_until(function() return not G.OVERLAY_MENU end, 5, 'collection closed')
        screen_check(tag .. '_end')
    end)
end

done()
