-- Blind select and the round's end in each layout style, for what long words do
-- to them (--lang): the prompt beside the score, the joker count over the blinds,
-- a tag's tooltip by the screen's edge, and the column of dollars when a round pays
-- out.

local SEED = os.getenv('BPM_HL_SEED') or 'BPMTEST1'

local function right(node) return node.T.x + node.T.w end
local function bottom(node) return node.T.y + node.T.h end

local function settle(extra)
    wait_until(input_ready, 20, 'input ready')
    wait(extra or 0.8)
end

local function find_tags(node, found)
    local object = node.config and node.config.object
    if object and object.config and object.config.tag then found[#found + 1] = object end
    if object and object.UIRoot then find_tags(object.UIRoot, found) end
    for _, child in pairs(node.children or {}) do find_tags(child, found) end
    return found
end

local function prompt_check(name)
    local box = G.blind_prompt_box
    local chips = G.HUD:get_UIE_by_ID('hand_chips_container') or G.HUD:get_UIE_by_ID('hand_chips')
    local panel = G.HUD:get_UIE_by_ID('row_blind')
    check(box and panel, name .. ': prompt and blind panel are there')
    if not (box and panel) then return end
    for i = 1, 2 do
        local text = box:get_UIE_by_ID('prompt_dynatext' .. i)
        check(text.T.x >= panel.T.x - 0.02 and right(text) <= right(panel) + 0.02,
            string.format('%s: prompt line %d inside its panel (%.2f-%.2f in %.2f-%.2f)',
                name, i, text.T.x, right(text), panel.T.x, right(panel)))
    end
end

local function count_check(name)
    local count = G.jokers.children.area_uibox
    local gap = G.blind_select.T.y - bottom(count)
    -- A panel taller than the room under the shelf gives up that gap first, as
    -- portrait_blind_select_offset says, so its bottom row stays on the screen.
    if G.blind_select.T.h > portrait_screen_bottom() - portrait_shelf_floor() then
        if gap < 0 then warn(string.format('%s: blinds taller than the room under the shelf, count covered by %.2f', name, -gap)) end
        return
    end
    check(gap >= 0, string.format('%s: joker count clear of the blinds (%.2f)', name, gap))
end

-- A finger held on a tag, the way the tooltip opens on a phone.
local function held_tag_check(name, tag, sprite)
    local s = G.TILESCALE * G.TILESIZE
    local x = (sprite.T.x + sprite.T.w / 2 + G.ROOM.T.x) * s
    local y = (sprite.T.y + sprite.T.h / 2 + G.ROOM.T.y) * s
    love.event.push('mousemoved', x, y, 0, 0, false)
    frames(2)
    love.event.push('touchpressed', 900, x, y, 0, 0, 1)
    wait_real(0.8)
    local row = G.blind_select_opts.small:get_UIE_by_ID('tag_Small')
    local popup = row.children.alert
    check(popup ~= nil, name .. ': a held tag opens its tooltip')
    if popup then
        local ok, where = on_screen(popup, 0)
        check(ok, name .. ': held tag tooltip on screen ' .. where)
    end
    shot(tag .. '_tag_held')
    love.event.push('touchreleased', 900, x, y, 0, 0, 1)
    frames(4)
end

local function tag_check(name, tag)
    local tags = {}
    for _, choice in pairs(G.blind_select_opts) do find_tags(choice.UIRoot, tags) end
    check(#tags > 0, name .. ': blinds show tags')
    table.sort(tags, function(p, q) return p.T.x < q.T.x end)
    held_tag_check(name, tag, tags[1])
    for i, sprite in ipairs(tags) do
        sprite:hover()
        wait(0.4)
        local popup = sprite.children.h_popup
        check(popup ~= nil, name .. ': tag ' .. i .. ' has a tooltip')
        if popup then
            local ok, where = on_screen(popup, 0)
            check(ok, name .. ': tag ' .. i .. ' tooltip on screen ' .. where)
        end
        sprite:stop_hover()
        wait(0.2)
    end

    -- Every tag, at each end of the row of blinds: how far a tooltip runs depends on
    -- its text.
    local left, right_most = tags[1], tags[1]
    for _, sprite in ipairs(tags) do
        if sprite.T.x < left.T.x then left = sprite end
        if sprite.T.x > right_most.T.x then right_most = sprite end
    end
    local worst = 99
    for key in pairs(G.P_TAGS) do
        for _, place in ipairs({left, right_most}) do
            local _, sprite = Tag(key, nil, 'Small'):generate_UI()
            sprite.T.x, sprite.T.y = place.T.x, place.T.y
            sprite.VT.x, sprite.VT.y = place.T.x, place.T.y
            sprite.states.visible = true
            sprite:hover()
            frames(4)
            local popup = sprite.children.h_popup
            if popup then
                local ok, where = on_screen(popup, 0)
                if not ok then check(false, name .. ': ' .. key .. ' tooltip on screen ' .. where) end
                worst = math.min(worst, popup.T.x, G.ROOM.T.w - right(popup))
            end
            sprite:stop_hover()
            sprite:remove()
        end
    end
    log(string.format('%s: closest a tag tooltip gets to the edge %.2f', name, worst))
end

local function dollars_check(name, tag)
    local rows = {}
    for _, id in ipairs({'blind1', 'hands', 'interest'}) do
        local node = G.round_eval:get_UIE_by_ID('dollar_' .. id)
        check(node ~= nil, name .. ': round pays ' .. id)
        if node then rows[#rows + 1] = {id = id, x = right(node)} end
    end
    for i = 2, #rows do
        check(math.abs(rows[i].x - rows[1].x) < 0.03, string.format('%s: %s dollars in line with %s (%.2f, %.2f)',
            name, rows[i].id, rows[1].id, rows[i].x, rows[1].x))
    end
    for _, row in ipairs(rows) do
        check(row.x <= right(G.round_eval), name .. ': ' .. row.id .. ' dollars inside the panel')
    end
    shot(tag .. '_round_eval')
end

wait_title(120)
milestone('title')
if not G.F_PORTRAIT then done() end

for i, name in ipairs(PORTRAIT_LAYOUT_NAMES) do
    local tag = PORTRAIT_LAYOUTS[i]
    step(name, function()
        G.SETTINGS.portrait_layout = i
        -- A tag with a long description, in the leftmost blind.
        G.FORCE_TAG = 'tag_double'
        G.FUNCS.start_run(nil, {stake = 1, seed = SEED})
        wait_state('BLIND_SELECT', 30)
        wait_until(function() dismiss_popups() return find({button = 'select_blind'}) end, 20, 'blind choices')
        settle(1.5)
        shot(tag .. '_blind_select')
        prompt_check(name)
        count_check(name)
        tag_check(name, tag)
        screen_check(tag .. '_blind_select')

        select_blind()
        wait_state('SELECTING_HAND', 30)
        wait_until(function() return #G.hand.cards > 0 end, 15, 'cards in hand')
        settle(1)

        for _, card in ipairs({G.hand.cards[1], G.hand.cards[#G.hand.cards]}) do
            card:hover()
            wait(0.4)
            local popup = card.children.h_popup
            if popup then
                local ok, where = on_screen(popup, 0)
                check(ok, name .. ': card tooltip on screen ' .. where)
            end
            card:stop_hover()
            wait(0.2)
        end

        -- One point short of the blind with money in the bank, so the round pays
        -- out for the blind, the hands left and the interest.
        G.GAME.dollars = to_big and to_big(25) or 25
        G.GAME.chips = G.GAME.blind.chips - 1
        local hands = G.GAME.current_round.hands_left
        for _, c in ipairs(best_hand()) do tap_node(c) wait(0.12) end
        G.FUNCS.play_cards_from_highlighted()
        wait_until(function() return G.GAME.current_round.hands_left < hands end, 10, 'hand played')
        wait_state('ROUND_EVAL', 40)
        wait_until(function() return find({button = 'cash_out'}) end, 30, 'cash out button')
        settle(1)
        dollars_check(name, tag)
    end)
end

done()
