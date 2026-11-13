-- Quickest check: the game boots to the title screen without crashing.
wait_stage('MAIN_MENU', 60)
wait_until(function() return G.MAIN_MENU_UI ~= nil end, 60, 'main menu UI')
wait(3)
local want_w, want_h = tonumber(os.getenv('BPM_HL_W')), tonumber(os.getenv('BPM_HL_H'))
check(screen().width == want_w and screen().height == want_h,
    string.format('window is %dx%d (asked for %dx%d)', screen().width, screen().height, want_w, want_h))
check(G.F_PORTRAIT == (screen().height > screen().width), 'portrait flag matches the window shape')
shot('title')
layout_report('title')
