-- Runs first in the official app, from the chunk the module swaps in for
-- conf.lua. It turns the game's own Lua into the portrait code with
-- patches/portrait-mobile, into portrait_game/ in the save folder, and the
-- module's loader hook takes the chunks from there. That way the module carries
-- the patches and never the game. It is redone only when the module or the game
-- changes.
--
-- Hunks match the way tools/patches.py matches them, minus the fuzz: a Play
-- update that only moves code applies as it is. One that changes a line the
-- patches touch leaves portrait_game/ empty, so the game runs as shipped, and
-- portrait_patch_error.txt says what happened.

local FOLDER = "portrait_game"
local ERROR_FILE = "portrait_patch_error.txt"

-- This chunk runs before love.conf, when LÖVE on Android can still have its
-- save folder on external storage (/sdcard/Android/data/...) once the system
-- has made that folder. The module's loader only reads the internal one, and
-- so does the game after its conf, so the built game goes there. Otherwise a
-- new build lands on the sdcard while the game keeps running the old one.
if love.filesystem._setAndroidSaveExternal then
    love.filesystem._setAndroidSaveExternal(false)
    love.filesystem.setIdentity(love.filesystem.getIdentity())
end

local function split_lines(data)
    local lines, count, pos = {}, 0, 1
    while pos <= #data do
        local stop = data:find("\n", pos, true) or #data
        count = count + 1
        lines[count] = data:sub(pos, stop)
        pos = stop + 1
    end
    return lines, count
end

local function parse_patch(text)
    local hunks, hunk = {}, nil
    local lines, count = split_lines(text)
    for i = 1, count do
        local line = lines[i]
        local start = line:match("^@@ %-(%d+)")
        if start then
            hunk = {start = tonumber(start), old = {}, new = {}}
            hunks[#hunks + 1] = hunk
        elseif hunk then
            local tag, rest = line:sub(1, 1), line:sub(2)
            if tag == "\\" then
                -- "No newline at end of file", about the line before it.
                local prev = lines[i - 1]:sub(1, 1)
                if prev ~= "+" then hunk.old[#hunk.old] = hunk.old[#hunk.old]:gsub("\n$", "") end
                if prev ~= "-" then hunk.new[#hunk.new] = hunk.new[#hunk.new]:gsub("\n$", "") end
            else
                if tag ~= "+" then hunk.old[#hunk.old + 1] = rest end
                if tag ~= "-" then hunk.new[#hunk.new + 1] = rest end
            end
        end
    end
    return hunks
end

local function matches(lines, pos, block)
    for i = 1, #block do
        if lines[pos + i - 1] ~= block[i] then return false end
    end
    return true
end

-- The place of `block` nearest to `expected`, not before `floor`.
local function find_block(lines, count, block, expected, floor)
    if #block == 0 then return math.min(math.max(expected, floor), count + 1) end
    local last = count - #block + 1
    local distance = 0
    while expected - distance >= floor or expected + distance <= last do
        for _, pos in ipairs({expected - distance, expected + distance}) do
            if pos >= floor and pos <= last and matches(lines, pos, block) then return pos end
        end
        distance = distance + 1
    end
end

local function apply_hunks(rel, data, hunks)
    local lines, count = split_lines(data)
    local out, size = {}, 0
    local drift, floor = 0, 1
    for number, hunk in ipairs(hunks) do
        local pos = find_block(lines, count, hunk.old, hunk.start + drift, floor)
        if not pos then error(rel .. ": hunk " .. number .. " (line " .. hunk.start .. ") finds no place", 0) end
        for i = floor, pos - 1 do
            size = size + 1
            out[size] = lines[i]
        end
        for _, line in ipairs(hunk.new) do
            size = size + 1
            out[size] = line
        end
        drift = pos - hunk.start
        floor = pos + #hunk.old
    end
    for i = floor, count do
        size = size + 1
        out[size] = lines[i]
    end
    return table.concat(out)
end

local function replace_all(data, find, replacement)
    local parts, pos = {}, 1
    while true do
        local first, last = data:find(find, pos, true)
        if not first then break end
        parts[#parts + 1] = data:sub(pos, first - 1)
        parts[#parts + 1] = replacement
        pos = last + 1
    end
    parts[#parts + 1] = data:sub(pos)
    return table.concat(parts)
end

local function remove_tree(path)
    for _, item in ipairs(love.filesystem.getDirectoryItems(path)) do
        local child = path .. "/" .. item
        if love.filesystem.getInfo(child, "directory") then remove_tree(child) end
        love.filesystem.remove(child)
    end
end

local function build(spec)
    local built = {}
    for rel, patch in pairs(spec.patches) do
        local data = love.filesystem.read(rel)
        if not data then error(rel .. " is not in this copy of the game", 0) end
        data = apply_hunks(rel, data:gsub("\r\n", "\n"), parse_patch(patch))
        for _, rule in ipairs(spec.rules[rel] or {}) do
            data = replace_all(data, rule[1], rule[2])
        end
        built[rel] = data
    end
    return built
end

local function write_tree(built, key)
    for rel, data in pairs(built) do
        local path = FOLDER .. "/" .. rel
        love.filesystem.createDirectory(path:match("^(.*)/[^/]+$"))
        assert(love.filesystem.write(path, data))
    end
    -- Last, so a run cut short is simply done over.
    assert(love.filesystem.write(FOLDER .. "/.version", key))
end

local function game_key(spec)
    local names = {}
    for rel in pairs(spec.patches) do names[#names + 1] = rel end
    table.sort(names)
    local key = {spec.version}
    for _, rel in ipairs(names) do
        local info = love.filesystem.getInfo(rel)
        key[#key + 1] = rel .. "=" .. tostring(info and info.size)
    end
    return table.concat(key, "\n")
end

local spec = require "portrait_game_patches"
local key = game_key(spec)
if love.filesystem.read(FOLDER .. "/.version") ~= key then
    remove_tree(FOLDER)
    local ok, result = pcall(build, spec)
    if ok then
        write_tree(result, key)
        love.filesystem.remove(ERROR_FILE)
    else
        print("portrait: " .. tostring(result))
        love.filesystem.write(ERROR_FILE, tostring(result) .. "\n")
    end
end

-- The game's conf.lua, patched when that worked. Under a name of its own: the
-- module swaps this very chunk in for conf.lua.
local conf = love.filesystem.read(FOLDER .. "/conf.lua") or love.filesystem.read("conf.lua")
assert(loadstring(conf, "@portrait_conf.lua"))()
