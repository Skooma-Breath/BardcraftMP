--[[
Bardcraft Conductor
Manages performance timing and coordination
]]
local conductor = {}

local Bardcraft
-- Export a setter so the init module can inject the Bardcraft table and avoid circular require issues
function conductor.SetBardcraft(bc)
    Bardcraft = bc
end

local inventory = require("custom.bardcraft.inventory")
local logger = require("custom.bardcraft.logger")

-- Active performances (pid -> performance data)
conductor.performances = {}
conductor.cellPerformances = {}

-- Update timer
conductor.updateTimer = nil
conductor.updateInterval = nil -- milliseconds (20 updates per second)

-- Initialize update interval from config
function conductor.Init()
    local config = require("custom.bardcraft.config")
    if config and config.updateInterval then
        conductor.updateInterval = config.updateInterval
    else
        -- Default to 0.05 seconds (50ms, 20 updates per second)
        conductor.updateInterval = 0.05
        -- Log it
        logger.verbose(logger.CATEGORIES.CONDUCTOR,
            string.format("update interval - '%s'",
                tostring(conductor.updateInterval)))
    end
end

-- Get the current performance in a cell (if any)
function conductor.GetCellPerformance(cellDescription)
    return conductor.cellPerformances[cellDescription]
end

-- Register a performance in a cell
function conductor.RegisterCellPerformance(pid, cellDescription, songId, startTime)
    if not conductor.cellPerformances[cellDescription] then
        conductor.cellPerformances[cellDescription] = {
            songId = songId,
            startTime = startTime,
            performers = {}
        }
    end

    table.insert(conductor.cellPerformances[cellDescription].performers, pid)

    logger.info(logger.CATEGORIES.CELL,
        string.format("Registered performance in cell %s: pid=%d, song=%s",
            cellDescription, pid, songId))
end

-- Unregister a performer from a cell
function conductor.UnregisterCellPerformance(pid, cellDescription)
    if not conductor.cellPerformances[cellDescription] then return end

    local perf = conductor.cellPerformances[cellDescription]

    -- Remove performer
    for i, performerId in ipairs(perf.performers) do
        if performerId == pid then
            table.remove(perf.performers, i)
            break
        end
    end

    -- If no more performers, clear the cell performance
    if #perf.performers == 0 then
        conductor.cellPerformances[cellDescription] = nil
        logger.info(logger.CATEGORIES.CELL,
            string.format("Cleared cell performance: %s", cellDescription))
    end
end

-- Check if a different song is already playing in the cell
function conductor.CanStartInCell(pid, songId)
    --local Bardcraft = require("custom.bardcraft.init")

    -- Log the chaos mode setting
    logger.verbose(logger.CATEGORIES.CONDUCTOR,
        string.format("CanStartInCell check - allowChaos=%s",
            tostring(Bardcraft.config.allowChaos)))

    -- If chaos is allowed, anyone can play anything
    if Bardcraft.config.allowChaos then
        logger.verbose(logger.CATEGORIES.CONDUCTOR,
            "Chaos mode is ON - allowing performance")
        return true, nil
    end

    local cellDescription = Players[pid].data.location.cell
    local cellPerf = conductor.cellPerformances[cellDescription]

    -- Log cell performance status
    logger.verbose(logger.CATEGORIES.CONDUCTOR,
        string.format("Cell '%s' - existing performance: %s",
            cellDescription, cellPerf and "YES" or "NO"))

    -- No performance in this cell, OK to start
    if not cellPerf then
        logger.verbose(logger.CATEGORIES.CONDUCTOR,
            "No existing performance - allowing")
        return true, nil
    end

    -- Log song comparison
    logger.verbose(logger.CATEGORIES.CONDUCTOR,
        string.format("Comparing songs - existing='%s', requested='%s'",
            tostring(cellPerf.songId), tostring(songId)))

    -- Same song is playing, OK to join
    if cellPerf.songId == songId then
        logger.verbose(logger.CATEGORIES.CONDUCTOR,
            "Same song - allowing join")
        return true, cellPerf
    end

    -- Different song is playing, not allowed
    logger.warn(logger.CATEGORIES.CONDUCTOR,
        string.format("Different song detected - BLOCKING (chaos mode is OFF, existing='%s', requested='%s')",
            tostring(cellPerf.songId), tostring(songId)))
    return false, cellPerf
end

-- Join an ongoing performance in the current cell
function conductor.JoinCellPerformance(pid, partIndexOrInstrument)
    --local Bardcraft = require("custom.bardcraft.init")
    local cellDescription = Players[pid].data.location.cell
    local cellPerf = conductor.cellPerformances[cellDescription]

    if not cellPerf then
        tes3mp.SendMessage(pid, color.Red .. "No performance to join in this area!\n", false)
        return false
    end

    local song = Bardcraft.midi.GetSongById(cellPerf.songId)
    if not song then
        tes3mp.SendMessage(pid, color.Red .. "Performance song not found!\n", false)
        return false
    end

    -- Find the requested part
    local part = nil
    local instrumentName = nil

    if type(partIndexOrInstrument) == "number" then
        -- Part index provided
        part = song.parts[partIndexOrInstrument]
    else
        -- Instrument name provided, find first matching part
        for _, p in ipairs(song.parts) do
            local pTitle = (p.title or ""):lower()
            local pInst = tostring(p.instrument):lower()
            local requested = tostring(partIndexOrInstrument):lower()

            if pTitle:match(requested) or pInst == requested then
                part = p
                break
            end
        end
    end

    if not part then
        tes3mp.SendMessage(pid, color.Red .. "Part not found in this song!\n", false)
        return false
    end

    -- Get instrument name
    instrumentName = part.title or tostring(part.instrument)
    if type(instrumentName) == "string" then
        instrumentName = instrumentName:gsub("%s+%d+$", "")
    end

    -- Stop any existing performance
    if conductor.performances[pid] then
        conductor.StopPerformance(pid)
    end

    -- Start synchronized with the cell performance
    conductor.StartPerformanceWithTime(pid, song, part, instrumentName, cellPerf.startTime)

    -- Register in cell
    conductor.RegisterCellPerformance(pid, cellDescription, song.id, cellPerf.startTime)

    tes3mp.SendMessage(pid, color.Green ..
        string.format("Joined performance: %s (%s)\n", song.title, instrumentName), false)

    return true
end

function conductor.StartPerformance(pid, songName, instrumentName)
    --local Bardcraft = require("custom.bardcraft.init")

    -- Get the song
    local song = Bardcraft.midi.GetSongByName(songName)
    if not song then
        tes3mp.SendMessage(pid, color.Red .. "Song not found: " .. songName .. "\n", false)
        return false
    end

    -- Check if performance is allowed in this cell
    local cellDescription = Players[pid].data.location.cell
    local canStart, existingPerf = conductor.CanStartInCell(pid, song.id)

    if not canStart then
        local existingSong = Bardcraft.midi.GetSongById(existingPerf.songId)
        local existingSongName = existingSong and existingSong.title or "Unknown"
        tes3mp.SendMessage(pid, color.Red ..
            string.format("Another song is already playing in this area: %s\n" ..
                "Use /bc to join the ongoing performance or wait for it to finish.\n",
                existingSongName), false)
        return false
    end

    -- Normalize requested instrument input
    local requestedName = instrumentName
    local requestedId = tonumber(instrumentName)
    local requestedLower = nil
    if type(requestedName) == "string" then requestedLower = requestedName:lower() end

    -- Find the part for this instrument
    local part = nil
    local chosenInstrumentString = nil

    for _, p in ipairs(song.parts) do
        if type(p.instrument) == "number" and requestedId and p.instrument == requestedId then
            part = p
            chosenInstrumentString = p.title and tostring(p.title):gsub("%s+%d+$", "") or nil
            break
        end

        if requestedLower and p.title and type(p.title) == "string" then
            local partTitleLower = p.title:lower()
            if partTitleLower == requestedLower or partTitleLower:match("^" .. requestedLower) then
                part = p
                chosenInstrumentString = p.title:gsub("%s+%d+$", "")
                break
            end
        end

        if requestedLower and type(p.instrument) == "string" and p.instrument:lower() == requestedLower then
            part = p
            chosenInstrumentString = p.instrument
            break
        end
    end

    if not part then
        local available = ""
        for _, p in ipairs(song.parts) do
            available = available .. (p.title or tostring(p.instrument)) .. " "
        end
        tes3mp.SendMessage(pid, color.Red .. "No part for " .. tostring(instrumentName) ..
            " in this song! Available parts: " .. available .. "\n", false)
        return false
    end

    if not inventory.HasInstrument(pid, chosenInstrumentString) then
        tes3mp.SendMessage(pid, color.Red ..
            string.format("You need a %s instrument (bcw_%s) to play this part!\n",
                chosenInstrumentString, chosenInstrumentString:lower()), false)
        logger.info(logger.CATEGORIES.CONDUCTOR,
            string.format("Player %d lacks instrument %s", pid, chosenInstrumentString))
        return false
    end

    chosenInstrumentString = chosenInstrumentString or tostring(instrumentName)

    -- Stop any existing performance
    if conductor.performances[pid] then
        conductor.StopPerformance(pid)
    end

    -- Create performance data with synchronized start time
    local startTime = tes3mp.GetMillisecondsSinceServerStart() / 1000

    conductor.performances[pid] = {
        song = song,
        part = part,
        instrument = chosenInstrumentString,
        startTime = startTime,
        currentTick = 0,
        noteIndex = 1,
        bpm = song.tempo or 120,
        playedNotes = {},
        notes = conductor.GetNotesForPart(song, part),
    }

    -- Register in cell
    conductor.RegisterCellPerformance(pid, cellDescription, song.id, startTime)

    logger.info(logger.CATEGORIES.CONDUCTOR,
        string.format("Created performance for pid %d: %d notes, BPM %d",
            pid, #conductor.performances[pid].notes, conductor.performances[pid].bpm))

    -- Start performer
    local performer = Bardcraft.performers[pid]
    if not performer then
        logger.warn(logger.CATEGORIES.CONDUCTOR,
            string.format("Performer didn't exist for pid %d, creating now", pid))
        Bardcraft.performers[pid] = Bardcraft.performer.New(pid)
        performer = Bardcraft.performers[pid]
    end

    if performer then
        performer:Start(song, chosenInstrumentString)
        inventory.OnPerformanceStart(pid, chosenInstrumentString)
        logger.verbose(logger.CATEGORIES.CONDUCTOR,
            string.format("Performer started for pid %d", pid))
    else
        logger.error(logger.CATEGORIES.CONDUCTOR,
            string.format("FAILED to create performer for pid %d!", pid))
        return false
    end

    -- Start/restart timer
    if not conductor.updateTimer then
        conductor.updateTimer = tes3mp.CreateTimer(
            "BardcraftUpdateTimer",
            conductor.updateInterval
        )
        local ok, err = pcall(function() tes3mp.StartTimer(conductor.updateTimer) end)
        if not ok then
            logger.warn(logger.CATEGORIES.TIMER,
                string.format("Failed to start timer %s: %s", tostring(conductor.updateTimer), tostring(err)))
        else
            logger.verbose(logger.CATEGORIES.TIMER,
                "Started update timer (ID: " .. tostring(conductor.updateTimer) .. ")")
        end
    else
        local ok, err = pcall(function() tes3mp.StartTimer(conductor.updateTimer) end)
        if not ok then
            logger.warn(logger.CATEGORIES.TIMER,
                string.format("StartTimer failed for existing ID %s: %s", tostring(conductor.updateTimer),
                    tostring(err)))
        else
            logger.verbose(logger.CATEGORIES.TIMER,
                "Restarted existing update timer (ID: " .. tostring(conductor.updateTimer) .. ")")
        end
    end

    tes3mp.SendMessage(pid, color.Green .. "Now performing: " .. song.title ..
        " (" .. chosenInstrumentString .. ")\n", false)

    return true
end

-- Start a performance with a specific start time (for band synchronization)
function conductor.StartPerformanceWithTime(pid, song, part, instrumentName, startTime)
    -- Stop any existing performance
    if conductor.performances[pid] then
        conductor.StopPerformance(pid)
    end

    -- Get instrument name from part if not provided
    local chosenInstrumentString = instrumentName
    if not chosenInstrumentString then
        chosenInstrumentString = part.title or tostring(part.instrument)
        if type(chosenInstrumentString) == "string" then
            chosenInstrumentString = chosenInstrumentString:gsub("%s+%d+$", "")
        end
    end

    -- Create performance data with synchronized start time
    conductor.performances[pid] = {
        song = song,
        part = part,
        instrument = chosenInstrumentString,
        startTime = startTime, -- Use the provided synchronized start time
        currentTick = 0,
        noteIndex = 1,
        bpm = song.tempo or 120,
        playedNotes = {},
        notes = conductor.GetNotesForPart(song, part),
    }

    logger.info(logger.CATEGORIES.CONDUCTOR,
        string.format("Created synchronized performance for pid %d: %d notes, BPM %d, startTime=%.2f",
            pid, #conductor.performances[pid].notes, conductor.performances[pid].bpm, startTime))

    -- Start performer
    local performer = Bardcraft.performers[pid]
    if not performer then
        logger.warn(logger.CATEGORIES.CONDUCTOR,
            string.format("Performer didn't exist for pid %d, creating now", pid))
        Bardcraft.performers[pid] = Bardcraft.performer.New(pid)
        performer = Bardcraft.performers[pid]
    end

    if performer then
        performer:Start(song, chosenInstrumentString)
        inventory.OnPerformanceStart(pid, chosenInstrumentString)
        logger.verbose(logger.CATEGORIES.CONDUCTOR,
            string.format("Performer started for pid %d", pid))
    else
        logger.error(logger.CATEGORIES.CONDUCTOR,
            string.format("FAILED to create performer for pid %d!", pid))
        return false
    end

    -- Start/restart timer
    if not conductor.updateTimer then
        conductor.updateTimer = tes3mp.CreateTimer(
            "BardcraftUpdateTimer",
            conductor.updateInterval
        )
        local ok, err = pcall(function() tes3mp.StartTimer(conductor.updateTimer) end)
        if not ok then
            logger.warn(logger.CATEGORIES.TIMER,
                string.format("Failed to start timer %s: %s", tostring(conductor.updateTimer), tostring(err)))
        else
            logger.verbose(logger.CATEGORIES.TIMER,
                "Started update timer (ID: " .. tostring(conductor.updateTimer) .. ")")
        end
    else
        local ok, err = pcall(function() tes3mp.StartTimer(conductor.updateTimer) end)
        if not ok then
            logger.warn(logger.CATEGORIES.TIMER,
                string.format("StartTimer failed for existing ID %s: %s", tostring(conductor.updateTimer),
                    tostring(err)))
        else
            logger.verbose(logger.CATEGORIES.TIMER,
                "Restarted existing update timer (ID: " .. tostring(conductor.updateTimer) .. ")")
        end
    end

    return true
end

function conductor.SwitchPerformancePart(pid, newPart, newInstrumentName)
    --local Bardcraft = require("custom.bardcraft.init")
    local perf = conductor.performances[pid]

    if not perf then
        logger.warn(logger.CATEGORIES.CONDUCTOR,
            string.format("Cannot switch part - no performance for pid %d", pid))
        return false
    end

    -- Get instrument name from part if not provided
    local chosenInstrumentString = newInstrumentName
    if not chosenInstrumentString then
        chosenInstrumentString = newPart.title or tostring(newPart.instrument)
    end

    -- Always strip trailing numbers (e.g., "Lute 1" -> "Lute")
    if type(chosenInstrumentString) == "string" then
        chosenInstrumentString = chosenInstrumentString:gsub("%s+%d+$", "")
    end

    -- Check if player has the new instrument (or if requirement is disabled)
    if not inventory.HasInstrument(pid, chosenInstrumentString) then
        tes3mp.SendMessage(pid, color.Red ..
            string.format("You need a %s instrument (bcw_%s) to play this part!\n",
                chosenInstrumentString, chosenInstrumentString:lower()), false)
        logger.info(logger.CATEGORIES.CONDUCTOR,
            string.format("Player %d lacks instrument %s for part switch",
                pid, chosenInstrumentString))
        return false
    end

    -- Calculate current position in the song
    local elapsed = (tes3mp.GetMillisecondsSinceServerStart() / 1000) - perf.startTime
    local ticksPerSecond = (perf.bpm / 60) * (perf.song.resolution or 96)
    local currentTick = elapsed * ticksPerSecond

    -- Stop all currently playing notes from old instrument
    local performer = Bardcraft.performers[pid]
    if performer then
        performer:StopAllNotes()
    end

    -- Store old instrument for equipment swap
    local oldInstrument = perf.instrument

    -- Get notes for the new part
    local newNotes = conductor.GetNotesForPart(perf.song, newPart)

    -- Find the correct note index for current position
    local newNoteIndex = 1
    for i, note in ipairs(newNotes) do
        if note.tick > currentTick then
            newNoteIndex = i
            break
        end
        newNoteIndex = i + 1
    end

    logger.info(logger.CATEGORIES.CONDUCTOR,
        string.format("Switching part for pid %d: old=%s, new=%s, currentTick=%.1f, newNoteIndex=%d/%d",
            pid, oldInstrument, chosenInstrumentString, currentTick, newNoteIndex, #newNotes))

    -- Handle instrument equipment swap if changing instruments
    if oldInstrument ~= chosenInstrumentString then
        -- End performance with old instrument (unequips it and restores original equipment)
        inventory.OnPerformanceEnd(pid, oldInstrument)

        logger.info(logger.CATEGORIES.CONDUCTOR,
            string.format("Unequipped old instrument %s for pid %d", oldInstrument, pid))

        -- Start performance with new instrument (equips it)
        inventory.OnPerformanceStart(pid, chosenInstrumentString)

        logger.info(logger.CATEGORIES.CONDUCTOR,
            string.format("Equipped new instrument %s for pid %d", chosenInstrumentString, pid))
    end

    -- Update performance data (keep same startTime and song!)
    perf.part = newPart
    perf.instrument = chosenInstrumentString
    perf.notes = newNotes
    perf.noteIndex = newNoteIndex
    perf.currentTick = currentTick

    -- Update performer instrument
    if performer then
        performer.currentInstrument = chosenInstrumentString

        -- Update animation for new instrument
        local instruments = require("custom.bardcraft.instruments")
        local anims = instruments.animations[chosenInstrumentString]
        if anims and anims.main then
            tes3mp.PlayAnimation(pid, anims.main, 2, 1, false)
            logger.info(logger.CATEGORIES.CONDUCTOR,
                string.format("Playing animation for new instrument: %s", anims.main))
        end
    end

    logger.info(logger.CATEGORIES.CONDUCTOR,
        string.format("Successfully switched to new part for pid %d", pid))

    return true
end

-- Stop a performance
function conductor.StopPerformance(pid)
    local perf = conductor.performances[pid]
    if not perf then return end

    local instrumentType = perf.instrument

    --local Bardcraft = require("custom.bardcraft.init")
    local performer = Bardcraft.performers[pid]
    if performer then
        performer:Stop()
    end

    if instrumentType then
        inventory.OnPerformanceEnd(pid, instrumentType)
    end

    local cellDescription = Players[pid].data.location.cell
    conductor.UnregisterCellPerformance(pid, cellDescription)

    conductor.performances[pid] = nil
end

-- Update all performances (called by timer)
function conductor.Update()
    local perfCount = 0
    for _ in pairs(conductor.performances) do
        perfCount = perfCount + 1
    end

    -- Only log timer updates at VERBOSE level since this happens frequently
    logger.verbose(logger.CATEGORIES.TIMER,
        string.format("Update called, %d active performance(s)", perfCount))

    -- Update each performance
    for pid, perf in pairs(conductor.performances) do
        conductor.UpdatePerformance(pid, perf)
    end

    -- Restart timer if there are still performances
    local hasPerformances = false
    for _ in pairs(conductor.performances) do
        hasPerformances = true
        break
    end

    if hasPerformances and conductor.updateTimer then
        -- Keep the timer alive; restart its interval so it triggers again shortly
        local ok, err = pcall(function() tes3mp.RestartTimer(conductor.updateTimer, conductor.updateInterval) end)
        if not ok then
            logger.warn(logger.CATEGORIES.TIMER,
                string.format("RestartTimer failed for ID %s: %s", tostring(conductor.updateTimer),
                    tostring(err)))
        end
    else
        logger.verbose(logger.CATEGORIES.TIMER,
            "No more performances, timer will be stopped")

        if conductor.updateTimer then
            -- Stop the timer but keep the id for reuse later (do not FreeTimer)
            local ok, err = pcall(function() tes3mp.StopTimer(conductor.updateTimer) end)
            if not ok then
                logger.warn(logger.CATEGORIES.TIMER,
                    string.format("StopTimer failed for ID %s: %s", tostring(conductor.updateTimer),
                        tostring(err)))
            else
                logger.verbose(logger.CATEGORIES.TIMER,
                    "Update timer stopped (ID: " .. tostring(conductor.updateTimer) .. ")")
            end
        end
    end
end

-- Global function for timer callback
function BardcraftUpdateTimer()
    logger.verbose(logger.CATEGORIES.TIMER, "Timer callback triggered")

    if Bardcraft and Bardcraft.conductor then
        Bardcraft.conductor.Update()
    else
        logger.error(logger.CATEGORIES.TIMER, "Could not access conductor in timer!")
    end
end

-- Update a single performance
function conductor.UpdatePerformance(pid, perf)
    --local Bardcraft = require("custom.bardcraft.init")
    local performer = Bardcraft.performers[pid]
    if not performer then
        logger.warn(logger.CATEGORIES.CONDUCTOR,
            string.format("No performer for pid %d, stopping performance", pid))
        conductor.StopPerformance(pid)
        return
    end

    -- Calculate current time in the song
    local elapsed = (tes3mp.GetMillisecondsSinceServerStart() / 1000) - perf.startTime
    performer.musicTime = elapsed

    -- Calculate current tick with better precision
    -- Don't use math.floor - we want to play notes as soon as their tick time is reached
    local ticksPerSecond = (perf.bpm / 60) * (perf.song.resolution or 96)
    local exactTick = elapsed * ticksPerSecond
    perf.currentTick = exactTick -- Store the exact tick for comparison

    -- Only log note processing at VERBOSE level to avoid spam
    logger.verbose(logger.CATEGORIES.CONDUCTOR,
        string.format("pid %d: elapsed=%.3fs, exactTick=%.1f, noteIndex=%d/%d",
            pid, elapsed, exactTick, perf.noteIndex, #perf.notes))

    -- Get notes for this part
    local notes = perf.notes

    -- Play/stop notes that should be playing/stopping now
    local notesPlayed = 0
    while perf.noteIndex <= #notes do
        local note = notes[perf.noteIndex]

        -- Play notes when we've reached or passed their tick time
        -- Add a small tolerance to prevent missing notes due to floating point precision
        if note.tick > (perf.currentTick + 0.5) then
            -- Haven't reached this note yet
            break
        end

        -- Only log individual notes at VERBOSE level
        logger.verbose(logger.CATEGORIES.CONDUCTOR,
            string.format("Processing note %d at tick %d (type=%s, MIDI note %d, velocity %d)",
                perf.noteIndex, note.tick, note.type, note.note, note.velocity or 64))

        -- Handle note based on type
        if note.type == "noteOn" then
            performer:PlayNote(note.note, note.velocity or 64)
            notesPlayed = notesPlayed + 1
        elseif note.type == "noteOff" then
            performer:StopNote(note.note)
        end

        perf.noteIndex = perf.noteIndex + 1
    end

    -- Only log if notes were actually played
    if notesPlayed > 0 then
        logger.verbose(logger.CATEGORIES.CONDUCTOR,
            string.format("Played %d note(s) this tick", notesPlayed))
    end

    -- Check if song is finished (all events processed)
    if perf.noteIndex > #notes then
        logger.info(logger.CATEGORIES.CONDUCTOR,
            string.format("Performance finished for pid %d", pid))
        conductor.StopPerformance(pid)
        tes3mp.SendMessage(pid, color.Orange .. "Performance finished!\n", false)
    end
end

function conductor.GetNotesForPart(song, part)
    local notes = {}

    -- Collect ALL notes (noteOn AND noteOff) belonging to the requested part
    for _, note in ipairs(song.notes or {}) do
        if note.part == part.index then
            local normalized = {
                id = note.id,
                type = note.type or "noteOn", -- Keep the original type (noteOn or noteOff)
                tick = note.tick or note.time or 0,
                note = note.note,
                velocity = (note.velocity * 6) or 64,
                part = note.part
            }
            table.insert(notes, normalized)
        end
    end

    -- Sort by tick
    table.sort(notes, function(a, b)
        return (a.tick or 0) < (b.tick or 0)
    end)

    return notes
end

return conductor
