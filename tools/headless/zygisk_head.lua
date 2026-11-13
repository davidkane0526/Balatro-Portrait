-- Goes in front of the module's chunk for --source zygisk. Each job's save
-- folder is set before the chunk runs: it writes the game's code there, and
-- parallel jobs must not write over each other.
love.filesystem.setIdentity(os.getenv('BPM_HL_IDENTITY') or 'balatro-portrait-headless', true)

-- On a phone the swap happens as the chunk loads, and conf.lua on disk stays the
-- game's. This stage has to overwrite it, so the game's is kept under a name of
-- its own and read from there.
local bpm_read = love.filesystem.read
love.filesystem.read = function(name, ...)
    return bpm_read(name == 'conf.lua' and 'bpm_play_conf.lua' or name, ...)
end
BPM_RESTORE_READ = function() love.filesystem.read = bpm_read end
