-- The profile name field, on a phone's own keyboard. The menu lifts while the
-- keyboard is up and must come back down however the keyboard goes away: Enter,
-- the system closing it (the chevron under Gboard, a back swipe), or a tap
-- beside the field when nothing told the game it closed.

local function field() return find({button = 'select_text_input'}) end
local function hook() return G.CONTROLLER.text_input_hook end
local function lift() return G.OVERLAY_MENU and G.OVERLAY_MENU.portrait_keyboard_lift end

local function open_keyboard(name)
    tap_node(field())
    wait(0.3)
    check(hook() ~= nil, name .. ': field takes the text')
    check(lift() ~= nil, name .. ': menu lifts over the keyboard')
    check(love.keyboard.hasTextInput(), name .. ': keyboard asked for')
end

local function closed(name)
    wait(0.3)
    check(hook() == nil, name .. ': field lets go')
    check(lift() == nil, name .. ': menu back down')
    check(not love.keyboard.hasTextInput(), name .. ': keyboard not asked for')
end

wait_title()
milestone('title')
if not (G.F_PORTRAIT and love.system.getOS() ~= 'Windows') then done() end

tap_ui({button = 'profile_select'})
settle_ui()
local top = G.OVERLAY_MENU.T.y

step('enter', function()
    open_keyboard('enter')
    shot('keyboard_open')
    key('return')
    closed('enter')
end)

step('system closes it', function()
    open_keyboard('system')
    G.CONTROLLER:key_press_update('A')
    wait(0.1)
    local name = G.PROFILES[G.SETTINGS.profile].name
    love.keyboard.setTextInput(false)
    closed('system')
    check(G.PROFILES[G.SETTINGS.profile].name == name, 'system: typed text stays')
    wait(0.6)
    shot('keyboard_closed')
    check(math.abs(G.OVERLAY_MENU.T.y - top) < 0.05, 'system: menu where it started')
end)

step('tap beside the field', function()
    open_keyboard('tap')
    local w, h = love.graphics.getDimensions()
    tap(w / 2, h - 8)
    closed('tap')
end)

step('tap on the field', function()
    open_keyboard('field')
    tap_node(field())
    wait(0.3)
    check(hook() ~= nil, 'field: a second tap keeps the text going')
    check(lift() ~= nil, 'field: menu stays up')
    key('return')
    closed('field')
end)

step('opens again', function()
    open_keyboard('again')
    love.keyboard.setTextInput(false)
    closed('again')
end)

screen_check('keyboard_done')
back()
done()
