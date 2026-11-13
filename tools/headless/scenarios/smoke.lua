-- Default run: title screen -> new run -> blind -> play a hand -> discard,
-- by touch, the way a phone would, checking the portrait layout on the way.
local want_w, want_h = tonumber(os.getenv('BPM_HL_W')), tonumber(os.getenv('BPM_HL_H'))
local portrait = want_h > want_w

wait_title()
wait(0.5)
check(screen().width == want_w and screen().height == want_h,
    string.format('window is %dx%d (asked for %dx%d)', screen().width, screen().height, want_w, want_h))
check(G.F_PORTRAIT == portrait, 'portrait flag matches the window shape')
check_on_screen({id = 'main_menu_play'}, 'title PLAY button')
shot('title')
layout_report('title')

-- Title PLAY opens the run setup (deck and stake) when there is a profile to
-- pick from; its own PLAY starts the run.
tap_ui({id = 'main_menu_play'})
wait(1.5)
if find({button = 'start_setup_run'}) then
    shot('run_setup')
    layout_report('run_setup')
    tap_ui({button = 'start_setup_run'})
elseif find({button = 'run_select_quick_start'}) then
    -- Steamodded's own run select, which it uses whenever a mod adds a page
    -- to it (Cryptid does). Recorded for the layout, then quick-started.
    shot('run_select')
    check(offscreen_check('run_select') == 0, "Steamodded's run select: nothing cut off")
    tap_ui({button = 'run_select_quick_start'})
end

wait_state('BLIND_SELECT', 30)
wait_until(function() dismiss_popups() return find({button = 'select_blind'}) end, 20, 'blind choices')
wait(1.5)
check_on_screen({button = 'select_blind'}, 'select blind button')
shot('blind_select')
layout_report('blind_select')
tap_ui({button = 'select_blind'})

wait_state('SELECTING_HAND', 30)
wait_until(function() return G.hand and #G.hand.cards >= 5 end, 15, 'a dealt hand')
wait(2)
check(#G.hand.cards == G.hand.config.card_limit, 'full hand dealt (' .. #G.hand.cards .. ')')
for i, card in ipairs(G.hand.cards) do
    local ok, where = on_screen(card)
    if not ok then check(false, 'hand card ' .. i .. ' on screen ' .. where) end
end
check_on_screen({id = 'play_button'}, 'Play hand button')
check_on_screen({id = 'discard_button'}, 'Discard button')
shot('hand')
layout_report('hand')

-- Select the first three cards by tapping them, then play.
local before = G.GAME.chips
for i = 1, 3 do tap_node(G.hand.cards[i]) end
wait(0.5)
check(#G.hand.highlighted == 3, 'three cards selected by touch (' .. #G.hand.highlighted .. ')')
shot('selected')
tap_ui({id = 'play_button'})
wait_until(function() return G.STATE == G.STATES.HAND_PLAYED end, 15, 'hand being scored')
wait_state('SELECTING_HAND', 30)
check(G.GAME.chips > before, 'played hand scored (' .. tostring(G.GAME.chips) .. ' chips)')
wait(1.5)
shot('after_play')

-- Discard two cards.
local discards = G.GAME.current_round.discards_left
for i = 1, 2 do tap_node(G.hand.cards[i]) end
wait(0.4)
tap_ui({id = 'discard_button'})
wait_until(function() return G.GAME.current_round.discards_left < discards end, 15, 'discard used')
check(G.GAME.current_round.discards_left == discards - 1, 'discard went through')
wait_state('SELECTING_HAND', 30)
wait(1.5)
shot('after_discard')
layout_report('after_discard')
