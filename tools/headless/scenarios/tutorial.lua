-- The game's tutorial, which a first run opens with (BPM_HL_TUTORIAL=1 keeps it): every
-- step of Jimbo's, with its speech bubble, its dimmed screen and what it points at.
-- Steps that wait for a hand or a discard are played for it.

local function settle(extra)
    wait_until(input_ready, 20, 'input ready')
    wait(extra or 0.5)
end

wait_title(120)
milestone('title')
if not G.F_PORTRAIT then done() end

G.FUNCS.start_run(nil, {stake = 1, seed = 'TUTORIAL'})
wait_state('BLIND_SELECT', 30)
wait(2)

local seen = 0
local deadline = love.timer.getTime() + 40
local last_step
while love.timer.getTime() < deadline do
    local progress = G.SETTINGS.tutorial_progress
    if not progress or G.SETTINGS.tutorial_complete then break end
    local step_name = tostring(progress.section) .. ':' .. tostring(progress.completed_parts and #progress.completed_parts or 0) .. ':' .. tostring(progress.hold_parts and 1 or 0)

    local next_button = find({button = 'tut_next'})
    if next_button then
        seen = seen + 1
        wait(0.6)
        shot('tutorial_' .. seen)
        tap_node(next_button)
        wait(0.5)
    elseif G.STATE == G.STATES.BLIND_SELECT and find({button = 'select_blind'}) then
        tap_ui({button = 'select_blind'})
        wait(1)
    elseif G.STATE == G.STATES.SELECTING_HAND and G.STATE_COMPLETE and #G.hand.cards > 0 and input_ready() then
        if #G.hand.highlighted == 0 then
            for _, c in ipairs(best_hand()) do tap_node(c) wait(0.1) end
        end
        if find({button = 'play_cards_from_highlighted'}) then
            G.FUNCS.play_cards_from_highlighted()
        end
        wait(1)
    elseif find({button = 'cash_out'}) then
        tap_ui({button = 'cash_out'})
        wait(1)
    elseif G.STATE == G.STATES.SHOP and find({id = 'next_round_button'}) then
        tap_ui({id = 'next_round_button'})
        wait(1)
    else
        wait(0.5)
    end
    last_step = step_name
end
log('tutorial bubbles seen', seen, tostring(last_step))
check(seen >= 5, 'the tutorial showed its steps (' .. seen .. ')')
done()
