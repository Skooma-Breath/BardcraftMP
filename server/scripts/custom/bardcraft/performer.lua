--[[
Bardcraft Performer
Manages individual performer state and actions

FIXED VERSION - Implements counter-based note tracking like the original OpenMW Bardcraft
to prevent missing repeated notes when cutoff mode is enabled.
]]

local performer = {}

local logger = require("custom.bardcraft.logger")

-- Create a new performer for a player
function performer.New(pid)
    logger.info(logger.CATEGORIES.PERFORMER,
        string.format("performer.New called for pid %d", pid))

    if not Players[pid] then
        logger.error(logger.CATEGORIES.PERFORMER,
            string.format("Players[%d] is nil!", pid))
        return nil
    end

    if not Players[pid].data then
        logger.error(logger.CATEGORIES.PERFORMER,
            string.format("Players[%d].data is nil!", pid))
        return nil
    end

    if not Players[pid].data.customVariables then
        logger.error(logger.CATEGORIES.PERFORMER,
            string.format("Players[%d].data.customVariables is nil!", pid))
        return nil
    end

    if not Players[pid].data.customVariables.bardcraft then
        logger.error(logger.CATEGORIES.PERFORMER,
            string.format("Players[%d].data.customVariables.bardcraft is nil!", pid))
        return nil
    end

    local p = {
        pid = pid,
        playing = false,
        currentSong = nil,
        currentInstrument = nil,
        musicTime = 0,
        lastNoteTime = 0,
        lastAnimation = nil,
        playingNotes = {}, -- Track which notes are currently playing (counter-based)
        activeSounds = {}, -- Track active sound IDs for stopping
        data = Players[pid].data.customVariables.bardcraft,
    }

    setmetatable(p, { __index = performer })

    logger.info(logger.CATEGORIES.PERFORMER,
        string.format("Created performer object for pid %d", pid))

    return p
end

-- Start performance
function performer:Start(song, instrumentType)
    self.playing = true
    self.currentSong = song
    self.currentInstrument = instrumentType
    self.musicTime = 0
    self.lastNoteTime = 0
    self.lastAnimation = nil
    self.playingNotes = {}
    self.activeSounds = {}

    logger.info(logger.CATEGORIES.PERFORMER,
        string.format("Performer:Start - pid=%d, song=%s, instrument=%s",
            self.pid, song.title, instrumentType))

    -- Start the main animation
    local instruments = require("custom.bardcraft.instruments")
    local anims = instruments.animations[instrumentType]
    if anims and anims.main then
        tes3mp.PlayAnimation(self.pid, anims.main, 2, 1, false)
        logger.info(logger.CATEGORIES.PERFORMER,
            string.format("Playing main animation: %s", anims.main))
    else
        logger.warn(logger.CATEGORIES.PERFORMER,
            string.format("No main animation found for %s", instrumentType))
    end

    logger.info(logger.CATEGORIES.PERFORMER,
        string.format("Player %d started performing %s with %s",
            self.pid, song.title, instrumentType))
end

-- Stop performance
function performer:Stop()
    if not self.playing then return end

    self.playing = false

    -- Cancel animation
    tes3mp.PlayAnimation(self.pid, "idle", 2, 1, false)

    -- Stop all playing notes
    self:StopAllNotes()

    logger.info(logger.CATEGORIES.PERFORMER,
        string.format("Player %d stopped performing", self.pid))
end

-- Play a note
function performer:PlayNote(note, velocity)
    local instruments = require("custom.bardcraft.instruments")
    local profile = instruments.profiles[self.currentInstrument]

    if not profile then
        logger.error(logger.CATEGORIES.PERFORMER,
            string.format("No instrument profile for %s", self.currentInstrument))
        return
    end

    -- Generate sound record ID (format: InstrumentName_NoteName)
    local noteName = self:NoteNumberToName(note)
    local soundId = string.format("%s_%s", profile.name, noteName)

    logger.info(logger.CATEGORIES.PERFORMER,
        string.format("PlayNote: pid=%d, note=%d (%s), soundId=%s, velocity=%d",
            self.pid, note, noteName, soundId, velocity))

    -- Get player's volume setting
    local playerVolume = self.data.instrumentVolume or 1.0

    -- Calculate volume from velocity (MIDI velocity is 0-127) and player setting
    local volume = (velocity / 127.0) * playerVolume
    local pitch = 1.0

    -- Check if note cutoff is enabled
    local noteCutoffEnabled = self.data.noteCutoffEnabled
    if noteCutoffEnabled == nil then
        noteCutoffEnabled = true -- Default to enabled
    end

    -- FIXED: Track playing notes with a counter (like the original OpenMW version)
    -- This allows multiple instances of the same note to play simultaneously
    -- without overwriting each other in rapid succession
    self.playingNotes[note] = self.playingNotes[note] and self.playingNotes[note] + 1 or 1

    -- Use PlayLoopSound3DVP for sustained instruments OR if note cutoff is enabled for non-sustained
    local soundCommand
    if profile.sustain or noteCutoffEnabled then
        soundCommand = string.format('PlayLoopSound3DVP, "%s", %.2f, %.2f', soundId, volume, pitch)
        -- Store the sound ID (needed for stopping)
        -- Only set on first instance to avoid overwriting
        if not self.activeSounds[note] then
            self.activeSounds[note] = soundId
        end
    else
        -- Let the sound play naturally without tracking
        soundCommand = string.format('PlaySound3DVP, "%s", %.2f, %.2f', soundId, volume, pitch)
    end

    logger.info(logger.CATEGORIES.PERFORMER,
        string.format("Sound command: %s (playing instances: %d)",
            soundCommand, self.playingNotes[note]))

    logicHandler.RunConsoleCommandOnPlayer(self.pid, soundCommand, true)

    -- Play animation
    local anim = instruments.GetNoteAnimation(self.currentInstrument, note,
        self.lastNote, self.lastAnimation)
    if anim then
        tes3mp.PlayAnimation(self.pid, anim, 2, 1, false)
        logger.info(logger.CATEGORIES.PERFORMER,
            string.format("Playing animation: %s", anim))
        self.lastAnimation = anim
    else
        logger.warn(logger.CATEGORIES.PERFORMER,
            string.format("No animation for note %d on %s", note, self.currentInstrument))
    end

    self.lastNote = note
    self.lastNoteTime = self.musicTime
end

-- Stop a note
function performer:StopNote(note)
    -- FIXED: Decrement counter instead of immediately stopping
    -- Only stop the sound when counter reaches 0
    self.playingNotes[note] = self.playingNotes[note] and self.playingNotes[note] - 1 or 0

    if self.playingNotes[note] > 0 then
        logger.info(logger.CATEGORIES.PERFORMER,
            string.format("Note %d still has %d active instances, not stopping yet",
                note, self.playingNotes[note]))
        return
    end

    -- For sustained instruments, stop the looping sound
    if self.activeSounds[note] then
        local soundId = self.activeSounds[note]
        local stopCommand = string.format('StopSound, "%s"', soundId)
        logger.info(logger.CATEGORIES.PERFORMER,
            string.format("Stopping sound: %s (all instances ended)", stopCommand))
        logicHandler.RunConsoleCommandOnPlayer(self.pid, stopCommand, true)
        self.activeSounds[note] = nil
    end
end

-- Stop all playing notes
function performer:StopAllNotes()
    -- Stop all active looping sounds
    for note, soundId in pairs(self.activeSounds) do
        local stopCommand = string.format('StopSound, "%s"', soundId)
        logger.info(logger.CATEGORIES.PERFORMER,
            string.format("Stopping all sounds: %s", stopCommand))
        logicHandler.RunConsoleCommandOnPlayer(self.pid, stopCommand, true)
    end

    self.activeSounds = {}
    self.playingNotes = {}
end

-- Convert MIDI note number to note name
function performer:NoteNumberToName(noteNumber)
    local noteNames = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }
    local octave = math.floor(noteNumber / 12) - 1
    local noteName = noteNames[(noteNumber % 12) + 1]
    return noteName .. octave
end

-- Teach a song to the performer
function performer.TeachSong(pid, songId)
    if not Players[pid] or not Players[pid]:IsLoggedIn() then return false end

    local data = Players[pid].data.customVariables.bardcraft
    if not data.knownSongs[songId] then
        data.knownSongs[songId] = {
            confidence = 0,
            timesPlayed = 0,
        }
        Players[pid]:Save()
        return true
    end
    return false
end

return performer
