-- Bardcraft sound records (explicit version)
local bardcraft = {}
bardcraft.sounds = {}
bardcraft.sounds.records = {}
bardcraft.sounds.refIds = {}

-- Helper function to add a sound record
local function addSound(instrument, note)
    local refId = instrument .. "_" .. note
    local filePath = "Bardcraft/samples/" .. instrument .. "/" .. instrument .. "_" .. note .. ".flac"

    bardcraft.sounds.refIds[refId] = refId
    bardcraft.sounds.records[refId] = {
        type = "sound",
        data = {
            sound = filePath
        }
    }
end

-- BassFlute sounds
local bassFluteNotes = {
    "A2", "A3", "A4", "A5", "Ab2", "Ab3", "Ab4", "Ab5",
    "B2", "B3", "B4", "Bb2", "Bb3", "Bb4",
    "C2", "C3", "C4", "C5",
    "D2", "D3", "D4", "D5", "Db2", "Db3", "Db4", "Db5",
    "E2", "E3", "E4", "E5", "Eb2", "Eb3", "Eb4", "Eb5",
    "F2", "F3", "F4", "F5",
    "G2", "G3", "G4", "G5", "Gb2", "Gb3", "Gb4", "Gb5"
}
for _, note in ipairs(bassFluteNotes) do
    addSound("BassFlute", note)
end

-- Drum sounds
local drumNotes = {
    "A2", "Ab2", "B2", "Bb2", "C2", "C3",
    "D2", "D3", "Db2", "Db3",
    "E2", "Eb2", "Eb3",
    "F2", "G2", "Gb2"
}
for _, note in ipairs(drumNotes) do
    addSound("Drum", note)
end

-- Fiddle sounds
local fiddleNotes = {
    "A3", "A4", "A5", "A6", "Ab3", "Ab4", "Ab5", "Ab6",
    "B3", "B4", "B5", "B6", "Bb3", "Bb4", "Bb5", "Bb6",
    "C3", "C4", "C5", "C6", "C7",
    "D3", "D4", "D5", "D6", "Db3", "Db4", "Db5", "Db6",
    "E3", "E4", "E5", "E6", "Eb3", "Eb4", "Eb5", "Eb6",
    "F3", "F4", "F5", "F6",
    "G3", "G4", "G5", "G6", "Gb3", "Gb4", "Gb5", "Gb6"
}
for _, note in ipairs(fiddleNotes) do
    addSound("Fiddle", note)
end

-- Lute sounds
local luteNotes = {
    "A1", "A2", "A3", "A4", "A5", "A6", "Ab1", "Ab2", "Ab3", "Ab4", "Ab5", "Ab6",
    "B1", "B2", "B3", "B4", "B5", "B6", "Bb1", "Bb2", "Bb3", "Bb4", "Bb5", "Bb6",
    "C2", "C3", "C4", "C5", "C6", "C7",
    "D2", "D3", "D4", "D5", "D6", "D7", "Db2", "Db3", "Db4", "Db5", "Db6", "Db7",
    "E1", "E2", "E3", "E4", "E5", "E6", "Eb2", "Eb3", "Eb4", "Eb5", "Eb6",
    "F1", "F2", "F3", "F4", "F5", "F6",
    "G1", "G2", "G3", "G4", "G5", "G6", "Gb1", "Gb2", "Gb3", "Gb4", "Gb5", "Gb6"
}
for _, note in ipairs(luteNotes) do
    addSound("Lute", note)
end

-- MusicBox sounds
local musicBoxNotes = {
    "A2", "A3", "A4", "A5", "A6", "Ab2", "Ab3", "Ab4", "Ab5", "Ab6",
    "B2", "B3", "B4", "B5", "B6", "Bb2", "Bb3", "Bb4", "Bb5", "Bb6",
    "C2", "C3", "C4", "C5", "C6", "C7",
    "D2", "D3", "D4", "D5", "D6", "Db2", "Db3", "Db4", "Db5", "Db6",
    "E2", "E3", "E4", "E5", "E6", "Eb2", "Eb3", "Eb4", "Eb5", "Eb6",
    "F2", "F3", "F4", "F5", "F6",
    "G2", "G3", "G4", "G5", "G6", "Gb2", "Gb3", "Gb4", "Gb5", "Gb6"
}
for _, note in ipairs(musicBoxNotes) do
    addSound("MusicBox", note)
end

-- Ocarina sounds
local ocarinaNotes = {
    "A3", "A4", "A5", "A6", "Ab3", "Ab4", "Ab5", "Ab6",
    "B3", "B4", "B5", "B6", "Bb3", "Bb4", "Bb5", "Bb6",
    "C4", "C5", "C6", "C7",
    "D4", "D5", "D6", "D7", "Db4", "Db5", "Db6", "Db7",
    "E4", "E5", "E6", "E7", "Eb4", "Eb5", "Eb6", "Eb7",
    "F4", "F5", "F6",
    "G3", "G4", "G5", "G6", "Gb4", "Gb5", "Gb6"
}
for _, note in ipairs(ocarinaNotes) do
    addSound("Ocarina", note)
end

return bardcraft
