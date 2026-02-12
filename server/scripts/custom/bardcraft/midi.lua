--[[
Bardcraft MIDI Parser
Full MIDI file parser for TES3MP - ported from OpenMW Lua version

Supports:
- Note on/off events
- Program changes (instrument changes)
- Tempo changes
- Time signatures
- Variable-length quantities
- Multiple tracks
]]

local midi = {}

local logger = require("custom.bardcraft.logger")

-- Loaded songs
midi.songs = {}
midi.songsByName = {}

-- Basic bit operations since Lua 5.1 doesn't have them built-in
local bit = {}

function bit.lshift(x, by)
    return x * 2 ^ by
end

function bit.rshift(x, by)
    return math.floor(x / 2 ^ by)
end

function bit.band(a, b)
    local result = 0
    local bitval = 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then
            result = result + bitval
        end
        bitval = bitval * 2
        a = math.floor(a / 2)
        b = math.floor(b / 2)
    end
    return result
end

function bit.bor(a, b)
    local result = 0
    local bitval = 1
    while a > 0 or b > 0 do
        if a % 2 == 1 or b % 2 == 1 then
            result = result + bitval
        end
        bitval = bitval * 2
        a = math.floor(a / 2)
        b = math.floor(b / 2)
    end
    return result
end

-- MIDI Parser class
local MidiParser = {}
MidiParser.__index = MidiParser

function MidiParser.new(filename)
    local self = setmetatable({}, MidiParser)
    self.filename = filename
    self.tracks = {}
    self.format = 0
    self.numTracks = 0
    self.division = 0
    self.events = {}
    self.tempoEvents = {}
    self.timeSignatureEvents = {}
    self.instruments = {}
    return self
end

-- Read variable-length quantity from a string buffer
function MidiParser:readVLQ(content, cursor, contentLength)
    local value = 0
    if cursor > contentLength then return nil, cursor, "EOF before reading VLQ byte" end
    local byte = content:byte(cursor)
    cursor = cursor + 1
    value = bit.band(byte, 0x7F)

    while bit.band(byte, 0x80) ~= 0 do
        if cursor > contentLength then return nil, cursor, "EOF in VLQ continuation byte" end
        byte = content:byte(cursor)
        cursor = cursor + 1
        value = bit.lshift(value, 7)
        value = bit.bor(value, bit.band(byte, 0x7F))
    end

    return value, cursor
end

-- Read a specific number of bytes from string buffer and return as number
function MidiParser:readBytes(content, cursor, count, contentLength)
    if cursor + count - 1 > contentLength then
        return nil, cursor, "EOF trying to read " .. count .. " bytes"
    end

    local value = 0
    for i = 1, count do
        value = bit.lshift(value, 8)
        value = value + content:byte(cursor)
        cursor = cursor + 1
    end
    return value, cursor
end

-- Parse a MIDI file
function MidiParser:parse()
    local file = io.open(self.filename, "rb")
    if not file then
        return false, "Could not open file: " .. self.filename
    end

    local content = file:read("*a")
    file:close()

    local contentLength = #content
    local cursor = 1
    local errMsg

    -- Read header chunk
    if cursor + 3 > contentLength then return false, "Unexpected EOF reading header chunk ID" end
    local headerChunk = content:sub(cursor, cursor + 3)
    cursor = cursor + 4
    if headerChunk ~= "MThd" then
        return false, "Not a valid MIDI file (header not found)"
    end

    -- Read header length
    local headerLength
    headerLength, cursor, errMsg = self:readBytes(content, cursor, 4, contentLength)
    if errMsg then return false, "Error reading header length: " .. errMsg end
    if headerLength ~= 6 then
        return false, "Invalid header length"
    end

    -- Read format type
    self.format, cursor, errMsg = self:readBytes(content, cursor, 2, contentLength)
    if errMsg then return false, "Error reading format type: " .. errMsg end

    -- Read number of tracks
    self.numTracks, cursor, errMsg = self:readBytes(content, cursor, 2, contentLength)
    if errMsg then return false, "Error reading number of tracks: " .. errMsg end

    -- Read time division
    self.division, cursor, errMsg = self:readBytes(content, cursor, 2, contentLength)
    if errMsg then return false, "Error reading time division: " .. errMsg end

    -- Process each track
    for trackNum = 1, self.numTracks do
        local track = { events = {} }

        -- Check for track header
        if cursor + 3 > contentLength then return false, "Unexpected EOF reading track header ID for track " .. trackNum end
        local trackHeader = content:sub(cursor, cursor + 3)
        cursor = cursor + 4
        if trackHeader ~= "MTrk" then
            return false, "Invalid track header in track " .. trackNum
        end

        -- Read track length
        local trackLength
        trackLength, cursor, errMsg = self:readBytes(content, cursor, 4, contentLength)
        if errMsg then return false, "Error reading track length for track " .. trackNum .. ": " .. errMsg end

        local trackDataStartCursor = cursor
        local trackEndLimit = trackDataStartCursor + trackLength

        local absoluteTime = 0
        local runningStatus = 0

        while cursor < trackEndLimit and cursor <= contentLength do
            local event = {}

            local deltaTime
            deltaTime, cursor, errMsg = self:readVLQ(content, cursor, contentLength)
            if errMsg then
                return false,
                    "Error reading delta time in track " .. trackNum .. " at cursor " .. (cursor - 1) .. ": " .. errMsg
            end
            absoluteTime = absoluteTime + deltaTime
            event.time = absoluteTime

            if cursor > contentLength then return false, "Unexpected EOF reading status byte in track " .. trackNum end
            local statusByte = content:byte(cursor)

            if statusByte < 0x80 then -- Running status
                if runningStatus == 0 then
                    return false,
                        "Invalid running status (0) with data byte in track " .. trackNum
                end
                statusByte = runningStatus
            else
                cursor = cursor + 1
                runningStatus = statusByte
            end

            local eventType = bit.rshift(statusByte, 4)
            local channel = bit.band(statusByte, 0x0F)
            event.channel = channel

            if eventType == 0x8 then -- Note Off
                event.type = "noteOff"
                if cursor + 1 > contentLength then return false, "Unexpected EOF for Note Off data in track " .. trackNum end
                event.note = content:byte(cursor)
                event.velocity = content:byte(cursor + 1)
                cursor = cursor + 2
                table.insert(track.events, event)
            elseif eventType == 0x9 then -- Note On
                event.type = "noteOn"
                if cursor + 1 > contentLength then return false, "Unexpected EOF for Note On data in track " .. trackNum end
                event.note = content:byte(cursor)
                event.velocity = content:byte(cursor + 1)
                cursor = cursor + 2
                if event.velocity == 0 then event.type = "noteOff" end
                table.insert(track.events, event)
            elseif eventType == 0xC then -- Program Change
                event.type = "programChange"
                if cursor > contentLength then
                    return false,
                        "Unexpected EOF for Program Change data in track " .. trackNum
                end
                event.program = content:byte(cursor)
                cursor = cursor + 1
                table.insert(track.events, event)
                if not self.instruments[channel] then
                    self.instruments[channel] = event.program
                end
            elseif eventType == 0xF then   -- Meta Event or System Exclusive
                if statusByte == 0xFF then -- Meta Event
                    if cursor > contentLength then
                        return false,
                            "Unexpected EOF for Meta Event type in track " .. trackNum
                    end
                    local metaType = content:byte(cursor)
                    cursor = cursor + 1

                    local metaLength
                    metaLength, cursor, errMsg = self:readVLQ(content, cursor, contentLength)
                    if errMsg then
                        return false,
                            "Error reading Meta Event length in track " .. trackNum .. ": " .. errMsg
                    end

                    local metaDataStartCursor = cursor
                    if metaType == 0x2F then -- End of Track
                        cursor = metaDataStartCursor + metaLength
                        if cursor > contentLength + 1 then cursor = contentLength + 1 end
                        break
                    elseif metaType == 0x51 then -- Tempo Change
                        if metaLength == 3 then
                            if metaDataStartCursor + 2 > contentLength then
                                return false,
                                    "Unexpected EOF for Tempo data in track " .. trackNum
                            end
                            local tempoByte1 = content:byte(metaDataStartCursor)
                            local tempoByte2 = content:byte(metaDataStartCursor + 1)
                            local tempoByte3 = content:byte(metaDataStartCursor + 2)
                            local microsecondsPerQuarter = (tempoByte1 * 65536) + (tempoByte2 * 256) + tempoByte3
                            local bpm = 60000000 / microsecondsPerQuarter
                            bpm = math.floor(bpm * 1000 + 0.5) / 1000
                            table.insert(self.tempoEvents, {
                                type = "setTempo",
                                time = absoluteTime,
                                track = trackNum,
                                microsecondsPerQuarter = microsecondsPerQuarter,
                                bpm = bpm
                            })
                        end
                        cursor = metaDataStartCursor + metaLength
                    elseif metaType == 0x58 then -- Time Signature
                        if metaLength == 4 then
                            if metaDataStartCursor + 3 > contentLength then
                                return false,
                                    "Unexpected EOF for Time Signature data in track " .. trackNum
                            end
                            local numerator = content:byte(metaDataStartCursor)
                            local denominatorPower = content:byte(metaDataStartCursor + 1)
                            local clocksPerClick = content:byte(metaDataStartCursor + 2)
                            local thirtySecondNotesPerQuarter = content:byte(metaDataStartCursor + 3)
                            table.insert(self.timeSignatureEvents, {
                                type = "timeSignature",
                                time = absoluteTime,
                                track = trackNum,
                                numerator = numerator,
                                denominator = 2 ^ denominatorPower,
                                clocksPerClick = clocksPerClick,
                                thirtySecondNotesPerQuarter = thirtySecondNotesPerQuarter
                            })
                        end
                        cursor = metaDataStartCursor + metaLength
                    else
                        cursor = metaDataStartCursor + metaLength
                    end
                    if cursor > contentLength + 1 then cursor = contentLength + 1 end
                elseif statusByte == 0xF0 or statusByte == 0xF7 then -- SysEx Event
                    local length
                    length, cursor, errMsg = self:readVLQ(content, cursor, contentLength)
                    if errMsg then return false, "Error reading SysEx length in track " .. trackNum .. ": " .. errMsg end
                    cursor = cursor + length
                    if cursor > contentLength + 1 then cursor = contentLength + 1 end
                end
            else
                if cursor + 1 > contentLength then
                    return false,
                        "Unexpected EOF for 2-byte skip event (type " ..
                        string.format("%X", eventType) .. ") in track " .. trackNum
                end
                cursor = cursor + 2
            end

            if cursor > trackEndLimit then cursor = trackEndLimit end
            if cursor > contentLength + 1 then cursor = contentLength + 1 end
        end

        if cursor < trackEndLimit and trackEndLimit <= contentLength + 1 then
            cursor = trackEndLimit
        end
        if cursor > contentLength + 1 then cursor = contentLength + 1 end

        table.insert(self.tracks, track)
    end

    table.sort(self.tempoEvents, function(a, b) return a.time < b.time end)
    table.sort(self.timeSignatureEvents, function(a, b) return a.time < b.time end)

    return true
end

-- Get all notes from the MIDI file
function MidiParser:getNotes()
    local notes = {}

    for trackNum, track in ipairs(self.tracks) do
        for _, event in ipairs(track.events) do
            if event.type == "noteOn" or event.type == "noteOff" then
                table.insert(notes, {
                    type = event.type,
                    time = event.time,
                    track = trackNum,
                    channel = event.channel,
                    note = event.note,
                    velocity = event.velocity
                })
            end
        end
    end

    table.sort(notes, function(a, b)
        if a.time == b.time then
            return (a.type == "noteOff" and b.type == "noteOn")
        end
        return a.time < b.time
    end)

    return notes
end

-- Get all program changes (instrument changes)
function MidiParser:getInstruments()
    local instruments = {}

    for trackNum, track in ipairs(self.tracks) do
        for _, event in ipairs(track.events) do
            if event.type == "programChange" then
                table.insert(instruments, {
                    time = event.time,
                    track = trackNum,
                    channel = event.channel,
                    program = event.program
                })
            end
        end
    end

    table.sort(instruments, function(a, b) return a.time < b.time end)

    return instruments
end

-- Get tempo information
function MidiParser:getTempoEvents()
    return self.tempoEvents
end

-- Get time signature information
function MidiParser:getTimeSignatureEvents()
    return self.timeSignatureEvents
end

-- Get the initial tempo (or default 120 BPM if none specified)
function MidiParser:getInitialTempo()
    if #self.tempoEvents > 0 then
        return self.tempoEvents[1].bpm
    else
        return 120
    end
end

-- Get the initial time signature (or default 4/4 if none specified)
function MidiParser:getInitialTimeSignature()
    if #self.timeSignatureEvents > 0 then
        return self.timeSignatureEvents[1].numerator, self.timeSignatureEvents[1].denominator
    else
        return 4, 4
    end
end

-- Parse MIDI file wrapper function
local function ParseMidiFile(filename)
    local parser = MidiParser.new(filename)
    local success, errorMsg = parser:parse()

    if not success then
        logger.error(logger.CATEGORIES.MIDI,
            "Error parsing MIDI file: " .. errorMsg)
        return nil
    end

    return parser
end

-- Drum channel note mappings (MIDI channel 9/10)
local drumChannelMappings = {
    [35] = 46,
    [36] = 47,
    [37] = 49,
    [38] = 48,
    [39] = 41,
    [40] = 51,
    [41] = 46,
    [42] = 38,
    [43] = 48,
    [44] = 37,
    [45] = 48,
    [46] = 37,
    [47] = 46,
    [48] = 47,
    [49] = 45,
    [50] = 48,
    [51] = 45,
    [52] = 44,
    [57] = 44,
}

-- Instrument mappings (MIDI program to bardcraft instrument)
-- Instrument IDs: 1=Lute, 2=BassFlute, 3=Ocarina, 4=Fiddle, 5=Drum, 0=None
local instrumentMappings = {
    { instr = 1, low = 0,   high = 15 },  -- Piano/Chromatic -> Lute
    { instr = 3, low = 16,  high = 23 },  -- Organ -> Ocarina
    { instr = 1, low = 24,  high = 39 },  -- Guitar/Bass -> Lute
    { instr = 4, low = 40,  high = 41 },  -- Violin/Viola -> Fiddle
    { instr = 2, low = 42,  high = 43 },  -- Cello/Contrabass -> BassFlute
    { instr = 4, low = 44,  high = 44 },  -- Tremolo Strings -> Fiddle
    { instr = 1, low = 45,  high = 45 },  -- Pizzicato -> Lute
    { instr = 1, low = 46,  high = 46 },  -- Harp -> Lute
    { instr = 5, low = 47,  high = 47 },  -- Timpani -> Drum
    { instr = 4, low = 48,  high = 51 },  -- String Ensemble -> Fiddle
    { instr = 3, low = 52,  high = 54 },  -- Choir/Voice -> Ocarina
    { instr = 1, low = 55,  high = 55 },  -- Orchestra Hit -> Lute
    { instr = 3, low = 56,  high = 56 },  -- Trumpet -> Ocarina
    { instr = 2, low = 57,  high = 58 },  -- Trombone/Tuba -> BassFlute
    { instr = 3, low = 59,  high = 63 },  -- Brass -> Ocarina
    { instr = 3, low = 64,  high = 65 },  -- Sax Alto/Soprano -> Ocarina
    { instr = 2, low = 66,  high = 67 },  -- Sax Tenor/Bari -> BassFlute
    { instr = 3, low = 68,  high = 68 },  -- Oboe -> Ocarina
    { instr = 2, low = 69,  high = 70 },  -- English Horn/Bassoon -> BassFlute
    { instr = 3, low = 71,  high = 72 },  -- Clarinet/Piccolo -> Ocarina
    { instr = 2, low = 73,  high = 73 },  -- Flute -> BassFlute
    { instr = 3, low = 74,  high = 74 },  -- Recorder -> Ocarina
    { instr = 2, low = 75,  high = 77 },  -- Pan Flute etc -> BassFlute
    { instr = 3, low = 78,  high = 79 },  -- Whistle/Ocarina -> Ocarina
    { instr = 1, low = 80,  high = 87 },  -- Synth Lead -> Lute
    { instr = 2, low = 88,  high = 95 },  -- Synth Pad -> BassFlute
    { instr = 0, low = 96,  high = 103 }, -- Synth Effects -> None
    { instr = 1, low = 104, high = 108 }, -- Ethnic Plucked -> Lute
    { instr = 4, low = 109, high = 110 }, -- Bagpipe/Fiddle -> Fiddle
    { instr = 3, low = 111, high = 111 }, -- Shanai -> Ocarina
    { instr = 1, low = 112, high = 114 }, -- Percussion Pitched -> Lute
    { instr = 5, low = 115, high = 119 }, -- Percussion -> Drum
    { instr = 0, low = 120, high = 127 }, -- Sound Effects -> None
}

local function getInstrumentMapping(instrument)
    instrument = instrument or 0
    local low, high = 1, #instrumentMappings
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local mapping = instrumentMappings[mid]
        if instrument < mapping.low then
            high = mid - 1
        elseif instrument > mapping.high then
            low = mid + 1
        else
            return mapping.instr
        end
    end
    return 0
end

local function mapDrumNote(note)
    return drumChannelMappings[note] or 46
end

-- Instrument names for display
local instrumentNames = {
    [1] = "Lute",
    [2] = "BassFlute",
    [3] = "Ocarina",
    [4] = "Fiddle",
    [5] = "Drum",
    [0] = "None"
}

-- Convert MIDI parser output to Bardcraft song format
local function createSongFromParser(parser, songId, title)
    title = title or songId
    local song = {
        id = songId,
        title = title,
        tempo = parser:getInitialTempo(),
        resolution = parser.division or 96,
        parts = {},
        notes = {}
    }

    local timeNumerator, timeDenominator = parser:getInitialTimeSignature()
    song.timeSig = { timeNumerator, timeDenominator }

    -- Track part assignments
    local partIndex = {}
    local partCount = {}
    local id = 1

    -- Process notes
    for _, note in ipairs(parser:getNotes()) do
        -- Map drum notes
        if note.channel == 9 then
            note.note = mapDrumNote(note.note)
        end

        -- Get instrument for this channel
        if not parser.instruments[note.channel] then
            parser.instruments[note.channel] = 1
        end

        local instrument = (note.channel == 9 and 5) or getInstrumentMapping(parser.instruments[note.channel])

        -- Skip unmapped instruments
        if instrument ~= 0 then
            -- Create part if needed
            if not partIndex[instrument] or not partIndex[instrument][note.track] then
                partIndex[instrument] = partIndex[instrument] or {}
                partCount[instrument] = (partCount[instrument] or 0) + 1

                local partNum = #song.parts + 1
                local instrumentName = instrumentNames[instrument] or "Lute"
                local partTitle = instrumentName
                if partCount[instrument] > 1 then
                    partTitle = partTitle .. " " .. partCount[instrument]
                end

                table.insert(song.parts, {
                    index = partNum,
                    instrument = instrument,
                    title = partTitle
                })

                partIndex[instrument][note.track] = partNum
            end

            -- Add note
            table.insert(song.notes, {
                id = id,
                type = note.type,
                note = note.note,
                velocity = note.velocity,
                part = partIndex[instrument][note.track],
                time = note.time
            })
            id = id + 1
        end
    end

    -- Calculate song length
    local lastNoteTime = (#song.notes > 0) and song.notes[#song.notes].time / song.resolution or 0
    local quarterNotesPerBar = song.timeSig[1] * (4 / song.timeSig[2])
    song.lengthBars = math.ceil(lastNoteTime / quarterNotesPerBar)

    -- Add tempo events
    song.tempoEvents = parser:getTempoEvents()

    return song
end

-- Helper function to load MIDI files from a single directory
local function loadMidiFilesFromDirectory(midiDir, foundFiles, category)
    -- category should be "custom" or "preset" to tag the source
    -- Ensure midiDir has no trailing slash
    midiDir = tostring(midiDir)
    midiDir = midiDir:gsub("[/\\]+$", "")

    local sep = package.config:sub(1, 1) == "\\" and "\\" or "/"

    -- Try LuaFileSystem first (portable and reliable)
    local ok, lfs = pcall(require, "lfs")
    if ok and lfs then
        logger.warn(logger.CATEGORIES.MIDI, "Using lfs for directory scan: " .. midiDir)
        local attr = lfs.attributes(midiDir)
        if not attr or attr.mode ~= "directory" then
            logger.warn(logger.CATEGORIES.MIDI, "MIDI directory not found or not a directory: " .. tostring(midiDir))
        else
            for name in lfs.dir(midiDir) do
                if name:lower():match("%.mid$") then
                    -- Store full path with the filename
                    table.insert(foundFiles, {
                        filename = name,
                        fullPath = midiDir .. sep .. name,
                        category = category
                    })
                end
            end
        end
    else
        -- Fallback to shell listing
        local isWindows = package.config:sub(1, 1) == '\\'
        local cmd
        if isWindows then
            cmd = string.format('cmd /C dir "%s\\*.mid" /b /a-d 2>nul', midiDir)
            logger.error(logger.CATEGORIES.MIDI, "lfs not available, using Windows dir command for: " .. midiDir)
        else
            cmd = string.format('ls -1 "%s"/*.mid 2>/dev/null', midiDir)
            logger.error(logger.CATEGORIES.MIDI, "lfs not available, using ls command for: " .. midiDir)
        end

        local handle, err = io.popen(cmd)
        if not handle then
            logger.error(logger.CATEGORIES.MIDI, "Could not execute dir listing command: " .. tostring(err))
        else
            for line in handle:lines() do
                if isWindows then
                    if line:lower():match("%.mid$") then
                        table.insert(foundFiles, {
                            filename = line,
                            fullPath = midiDir .. sep .. line,
                            category = category
                        })
                    end
                else
                    local filename = line
                    if filename:match("/") then
                        filename = filename:match("([^/]+)$")
                    end
                    if filename and filename:lower():match("%.mid$") then
                        table.insert(foundFiles, {
                            filename = filename,
                            fullPath = midiDir .. sep .. filename,
                            category = category
                        })
                    end
                end
            end
            handle:close()
        end
    end
end

function midi.LoadMidiFiles()
    local config = require("custom.bardcraft.config")

    logger.error(logger.CATEGORIES.MIDI, "Loading MIDI files...")

    -- CLEAR EXISTING SONGS BEFORE RELOAD
    local oldCount = tableHelper.getCount(midi.songs)
    midi.songs = {}
    midi.songsByName = {}
    logger.warn(logger.CATEGORIES.MIDI, string.format("Cleared %d existing songs before reload", oldCount))

    -- Support multiple directories
    local midiDirs = {}
    if config.midiDirectories then
        -- New multi-directory config
        if type(config.midiDirectories) == "table" then
            midiDirs = config.midiDirectories
        else
            -- Single directory passed as string
            table.insert(midiDirs, config.midiDirectories)
        end
    else
        logger.warn(logger.CATEGORIES.MIDI, "No MIDI directory configured!")
    end

    local count = 0
    local customCount = 0
    local presetCount = 0
    local foundFiles = {}

    -- Load MIDI files from each configured directory
    for i, midiDir in ipairs(midiDirs) do
        midiDir = tostring(midiDir or "")
        if midiDir ~= "" then
            -- Determine category based on directory path
            -- If the path contains "/preset" it's a preset, otherwise it's custom
            local category = "custom" -- default
            if midiDir:match("/preset") or midiDir:match("\\preset") then
                category = "preset"
            end

            logger.warn(logger.CATEGORIES.MIDI, string.format("Scanning MIDI directory [%s]: %s", category, midiDir))
            loadMidiFilesFromDirectory(midiDir, foundFiles, category)
        end
    end

    -- Deduplicate foundFiles by filename (last one wins if there are duplicates)
    local seen = {}
    local unique = {}
    for _, fileInfo in ipairs(foundFiles) do
        if not seen[fileInfo.filename] then
            seen[fileInfo.filename] = true
            table.insert(unique, fileInfo)
        else
            logger.warn(logger.CATEGORIES.MIDI,
                string.format("Duplicate MIDI file found (skipping): %s", fileInfo.filename))
        end
    end

    -- Try to parse each found file
    for _, fileInfo in ipairs(unique) do
        local fullPath = fileInfo.fullPath
        local filename = fileInfo.filename

        logger.verbose(logger.CATEGORIES.MIDI, "Found candidate MIDI file: " .. tostring(fullPath))

        -- verify file is readable
        local f, ferr = io.open(fullPath, "rb")
        if not f then
            logger.warn(logger.CATEGORIES.MIDI,
                string.format("Cannot open file %s: %s", tostring(fullPath), tostring(ferr)))
        else
            f:close()
            local parser = ParseMidiFile(fullPath)
            if parser then
                local songId = filename:match("^(.+)%.mid$") or filename
                local song = createSongFromParser(parser, songId, songId)

                -- NEW: Add category metadata to the song
                song.category = fileInfo.category

                midi.AddSong(song)
                count = count + 1

                -- Track counts by category
                -- Track counts by category
                if fileInfo.category == "preset" then
                    presetCount = presetCount + 1
                else
                    customCount = customCount + 1
                end

                logger.verbose(logger.CATEGORIES.MIDI, string.format("Loaded [%s] '%s' with %d notes",
                    fileInfo.category, song.title, #song.notes))
            else
                logger.warn(logger.CATEGORIES.MIDI, "Parser returned nil for file: " .. tostring(fullPath))
            end
        end
    end

    -- If no files found, create dummy songs (fallback)
    if count == 0 then
        logger.error(logger.CATEGORIES.MIDI, "No MIDI files found in any configured directory, creating dummy songs...")
        midi.CreateDummySongs()
        count = midi.GetSongCount()
    end

    logger.warn(logger.CATEGORIES.MIDI, string.format(
        "Loaded %d songs total from %d director%s (Custom: %d, Preset: %d)",
        count, #midiDirs, #midiDirs == 1 and "y" or "ies", customCount, presetCount))
end

-- Create dummy songs for testing (fallback)
function midi.CreateDummySongs()
    -- Simple scale exercise
    local scales = {
        id = "scales",
        title = "Scales",
        tempo = 120,
        resolution = 96,
        timeSig = { 4, 4 },
        parts = { { index = 1, instrument = 1, title = "Lute" } },
        notes = {},
        tempoEvents = {},
        lengthBars = 2
    }

    local scaleNotes = { 60, 62, 64, 65, 67, 69, 71, 72 }
    local id = 1
    local currentTick = 0
    for i, note in ipairs(scaleNotes) do
        table.insert(scales.notes, {
            id = id,
            type = "noteOn",
            time = currentTick,
            note = note,
            velocity = 80,
            part = 1
        })
        id = id + 1
        currentTick = currentTick + 48
    end
    midi.AddSong(scales)

    -- Simple melody
    local simple = {
        id = "simple",
        title = "Simple Melody",
        tempo = 100,
        resolution = 96,
        timeSig = { 4, 4 },
        parts = { { index = 1, instrument = 1, title = "Lute" } },
        notes = {},
        tempoEvents = {},
        lengthBars = 2
    }

    local melodyNotes = { 60, 64, 67, 64, 60 }
    id = 1
    currentTick = 0
    for i, note in ipairs(melodyNotes) do
        table.insert(simple.notes, {
            id = id,
            type = "noteOn",
            time = currentTick,
            note = note,
            velocity = 70,
            part = 1
        })
        id = id + 1
        currentTick = currentTick + 96
    end
    midi.AddSong(simple)

    -- Drum pattern
    local drumPattern = {
        id = "drum1",
        title = "Basic Drum Pattern",
        tempo = 120,
        resolution = 96,
        timeSig = { 4, 4 },
        parts = { { index = 1, instrument = 5, title = "Drum" } },
        notes = {},
        tempoEvents = {},
        lengthBars = 4
    }

    id = 1
    for bar = 0, 3 do
        local baseTick = bar * 384
        -- Kick
        table.insert(drumPattern.notes, {
            id = id, type = "noteOn", time = baseTick, note = 48, velocity = 90, part = 1
        })
        id = id + 1
        table.insert(drumPattern.notes, {
            id = id, type = "noteOn", time = baseTick + 192, note = 48, velocity = 90, part = 1
        })
        id = id + 1
        -- Snare
        table.insert(drumPattern.notes, {
            id = id, type = "noteOn", time = baseTick + 96, note = 49, velocity = 85, part = 1
        })
        id = id + 1
        table.insert(drumPattern.notes, {
            id = id, type = "noteOn", time = baseTick + 288, note = 49, velocity = 85, part = 1
        })
        id = id + 1
        -- Hi-hat
        for i = 0, 7 do
            table.insert(drumPattern.notes, {
                id = id, type = "noteOn", time = baseTick + (i * 48), note = 46, velocity = 60, part = 1
            })
            id = id + 1
        end
    end
    midi.AddSong(drumPattern)
end

-- Add a song
function midi.AddSong(song)
    midi.songs[song.id] = song
    midi.songsByName[song.title:lower()] = song
end

-- Get song by ID
function midi.GetSongById(id)
    return midi.songs[id]
end

-- Get song by name (case-insensitive)
function midi.GetSongByName(name)
    return midi.songsByName[name:lower()]
end

-- Get number of loaded songs
function midi.GetSongCount()
    local count = 0
    for _ in pairs(midi.songs) do
        count = count + 1
    end
    return count
end

-- Get all song names
function midi.GetAllSongNames()
    local names = {}
    for id, song in pairs(midi.songs) do
        table.insert(names, song.title)
    end
    table.sort(names)
    return names
end

-- Export ParseMidiFile for debugging / direct usage
midi.ParseMidiFile = ParseMidiFile

return midi
