-- #11: a joker held by a finger that stops at each height down the screen, then
-- sweeps sideways low down. Neither the card nor its description may shake while
-- the finger is still: low on the screen the description jumped between two
-- places every frame.

local SEED = os.getenv('BPM_HL_SEED') or 'BPMTEST1'

G.SETTINGS.portrait_layout = tonumber(os.getenv('BPM_HL_LAYOUT') or '1')
G.FUNCS.start_run(nil, {stake = 1, seed = SEED})
wait_state('BLIND_SELECT', 30)
select_blind()
wait_state('SELECTING_HAND', 30)
wait_until(function() return #G.hand.cards > 0 and input_ready() end, 15, 'cards in hand')
for _, key in ipairs({'j_joker', 'j_blueprint', 'j_egg'}) do
    local card = create_card('Joker', G.jokers, nil, nil, nil, nil, key)
    card:add_to_deck()
    G.jokers:emplace(card)
end
wait(1.5)

local s = G.TILESCALE * G.TILESIZE
local W, H = love.graphics.getDimensions()
local card = G.jokers.cards[2]
local x = (card.T.x + card.T.w / 2 + G.ROOM.T.x) * s
local y0 = (card.T.y + card.T.h / 2 + G.ROOM.T.y) * s
local id = 777
love.event.push('touchpressed', id, x, y0, 0, 0, 1)
frames(2)
local px, py = x, y0
local worst, worst_y = 0, 0
for step = 0, 40 do
    local y = y0 + (H * 0.97 - y0) * step / 40
    love.event.push('touchmoved', id, x, y, x - px, y - py, 1)
    px, py = x, y
    frames(15)
    local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
    local flips = 0
    local last_dx
    local p0x, p1x, p0y, p1y, types = 1e9, -1e9, 1e9, -1e9, {}
    for _ = 1, 30 do
        frames(1)
        local pp = card.children.h_popup
        if pp then
            p0x, p1x = math.min(p0x, pp.VT.x), math.max(p1x, pp.VT.x)
            p0y, p1y = math.min(p0y, pp.VT.y), math.max(p1y, pp.VT.y)
            types[tostring(pp.alignment and pp.alignment.type)] = true
        end
        local vx, vy = card.VT.x, card.VT.y
        minx, maxx = math.min(minx, vx), math.max(maxx, vx)
        miny, maxy = math.min(miny, vy), math.max(maxy, vy)
    end
    local range = math.max(maxx - minx, maxy - miny) * s
    log(string.format('finger y=%4d (%.2f of screen)  card moves %.1f px  T=(%.2f,%.2f) area=%s',
        y, y / H, range, card.T.x, card.T.y, tostring(card.area == G.jokers and 'jokers' or card.area)))
    local prange = p1x > p0x - 1 and math.max(p1x - p0x, p1y - p0y) * s or 0
    local tl = {} for k in pairs(types) do tl[#tl + 1] = k end
    log(string.format('   popup moves %.1f px types=%s', prange, table.concat(tl, ',')))
    if prange > worst then worst, worst_y = prange, y end
    if range > worst then worst, worst_y = range, y end
end
for _, fy in ipairs({0.62, 0.68, 0.72, 0.76, 0.80, 0.85}) do
    for step = 0, 12 do
        local xx = W * (0.05 + 0.9 * step / 12)
        local yy = H * fy
        love.event.push('touchmoved', id, xx, yy, xx - px, yy - py, 1)
        px, py = xx, yy
        frames(20)
        local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
        local others = {}
        for _, area in ipairs({G.jokers, G.hand, G.consumeables}) do
            for _, c in ipairs(area.cards) do if c ~= card then others[#others + 1] = {c = c, x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9} end end
        end
        for _ = 1, 30 do
            frames(1)
            minx, maxx = math.min(minx, card.VT.x), math.max(maxx, card.VT.x)
            miny, maxy = math.min(miny, card.VT.y), math.max(maxy, card.VT.y)
            for _, o in ipairs(others) do
                o.x0, o.x1 = math.min(o.x0, o.c.VT.x), math.max(o.x1, o.c.VT.x)
                o.y0, o.y1 = math.min(o.y0, o.c.VT.y), math.max(o.y1, o.c.VT.y)
            end
        end
        for _, o in ipairs(others) do
            local r = math.max(o.x1 - o.x0, o.y1 - o.y0) * s
            if r > 1 then log(string.format('OTHER SHAKE finger (%d,%d) %.2f: %s in %s moves %.1f px', xx, yy, fy, o.c.config.center.key or '?', o.c.area == G.jokers and 'jokers' or (o.c.area == G.hand and 'hand' or '?'), r)) end
        end
        local range = math.max(maxx - minx, maxy - miny) * s
        if range > 1 then log(string.format('SHAKE finger (%d,%d) (%.2f of screen) card moves %.1f px', xx, yy, fy, range)) end
        if range > worst then worst, worst_y = range, yy end
    end
end
love.event.push('touchreleased', id, px, py, 0, 0, 1)
frames(5)
check(worst < 2, string.format('a held joker stays still (worst %.1f px at y=%d of %d)', worst, worst_y, H))
