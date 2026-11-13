-- Steamodded on the portrait build (run with --mods): every mod loads, the
-- Mods button and mod list fit the phone, and in each layout style Steamodded's
-- play/discard limits show on the bar and work, through a played hand, Cash
-- Out and the shop. Without Steamodded loaded there is nothing to check.

local SEED = os.getenv('BPM_HL_SEED') or 'BPMTEST1'

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

wait_title(120)

if not SMODS then
    log('Steamodded is not loaded (run with --mods smods-...): nothing to check')
    return
end

step('mods loaded', function()
    log('Steamodded', tostring(SMODS.version), 'mods asked for:', tostring(os.getenv('BPM_HL_MODS')))
    for key, mod in pairs(SMODS.Mods or {}) do
        local ok = mod.can_load ~= false and not mod.disabled
        local why = mod.load_issues and (mod.load_issues.dependencies and table.concat(mod.load_issues.dependencies, ', ')
            or mod.load_issues.version_mismatch or mod.load_issues.main_file_not_found and 'main file not found') or ''
        log('mod', key, tostring(mod.version), ok and 'loaded' or ('NOT loaded ' .. tostring(why)))
        check(ok, 'mod ' .. key .. ' loaded' .. (ok and '' or (': ' .. tostring(why))))
    end
    milestone('mods loaded')
end)

step('mod list', function()
    if not G.F_PORTRAIT then return end
    check_on_screen({button = 'mods_button'}, 'Mods button on the title')
    tap_ui({button = 'mods_button'})
    settle(1)
    check(G.OVERLAY_MENU ~= nil, 'the Mods button opens the mod list')
    shot('mod_list')
    check(offscreen_check('mod_list') == 0, 'mod list: nothing cut off')
    back()
    settle()
end)

if not G.F_PORTRAIT then return end

for i, name in ipairs(PORTRAIT_LAYOUT_NAMES) do
    local tag = name:lower():gsub('%W', '')
    step('mods ' .. name, function()
        G.SETTINGS.portrait_layout = i
        G.FUNCS.start_run(nil, {stake = 1, seed = SEED})
        wait_state('BLIND_SELECT', 30)
        leak_check(name .. ' new run')

        -- An unlock popup (mods unlock decks on the way) is closed while waiting.
        wait_until(function() dismiss_popups() return find({button = 'select_blind'}) end, 20, 'blind choices')
        settle(1)
        screen_check(tag .. '_blind')
        select_blind()
        wait_until(function() return #G.hand.cards > 0 end, 15, 'cards in hand')
        settle(1)

        -- A mod raising the play limit to 7 and cutting the discard limit to 3.
        SMODS.change_play_limit(2)
        SMODS.change_discard_limit(-2)
        rebuild_buttons_uibox()
        wait(0.6)
        check(SMODS.hand_limit_strings.play ~= '', name .. ': play limit text set')
        check_on_screen({text = SMODS.hand_limit_strings.play}, name .. ': play limit on the bar')
        check_on_screen({text = SMODS.hand_limit_strings.discard}, name .. ': discard limit on the bar')
        frame_check(name)
        overlap_check(name)
        screen_check(tag .. '_limits')

        local before = G.GAME.current_round.hands_left
        G.GAME.chips = G.GAME.blind.chips - 1
        G.hand:unhighlight_all()
        for k = 1, math.min(7, #G.hand.cards) do tap_node(G.hand.cards[k]) wait(0.12) end
        wait(0.4)
        check(#G.hand.highlighted == math.min(7, #G.hand.cards), name .. ': seven cards selected under the raised limit')
        shot(tag .. '_seven_selected')
        tap_ui({id = 'play_button'})
        wait_until(function() return G.GAME.current_round.hands_left < before end, 10, 'Play plays seven')
        check(true, name .. ': a seven-card hand plays')

        wait_state('ROUND_EVAL', 60)
        wait_until(function() return find({button = 'cash_out'}) end, 30, 'cash out button')
        settle(1)
        check(offscreen_check(tag .. '_round_eval') == 0, name .. ': round end, nothing cut off')
        tap_ui({button = 'cash_out'})
        wait_until(function()
            return state_is('SHOP') and find({id = 'next_round_button'}) and G.shop_jokers and #G.shop_jokers.cards > 0
        end, 30, 'shop stocked')
        settle(1)
        check_on_screen({id = 'next_round_button'}, name .. ': Next Round')
        check(offscreen_check(tag .. '_shop') == 0, name .. ': shop, nothing cut off')
        shot(tag .. '_shop')

        SMODS.change_play_limit(-2)
        SMODS.change_discard_limit(2)
    end)
end
