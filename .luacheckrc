-- Luacheck config tuned for this repo: a local src/ is largely vanilla Balatro
-- code that we deliberately do not restyle (smaller patches), so
-- style/whitespace/shadowing/unused classes are off. What stays on is the
-- class that catches real bugs in new portrait code: undefined globals
-- (W111/112/113) plus undefined love fields (W143).
std = "luajit+love"
allow_defined = true
max_line_length = false

exclude_files = {
    "src/localization/**",  -- extracted from the game, not ours
    "src/resources/**",
    "desktop_test/**",
    "balatro-mobile-maker/**",
    ".headless/**",
    "zygisk/deps/**",
}

ignore = {
    "131",  -- implicitly defined global unused in checked files (G.FUNCS-style dispatch)
    "2..",  -- unused variables/arguments (vanilla noise)
    "3..",  -- unused assignments (vanilla noise)
    "4..",  -- shadowing (vanilla noise)
    "5..",  -- control-flow style (vanilla noise)
    "6..",  -- whitespace (vanilla noise)
}

-- Steamodded defines this when installed. It is writable rather than read-only
-- because portrait installs its Collection page-size hook into it (see
-- portrait_hook_smods_collection in src/portrait_config.lua).
globals = {
    "SMODS",
    -- The game's own globals. Its code is not in the repository, so nothing
    -- here defines them; portrait code reads them and hooks some of them.
    "G", "Game", "UIBox", "PORTRAIT_SORT_STATE",
}

read_globals = {
    "CardArea", "DynaText", "Moveable", "create_UIBox_HUD_blind", "create_UIBox_HUD_vertical",
    "create_UIBox_hand_preview", "darken", "get_stake_sprite", "localize", "prep_draw",
    "scale_number", "utf8",
}

files = {
    -- Nil-guarded reads that upstream game code does on purpose; keep the
    -- ignores narrow (per variable, per file) so new typos still get caught.
    ["src/engine/animatedsprite.lua"] = {ignore = {"113/k"}},
    ["src/engine/ui.lua"] = {ignore = {"113/dt"}},
    ["src/functions/UI_definitions.lua"] = {ignore = {
        "113/maxw", "113/badges", "113/disabled", "113/target", "113/show_win_cta",
    }},
    -- The boot screen fit swaps love.graphics.print for the length of one call
    -- so an overlong status line can be squeezed to the window, and puts the
    -- real one back straight after. Writing into the love table is what 122
    -- flags, and it is deliberate here. 143 covers love._os, which is set by
    -- LOVE before conf.lua runs (love.system is not loaded yet at that point)
    -- but is not part of luacheck's love standard.
    ["src/conf.lua"] = {ignore = {"122/love", "143"}},
    -- The mobile LOVE fork adds APIs luacheck's love standard doesn't know
    -- (window.setHint, handlers table access, graphics.isCreated).
    ["src/main.lua"] = {ignore = {"143"}},
    ["src/functions/misc_functions.lua"] = {ignore = {"143"}},
}
