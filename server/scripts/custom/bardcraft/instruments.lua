--[[
Bardcraft Instruments
Defines instrument animations and behaviors
]]

local instruments = {}

-- Instrument profiles define sound characteristics
instruments.profiles = {
    Lute = {
        name = "Lute",
        sustain = false,
        densityMod = 1.0,
        midiProgram = 24, -- Acoustic Guitar (nylon)
    },
    Drum = {
        name = "Drum",
        sustain = false,
        densityMod = 1.5,
        midiProgram = 0, -- Drum kit (channel 10)
        isDrum = true,
    },
    Fiddle = {
        name = "Fiddle",
        sustain = true,
        densityMod = 1.0,
        midiProgram = 40, -- Violin
    },
    Ocarina = {
        name = "Ocarina",
        sustain = true,
        densityMod = 0.8,
        midiProgram = 79, -- Ocarina
    },
    BassFlute = {
        name = "BassFlute",
        sustain = true,
        densityMod = 0.8,
        midiProgram = 73, -- Flute
    },
}

-- Animation data for each instrument
instruments.animations = {
    Lute = {
        main = "bolute", -- Base animation group
        strum = "bolute_strum",
        strumAlt = "bolute_strumalt",
        fret = { "bolute_fret1", "bolute_fret2", "bolute_fret3", "bolute_fret4" },
    },
    Drum = {
        main = "bodrum",
        hitLeft = "bodrum_hitl",
        hitRight = "bodrum_hitr",
        roll = "bodrum_roll",
    },
    Fiddle = {
        main = "bcfiddle",
        bow = "bcfiddle_bow",
        bowAlt = "bcfiddle_bowalt",
        finger = { "bcfiddle_fin1", "bcfiddle_fin2", "bcfiddle_fin3" },
    },
    Ocarina = {
        main = "boocarina",
        notes = { "boocarina_note1", "boocarina_note2", "boocarina_note3", "boocarina_note4", "boocarina_note5" },
    },
    BassFlute = {
        main = "boflute",
        notes = { "boflute_note1", "boflute_note2", "boflute_note3", "boflute_note4", "boflute_note5" },
    },
}

-- Drum note mappings (MIDI note to drum sound)
instruments.drumMappings = {
    [46] = "hitLeft",  -- Open Hi-Hat
    [47] = "hitRight", -- Low-Mid Tom
    [48] = "hitLeft",  -- Hi-Mid Tom
    [49] = "hitRight", -- Crash Cymbal 1
    [50] = "roll",     -- High Tom
    [51] = "hitLeft",  -- Ride Cymbal 1
}

-- -- Get instrument type from item ID
-- function instruments.GetInstrumentType(itemId)
--     local data = require("custom.bardcraft.data")
--     for instrumentType, items in pairs(data.INSTRUMENT_ITEMS) do
--         if items[itemId] then
--             return instrumentType
--         end
--     end
--     return nil
-- end

-- Get animation for note event
function instruments.GetNoteAnimation(instrumentType, note, lastNote, lastAnim)
    local anims = instruments.animations[instrumentType]
    if not anims then return nil end

    if instrumentType == "Lute" then
        -- Alternate between strum and strumAlt
        if lastAnim == anims.strumAlt then
            return anims.strum
        else
            return anims.strumAlt
        end
    elseif instrumentType == "Drum" then
        -- Map MIDI note to drum animation
        local drumType = instruments.drumMappings[note]
        if drumType == "hitLeft" then
            return anims.hitLeft
        elseif drumType == "hitRight" then
            return anims.hitRight
        elseif drumType == "roll" then
            return anims.roll
        end
        return anims.hitRight -- Default
    elseif instrumentType == "Fiddle" then
        -- Alternate bow direction
        if lastAnim == anims.bowAlt then
            return anims.bow
        else
            return anims.bowAlt
        end
    elseif instrumentType == "Ocarina" or instrumentType == "BassFlute" then
        -- Cycle through fingering animations based on note
        local index = (note % 5) + 1
        return anims.notes[index]
    end

    return anims.main
end

return instruments
