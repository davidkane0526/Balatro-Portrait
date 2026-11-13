-- Android's vibrator, recorded while a hand is dealt and scored. Pulses that
-- land on each other merge into a rumble, so they keep a gap; the Haptic
-- Feedback option sets how long and how hard they are, and Off is silent.

local SEED = os.getenv('BPM_HL_SEED') or 'BPMTEST1'
local GAP = 0.08

wait_title()
milestone('title')
if not (G.F_PORTRAIT and love.system.getOS() == 'Android') then done() end

local pulses = {}
love.system.vibrate = function(seconds)
    pulses[#pulses + 1] = {at = G.TIMERS.REAL, seconds = seconds}
end

local function ms(p) return math.floor(p.seconds * 1000) end
local function power(p) return p.seconds * 1000 - ms(p) end

local function report(name)
    local closest, longest, total = 99, 0, 0
    for i, p in ipairs(pulses) do
        if i > 1 then closest = math.min(closest, p.at - pulses[i - 1].at) end
        longest = math.max(longest, ms(p))
        total = total + ms(p)
    end
    log(string.format('%s: %d pulses, %d ms in all, longest %d ms, closest %.3f s', name, #pulses, total, longest, closest))
    return closest, longest, total
end

local function set_option(choice)
    if G.FUNCS.change_haptic_level then G.FUNCS.change_haptic_level({to_key = choice}) end
    wait(0.2)
    pulses = {}
end

-- The pulse the option gives when picked, once the table is quiet.
local function sample(choice)
    wait(2)
    pulses = {}
    G.FUNCS.change_haptic_level({to_key = choice})
    return pulses[#pulses]
end

local function play_hand()
    local hands = G.GAME.current_round.hands_left
    for _, c in ipairs(best_hand()) do tap_node(c) wait(0.12) end
    tap_ui({id = 'play_button'})
    wait_until(function() return G.GAME.current_round.hands_left < hands end, 10, 'hand played')
    wait_until(function() return G.STATE == G.STATES.SELECTING_HAND and G.STATE_COMPLETE or G.STATE == G.STATES.ROUND_EVAL end, 40, 'hand scored')
    wait(0.5)
end

step('option', function()
    tap_ui({button = 'options'})
    settle_ui()
    tap_ui({button = 'settings'})
    settle_ui()
    check(find({id = 'haptic_level'}) ~= nil, 'the Game tab has the Haptic Feedback option')
    screen_check('haptic_option')
    shot('haptic_option')
    back()
    if G.OVERLAY_MENU then back() end
end)

step('a run', function()
    G.FUNCS.start_run(nil, {seed = SEED, stake = 1})
    wait_stage('RUN', 30)
    select_blind()
    wait_until(function() return G.STATE == G.STATES.SELECTING_HAND and G.STATE_COMPLETE end, 30, 'hand dealt')
    wait(1)
    -- Talisman keeps scores as its own big numbers.
    G.GAME.blind.chips = to_big and to_big(1e9) or 1e9
    G.GAME.current_round.hands_left = 8
end)

local levels = {{'Light', 2}, {'Medium', 3}, {'Strong', 4}}
local totals = {}
for _, level in ipairs(levels) do
    step(level[1], function()
        set_option(level[2])
        play_hand()
        local closest, longest, total = report(level[1])
        totals[level[1]] = {total = total, longest = longest}
        check(#pulses > 0, level[1] .. ': the hand is felt')
        check(closest >= GAP - 0.001, string.format('%s: pulses stay apart (%.3f s)', level[1], closest))
    end)
end

step('levels', function()
    check(totals.Strong.longest <= 40, 'Strong: no pulse over the old longest')
    if G.FUNCS.change_haptic_level then
        local light, medium, strong = sample(2), sample(3), sample(4)
        check(light and math.abs(power(light) - 0.25) < 0.01, 'Light: asks for a quarter of the power')
        check(medium and math.abs(power(medium) - 0.5) < 0.01, 'Medium: asks for half the power')
        check(strong and power(strong) < 0.01, 'Strong: leaves the power as it is')
        check(light and medium and strong and ms(light) < ms(medium) and ms(medium) < ms(strong), 'each level is longer than the last')
        check(strong and ms(strong) == 20, 'Strong: the old length')
    end
end)

step('off', function()
    set_option(1)
    check(G.SETTINGS.haptic_enabled == false or not G.FUNCS.change_haptic_level, 'Off: turns haptics off')
    if G.FUNCS.change_haptic_level then
        play_hand()
        check(#pulses == 0, 'Off: nothing felt, got ' .. #pulses)
    end
end)

done()
