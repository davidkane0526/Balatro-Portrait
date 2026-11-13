-- Every menu reachable from the title screen, by touch: options and each of
-- its tabs, the portrait Diagnostics screen, every Collection page, profile
-- and language pickers, and the run setup tabs. Each screen gets a
-- screenshot and the layout checks. Run it per language with --lang.

local function tap_tabs(tag)
    local _, tabs = find({button = 'change_tab'})
    for i = 1, #tabs do
        step(tag .. ' tab ' .. i, function()
            local _, now_tabs = find({button = 'change_tab'})
            if not now_tabs[i] then return end
            tap_node(now_tabs[i])
            settle_ui()
            screen_check(tag .. '_tab' .. i)
        end)
    end
end

wait_title()
milestone('title')
screen_check('title')

step('frame rate', function()
    if not (G.F_PORTRAIT and love.system.getOS() == 'Android') then return end
    for choice, cap in ipairs({false, 60, 30}) do
        G.FUNCS.change_portrait_fps({to_key = choice})
        frames(2)
        check(not cap or G.FPS_CAP == cap, 'frame rate option ' .. choice .. ' sets the cap')
    end
    G.FUNCS.change_portrait_fps({to_key = 1})
end)

step('options', function()
    tap_ui({button = 'options'})
    settle_ui()
    screen_check('options')
    milestone('options')

    step('settings', function()
        tap_ui({button = 'settings'})
        settle_ui()
        screen_check('settings')
        tap_tabs('settings')
        back()
    end)

    step('support', function()
        if not G.OVERLAY_MENU then
            tap_ui({button = 'options'})
            settle_ui()
        end
        check_on_screen({button = 'open_portrait_support'}, 'Support button')
        -- Stands in for the browser, which must not open during a run.
        local opened
        local open_url = love.system.openURL
        love.system.openURL = function(url) opened = url end
        tap_ui({button = 'open_portrait_support'})
        wait(0.2)
        love.system.openURL = open_url
        check(opened == 'https://www.patreon.com/loreanxavier', 'Support opens the Patreon page: ' .. tostring(opened))
        milestone('support')
    end)

    step('diagnostics', function()
        if not G.OVERLAY_MENU then
            tap_ui({button = 'options'})
            settle_ui()
        end
        tap_ui({button = 'open_portrait_diagnostics'})
        settle_ui()
        screen_check('diagnostics')
        check(find({button = 'copy_portrait_diagnostics'}) ~= nil, 'Diagnostics has its copy button')
        milestone('diagnostics')
        back()
    end)
    back()
end)

step('collection', function()
    tap_ui({id = 'collection_button'})
    settle_ui()
    screen_check('collection')
    milestone('collection')
    local pages = {'jokers', 'decks', 'vouchers', 'tarots', 'planets', 'spectrals',
                   'enhancements', 'seals', 'editions', 'boosters', 'tags', 'blinds'}
    -- With mods adding card types, Steamodded groups the consumables behind
    -- one Consumables button (and adds an Other page): opened on the way.
    local CONSUMABLE = {tarots = true, planets = true, spectrals = true}
    if find({button = 'your_collection_other_gameobjects'}) then pages[#pages + 1] = 'other_gameobjects' end
    for _, page in ipairs(pages) do
        step('collection ' .. page, function()
            if not find({button = 'your_collection_' .. page}) then
                back()
                tap_ui({id = 'collection_button'})
                settle_ui()
            end
            if CONSUMABLE[page] and not find({button = 'your_collection_' .. page}) and find({button = 'your_collection_consumables'}) then
                tap_ui({button = 'your_collection_consumables'})
                settle_ui()
                screen_check('collection_consumables')
            end
            tap_ui({button = 'your_collection_' .. page})
            settle_ui()
            screen_check('collection_' .. page)
            -- Back to the collection index, not all the way out.
            local back_btn = find({button = 'your_collection'})
            if back_btn then tap_node(back_btn) settle_ui() else back() end
        end)
    end
    back()
end)

step('profile', function()
    tap_ui({button = 'profile_select'})
    settle_ui()
    screen_check('profile')
    milestone('profile')
    back()
end)

step('language', function()
    tap_ui({button = 'language_selection'})
    settle_ui()
    screen_check('language')
    milestone('language')
    back()
end)

step('run setup', function()
    tap_ui({id = 'main_menu_play'})
    settle_ui()
    screen_check('run_setup')
    -- Steamodded's own run select: its second page (the stakes) too.
    if find({id = 'next_selection'}) then
        tap_ui({id = 'next_selection'})
        settle_ui()
        screen_check('run_select_page2')
        local prev = find({id = 'previous_selection'})
        if prev then tap_node(prev) settle_ui() end
    end
    tap_tabs('run_setup')
    milestone('run setup')
    back()
end)

wait(0.5)
check(G.STAGE == G.STAGES.MAIN_MENU and not G.OVERLAY_MENU, 'back on the title screen with no menu left open')
screen_check('title_end')
