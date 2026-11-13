-- Everything reachable without playing, every page of it, with each tooltip opened:
-- the Collection, Stats, Customize Deck, Credits, the decks, stakes and challenges of
-- the run setup, and the windows that open when something unlocks. Text out of
-- place is noted by the audit (tools/headless/audit.py).

local function look(tag)
    settle_ui()
    shot(tag)
    hover_all(tag)
end

local function tabs(tag)
    local _, nodes = find({button = 'change_tab'})
    for i = 1, #(nodes or {}) do
        local _, now = find({button = 'change_tab'})
        if now and now[i] then
            tap_node(now[i])
            look(tag .. '_tab' .. i)
        end
    end
end

-- The arrows of a paged screen: every page, each looked at.
local function pages(tag)
    local _, arrows = find({button = 'option_cycle'})
    local right
    for _, a in ipairs(arrows or {}) do
        if a.config.ref_value ~= 'l' and a.config.ref_table and a.config.ref_table.options then right = a end
    end
    local count = right and #right.config.ref_table.options or 1
    for page = 2, count do
        G.FUNCS.option_cycle(right)
        wait(0.3)
        look(tag .. '_page')
        _, arrows = find({button = 'option_cycle'})
        for _, a in ipairs(arrows or {}) do
            if a.config.ref_value ~= 'l' and a.config.ref_table and a.config.ref_table.options then right = a end
        end
        if not right then break end
    end
end

local function open(name, tag, paged)
    step(tag, function()
        if not G.FUNCS[name] then return end
        G.FUNCS[name]()
        look(tag)
        tabs(tag)
        if paged then pages(tag) end
        back()
    end)
end

wait_title(120)
milestone('title')
unlock_all()
if not G.F_PORTRAIT then done() end

open('high_scores', 'stats')
open('usage', 'usage')
open('customize_deck', 'customize_deck', true)
open('show_credits', 'credits')
open('settings', 'settings')

for _, page in ipairs({'jokers', 'decks', 'vouchers', 'tarots', 'planets', 'spectrals', 'enhancements',
                       'seals', 'editions', 'boosters', 'tags', 'blinds'}) do
    open('your_collection_' .. page, 'collection_' .. page, true)
end

step('run setup decks', function()
    G.FUNCS.setup_run({config = {}})
    settle_ui()
    shot('setup_run')
    if G.P_CENTER_POOLS.Back and G.FUNCS.change_viewed_back then
        for i in ipairs(G.P_CENTER_POOLS.Back) do
            pcall(G.FUNCS.change_viewed_back, {to_key = i, to_val = G.P_CENTER_POOLS.Back[i].name})
            frames(4)
            text_audit('deck_' .. G.P_CENTER_POOLS.Back[i].key)
        end
    end
    for i = 1, #(G.P_CENTER_POOLS.Stake or {}) do
        pcall(G.FUNCS.change_stake, {to_key = i})
        frames(4)
        text_audit('stake_' .. i)
    end
    hover_all('setup_run')
    back()
end)

step('challenges', function()
    G.FUNCS.setup_run({config = {}})
    settle_ui()
    local _, nodes = find({button = 'change_tab'})
    local tab
    for _, node in ipairs(nodes or {}) do
        if node.config.ref_table and node.config.ref_table.tab_definition_function_args == 'Challenges' then tab = node end
        if node.config.ref_table and tostring(node.config.ref_table.label) == localize('b_challenges') then tab = node end
    end
    tab = tab or (nodes and nodes[3])
    if not tab then back() return end
    tap_node(tab)
    settle_ui()
    shot('challenges')
    for i = 1, #(G.CHALLENGES or {}) do
        local page = math.ceil(i / 10)
        if G.FUNCS.change_challenge_list_page and i % 10 == 1 then
            pcall(G.FUNCS.change_challenge_list_page, {cycle_config = {current_option = page}})
            frames(4)
        end
        pcall(G.FUNCS.change_challenge_description, {config = {id = i}})
        frames(4)
        text_audit('challenge_' .. i)
        local _, inner = find({button = 'change_tab'})
        for _, t in ipairs(inner or {}) do
            if t.UIBox ~= tab.UIBox then
                pcall(G.FUNCS.change_tab, t)
                frames(4)
                text_audit('challenge_' .. i .. '_tab')
            end
        end
    end
    back()
end)

step('unlock windows', function()
    for _, key in ipairs({'j_blueprint', 'b_green', 'v_overstock_norm', 'c_black_hole'}) do
        create_unlock_overlay(key)
        wait(1)
        settle_ui()
        shot('unlock_' .. key)
        back()
    end
end)

step('achievements', function()
    for _, key in ipairs({'ante_up', 'high_stakes', 'completionist_plus_plus', 'retrograde', 'roi'}) do
        notify_alert(key)
        wait(1.2)
        text_audit('achievement_' .. key)
        shot('achievement')
        wait(4)
    end
end)

done()
