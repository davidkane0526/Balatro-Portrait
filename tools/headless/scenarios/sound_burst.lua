-- #10: unlocks that come together play the same sound many times at once, and
-- once every copy of it is busy the sound thread makes another. A file the
-- thread cannot open crashed the game; now that one sound is skipped. Neither
-- may crash or stop the sound thread.
wait_stage('MAIN_MENU', 60)
wait_until(function() return G.MAIN_MENU_UI ~= nil end, 60, 'main menu UI')
wait(1)
for _ = 1, 3 do
    for _ = 1, 40 do play_sound('paper1', 1, 0.2) end
    frames(10)
end
for _ = 1, 20 do play_sound('cardSlide1', 1, 0.2) play_sound('generic1', 1, 0.2) end
play_sound('bpm_no_such_sound', 1, 0.2)
wait(2)
local thread = G.SOUND_MANAGER and G.SOUND_MANAGER.thread
check(thread ~= nil, 'the sound thread is there')
check(thread == nil or thread:getError() == nil, 'the sound thread did not fail: ' .. tostring(thread and thread:getError()))
check(thread == nil or thread:isRunning(), 'the sound thread is still running')
