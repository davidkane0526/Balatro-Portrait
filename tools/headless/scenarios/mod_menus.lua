-- The title screen and the Mods screen's tabs, in a language (--lang) and with
-- Steamodded (--mods smods-26) on the phone sizes: long words ran Steamodded's
-- Config tab off both edges, and its version sat flush with the corner the CRT
-- curve bends away. The language box has to stay clear of the menu column too.

local EDGE = 0.4

wait_title(120)
wait(1)

local function gap_to_column(box, label)
    if not (box and box.T) then return end
    local menu = G.MAIN_MENU_UI.T
    local clear = box.T.x + box.T.w <= menu.x or box.T.x >= menu.x + menu.w
    check(clear, string.format('%s clear of the menu column (box %.2f-%.2f, column %.2f-%.2f)',
        label, box.T.x, box.T.x + box.T.w, menu.x, menu.x + menu.w))
end

step('title', function()
    if not G.F_PORTRAIT then return end
    screen_check('title')
    gap_to_column(G.LANGUAGE_BUTTON, 'language box')
    gap_to_column(G.PROFILE_BUTTON, 'profile box')
    for _, box in pairs(G.I.UIBOX or {}) do
        local root = box.UIRoot
        local text = root and root.children and root.children[1] and root.children[1].config.text
        if type(text) == 'string' and text:find('^Steamodded v') then
            local right = G.ROOM.T.w - (box.T.x + box.T.w)
            check(right >= EDGE, string.format('Steamodded version %.2f from the edge', right))
        end
    end
end)

if not SMODS then return end

step('mods screen', function()
    if not G.F_PORTRAIT then return end
    tap_ui({button = 'mods_button'})
    wait(2)
    local _, tabs = find({button = 'change_tab'})
    check(#tabs >= 3, 'the Mods screen has its tabs')
    for i = 1, #tabs do
        local _, now = find({button = 'change_tab'})
        tap_node(now[i])
        wait(1.5)
        shot('mods_tab' .. i)
        check(offscreen_check('mods_tab' .. i) == 0, 'Mods tab ' .. i .. ': nothing cut off')
        panel_margin_check('mods_tab' .. i)
    end
    back()
end)
