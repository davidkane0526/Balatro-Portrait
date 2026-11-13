-- Lovely reads a folder the save folder's love.filesystem cannot write to, the
-- way it reads ASET/Mods on Android. The folder here is a stand-in on the same
-- drive, as ASET/Mods is on a phone. Mods from older builds in the save folder's
-- Mods/ and mods bundled with the build must end up where Lovely reads them,
-- without losing what is there already.
love.filesystem.createDirectory('stand_in_ASET/Mods/lovely')
local mod_dir = love.filesystem.getSaveDirectory():gsub('\\', '/') .. '/stand_in_ASET/Mods'
package.loaded.lovely = {mod_dir = mod_dir}

local function read(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read('*a')
    f:close()
    return data
end

local function write(path, text)
    local f = assert(io.open(path, 'wb'))
    f:write(text)
    f:close()
end

wait_title()

-- A build from before the move left these behind.
love.filesystem.createDirectory('Mods/OldMod/assets')
love.filesystem.write('Mods/OldMod/old.lua', 'old mod')
love.filesystem.write('Mods/OldMod/assets/a.txt', 'nested')
love.filesystem.createDirectory('Mods/lovely')
love.filesystem.write('Mods/lovely/blacklist.txt', 'OldMod')
love.filesystem.write('Mods/loose.txt', 'old loose file')
write(mod_dir .. '/loose.txt', 'already in place')

love.filesystem.createDirectory('install_mods/Bundled')
love.filesystem.write('install_mods/Bundled/one.lua', 'version one')

PORTRAIT_SYNC_MODS()

check(read(mod_dir .. '/OldMod/old.lua') == 'old mod', 'old mod moved')
check(read(mod_dir .. '/OldMod/assets/a.txt') == 'nested', 'its subfolders moved')
check(read(mod_dir .. '/lovely/blacklist.txt') == 'OldMod', 'disabled list merged into a folder that exists')
check(read(mod_dir .. '/loose.txt') == 'already in place', 'a file already in place is kept')
check(read(mod_dir .. '/Bundled/one.lua') == 'version one', 'bundled mod installed')
check(read(mod_dir .. '/Bundled/.portrait_bundle') ~= nil, 'bundled mod records its build')
check(not love.filesystem.getInfo('Mods/OldMod'), 'nothing of the old mod left behind')
check(not love.filesystem.getInfo('Mods/Bundled'), 'nothing of the bundled mod left behind')

-- Same bundle again: a change made since must survive.
write(mod_dir .. '/Bundled/user_edit.txt', 'mine')
PORTRAIT_SYNC_MODS()
check(read(mod_dir .. '/Bundled/user_edit.txt') == 'mine', 'same bundle is not installed twice')

-- Another bundle: the old one is replaced as a whole, as it was before.
love.filesystem.write('install_mods/Bundled/one.lua', 'version two, longer')
love.filesystem.write('install_mods/Bundled/two.lua', 'new file')
PORTRAIT_SYNC_MODS()
check(read(mod_dir .. '/Bundled/one.lua') == 'version two, longer', 'new bundle replaces the old')
check(read(mod_dir .. '/Bundled/two.lua') == 'new file', 'new bundle adds its files')
check(read(mod_dir .. '/Bundled/user_edit.txt') == nil, 'old bundle is gone as a whole')
check(not love.filesystem.getInfo('Mods/.old_Bundled'), 'old bundle left nothing in the save folder')

-- Someone following the old instructions drops a mod in the old place.
love.filesystem.createDirectory('Mods/LateMod')
love.filesystem.write('Mods/LateMod/late.lua', 'late')
PORTRAIT_SYNC_MODS()
check(read(mod_dir .. '/LateMod/late.lua') == 'late', 'a mod put in the old place is carried over')
