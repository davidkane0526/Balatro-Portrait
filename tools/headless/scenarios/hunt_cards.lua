-- The tooltip of every card the game has, at both ends of the row it sits in, in
-- each layout style: jokers (with stickers), consumables, and playing cards with
-- every enhancement, seal and edition. A tooltip that runs off the screen or out
-- of its panel is noted by the audit (tools/headless/audit.py).

local SEED = os.getenv('BPM_HL_SEED') or 'BPMTEST1'

local function settle(extra)
    wait_until(input_ready, 20, 'input ready')
    wait(extra or 0.8)
end

local function make(area, key)
    local card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H, nil, G.P_CENTERS[key],
        {bypass_discovery_center = true, bypass_discovery_ui = true})
    area:emplace(card)
    return card
end

local function inspect(card, tag)
    frames(2)
    card:hover()
    frames(3)
    text_audit(tag)
    card:stop_hover()
end

local function sweep(area, pool, tag, filler)
    -- Alone in its row, then at the far end of a full one.
    for _, center in ipairs(pool) do
        local card = make(area, center.key)
        inspect(card, tag .. '_first')
        card:remove()
    end
    local others = {}
    for _ = 1, 3 do others[#others + 1] = make(area, filler) end
    for _, center in ipairs(pool) do
        local card = make(area, center.key)
        inspect(card, tag .. '_last')
        card:remove()
    end
    for _, card in ipairs(others) do card:remove() end
    frames(3)
end

wait_title(120)
milestone('title')
unlock_all()
if not G.F_PORTRAIT then done() end

for i, name in ipairs(PORTRAIT_LAYOUT_NAMES) do
    local tag = PORTRAIT_LAYOUTS[i]
    step(name, function()
        G.SETTINGS.portrait_layout = i
        G.FUNCS.start_run(nil, {stake = 1, seed = SEED})
        wait_state('BLIND_SELECT', 30)
        select_blind()
        wait_state('SELECTING_HAND', 30)
        wait_until(function() return #G.hand.cards > 0 end, 15, 'cards in hand')
        settle(1)
        G.jokers.config.card_limit = 20
        G.consumeables.config.card_limit = 20

        sweep(G.jokers, G.P_CENTER_POOLS.Joker, tag .. '_joker', 'j_joker')
        for _, set in ipairs({'Tarot', 'Planet', 'Spectral'}) do
            sweep(G.consumeables, G.P_CENTER_POOLS[set], tag .. '_' .. set, 'c_pluto')
        end

        -- Stickers on a joker, alone and with an edition, which add tooltips beside it.
        local card = make(G.jokers, 'j_ancient')
        for _, edition in ipairs({'foil', 'holo', 'polychrome', 'negative'}) do
            card:set_edition({[edition] = true}, true, true)
            inspect(card, tag .. '_edition')
        end
        card:set_eternal(true)
        inspect(card, tag .. '_eternal')
        card.ability.eternal = nil
        card:set_perishable(true)
        inspect(card, tag .. '_perishable')
        card:set_rental(true)
        inspect(card, tag .. '_rental')
        card:remove()

        -- A playing card at each end of the hand.
        for _, place in ipairs({1, #G.hand.cards}) do
            local c = G.hand.cards[place]
            for _, center in ipairs(G.P_CENTER_POOLS.Enhanced) do
                c:set_ability(center, nil, true)
                for _, seal in ipairs({false, 'Gold', 'Red', 'Blue', 'Purple'}) do
                    c:set_seal(seal or nil, true, true)
                    inspect(c, tag .. '_playing_' .. place)
                end
            end
            for _, edition in ipairs({'foil', 'holo', 'polychrome'}) do
                c:set_edition({[edition] = true}, true, true)
                inspect(c, tag .. '_playing_edition_' .. place)
            end
        end
        shot(tag .. '_cards_done')
    end)
end

done()
