-- Opening the usage pages of Stats, then starting a round: the game's own code there
-- writes a global the mod's blind panel once kept its type() in, and the next blind
-- select crashed with "attempt to call upvalue '_type' (a string value)".

wait_title(120)
milestone('title')

G.FUNCS.usage()
settle_ui()
local _, tabs = find({button = 'change_tab'})
check(#(tabs or {}) > 0, 'the usage pages have tabs')
for i = 1, #(tabs or {}) do
    local _, now = find({button = 'change_tab'})
    if now and now[i] then
        tap_node(now[i])
        settle_ui()
    end
end
back()

G.FUNCS.start_run(nil, {stake = 1, seed = 'BPMTEST1'})
wait_state('BLIND_SELECT', 30)
wait_until(function() dismiss_popups() return find({button = 'select_blind'}) end, 20, 'blind choices')
check(true, 'blind select opens after the usage pages')
done()
