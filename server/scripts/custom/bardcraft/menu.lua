--[[
Bardcraft Menu GUI (FIXED VERSION)
Provides admin tools for managing songs, reloading MIDIs, and adjusting tempo

FIXES:
1. Added input sanitization for tempo to prevent client crashes
2. Changed song list to use ListBox for scrollable display
3. Added better error handling and logging
4. Fixed listbox index handling (0-based)
]]

local menu = {}


local logger = require("custom.bardcraft.logger")
local Bardcraft
function menu.SetBardcraft(bc)
    Bardcraft = bc
end

-- GUI IDs (make sure these don't conflict with other mods)
menu.GUI_IDS = {
    MAIN_MENU = 31340,
    SONG_LIST = 31341,
    SONG_DETAILS = 31342,
    TEMPO_ADJUST = 31343,
    CONFIRM_RELOAD = 31344,
    PARTS_MENU = 31345,
    CONFIRM_DELETE_PART = 31346,
    PART_SELECTION = 31347,
    CHAOS_TOGGLE = 31348,
    LOGGER_MENU = 31349,
    CATEGORY_SELECT = 31350,
    CONFIRM_STOP_ALL = 31351,
    VOLUME_MENU = 31352,
    VOLUME_STEP_ADJUST = 31353,
    BAND_VOLUME_MENU = 31354,
    INVENTORY_TOGGLE = 31355,
}

-- Store current admin session data
menu.sessions = {}

function menu.IsAdmin(pid)
    return Players[pid] and Players[pid]:IsAdmin()
end

-- Show logger configuration menu
function menu.ShowLoggerMenu(pid)
    if not menu.IsAdmin(pid) then return end

    -- Get current logging states
    local conductorLevel = logger.config[logger.CATEGORIES.CONDUCTOR]
    local conductorBtn = "Notes: "
    if conductorLevel == nil or conductorLevel < logger.LEVELS.TRACE then
        conductorBtn = conductorBtn .. "OFF"
    else
        conductorBtn = conductorBtn .. "[ON]"
    end

    local menuText = color.Yellow .. "=== Logger Configuration ===\n\n"
    menuText = menuText .. color.White .. "Toggle logging categories:\n"
    menuText = menuText .. color.Gray .. "([X] = currently active)\n\n"
    menuText = menuText .. color.White .. "Notes: OFF <> ON\n"

    -- Create buttons with current state shown
    local buttons = string.format("%s;Show All;Back", conductorBtn)

    return tes3mp.CustomMessageBox(pid, menu.GUI_IDS.LOGGER_MENU, menuText, buttons)
end

-- Show confirmation for stopping all performances
function menu.ShowStopAllConfirm(pid)
    if not menu.IsAdmin(pid) then return end

    local activeCount = tableHelper.getCount(Bardcraft.conductor.performances)

    if activeCount == 0 then
        tes3mp.SendMessage(pid, color.Orange .. "No active performances to stop.\n", false)
        menu.ShowMainMenu(pid)
        return
    end

    local message = color.Yellow .. "=== Stop All Performances ===\n" .. color.Red ..
        "WARNING: This will stop ALL active performances!\n" .. color.White ..
        "Active performances: " .. activeCount .. "\n\n" ..
        "Are you sure?"

    tes3mp.CustomMessageBox(pid, menu.GUI_IDS.CONFIRM_STOP_ALL, message,
        "Yes, Stop All;Cancel")
end

-- Stop all active performances
function menu.StopAllPerformances(pid)
    if not menu.IsAdmin(pid) then return end

    local stopped = 0

    -- Create a list of PIDs to avoid modifying table during iteration
    local activePids = {}
    for performerPid, _ in pairs(Bardcraft.conductor.performances) do
        table.insert(activePids, performerPid)
    end

    -- Stop each performance
    for _, performerPid in ipairs(activePids) do
        Bardcraft.conductor.StopPerformance(performerPid)
        stopped = stopped + 1
    end

    tes3mp.SendMessage(pid, color.Green ..
        string.format("[Bardcraft Menu] Stopped %d performance%s.\n",
            stopped, stopped == 1 and "" or "s"), false)

    logger.info(logger.CATEGORIES.MENU,
        string.format("Admin %s stopped all performances (%d total)",
            Players[pid].name, stopped))
end

-- Stop current performance (solo or band)
function menu.StopCurrentPerformance(pid)
    local b = Bardcraft.band.GetBand(pid)

    if b and b.leader == pid then
        -- Stop band performance
        Bardcraft.band.StopPerformance(b.id)
        tes3mp.SendMessage(pid, color.Green .. "Band performance stopped.\n", false)

        logger.info(logger.CATEGORIES.MENU,
            string.format("%s stopped band performance via menu", Players[pid].name))
    else
        -- Stop solo performance
        Bardcraft.conductor.StopPerformance(pid)
        tes3mp.SendMessage(pid, color.Green .. "Performance stopped.\n", false)

        logger.info(logger.CATEGORIES.MENU,
            string.format("%s stopped performance via menu", Players[pid].name))
    end
end

-- Handle logger menu actions
function menu.OnLoggerMenuAction(pid, buttonPressed)
    buttonPressed = tonumber(buttonPressed)

    if buttonPressed == 0 then
        -- Toggle note/conductor logging: OFF <-> TRACE
        local conductorLevel = logger.config[logger.CATEGORIES.CONDUCTOR]

        if conductorLevel == nil or conductorLevel < logger.LEVELS.TRACE then
            -- Enable TRACE for detailed note logs
            logger.setLevel(logger.CATEGORIES.CONDUCTOR, logger.LEVELS.TRACE)
            tes3mp.SendMessage(pid, color.Green ..
                "Note logging: ON (shows every note played)\n" ..
                color.Yellow .. "Warning: This creates A LOT of log spam!\n", false)
            logger.info(logger.CATEGORIES.CONFIG,
                string.format("Admin %s enabled CONDUCTOR logging at TRACE level", Players[pid].name))
        else
            -- Disable to avoid spam (set back to INFO)
            logger.setLevel(logger.CATEGORIES.CONDUCTOR, logger.LEVELS.INFO)
            tes3mp.SendMessage(pid, color.Yellow ..
                "Note logging: OFF (only shows important events)\n", false)
            logger.info(logger.CATEGORIES.CONFIG,
                string.format("Admin %s disabled note-level CONDUCTOR logging", Players[pid].name))
        end

        -- Re-show menu to display updated button state
        menu.ShowLoggerMenu(pid)
    elseif buttonPressed == 1 then
        -- Show full config
        local config = logger.getConfig()
        tes3mp.SendMessage(pid, color.White .. config .. "\n", false)

        -- Re-show menu after showing config
        menu.ShowLoggerMenu(pid)
    elseif buttonPressed == 2 then
        -- Back to main menu
        menu.ShowMainMenu(pid)
    end
end

function menu.ShowMainMenu(pid)
    if not menu.IsAdmin(pid) then
        tes3mp.SendMessage(pid, color.Red .. "You don't have permission to use this.\n", false)
        return
    end

    local songCount = 0
    for _ in pairs(Bardcraft.midi.songs) do
        songCount = songCount + 1
    end

    -- Check if admin is currently performing
    local isPerforming = Bardcraft.performers[pid] and Bardcraft.performers[pid].playing
    local b = Bardcraft.band.GetBand(pid)
    local isBandLeader = b and b.leader == pid

    local chaosStatus = Bardcraft.config.allowChaos and "ENABLED" or "DISABLED"
    local inventoryStatus = Bardcraft.config.requireInstrumentInInventory and "REQUIRED" or "NOT REQUIRED"
    local activePerformances = tableHelper.getCount(Bardcraft.conductor.performances)

    local message = color.Yellow .. "=== Bardcraft Menu Menu ===\n" .. color.White ..
        "Loaded Songs: " .. songCount .. "\n" ..
        "Active Performances: " .. activePerformances .. "\n" ..
        "Allow Chaos: " .. chaosStatus .. "\n" ..
        "Instrument Inventory: " .. inventoryStatus .. "\n"

    -- Show current performance info
    if isPerforming then
        local perf = Bardcraft.conductor.performances[pid]
        if perf and perf.song then
            message = message .. color.Green .. "Now Playing: " .. perf.song.title ..
                " (" .. (perf.instrument or "Unknown") .. ")\n"
        end
    end

    message = message .. "\nWhat would you like to do?"

    local buttons = "Reload MIDI Files;Song List;"

    if isPerforming then
        -- Add "Change Part" button when performing
        buttons = buttons .. "Change Part;"

        if isBandLeader then
            buttons = buttons .. "Stop Band Performance;"
        else
            buttons = buttons .. "Stop Performance;"
        end
    end

    buttons = buttons ..
        "Stop All Performances;Toggle Chaos Mode;Toggle Inventory Requirement;Volume;Logger Settings;Exit"

    tes3mp.CustomMessageBox(pid, menu.GUI_IDS.MAIN_MENU, message, buttons)
end

function menu.ShowCategorySelect(pid)
    local customCount = 0
    local presetCount = 0

    -- Count songs in each category
    for _, song in pairs(Bardcraft.midi.songs) do
        if song.category == "preset" then
            presetCount = presetCount + 1
        else
            customCount = customCount + 1
        end
    end

    local message = color.Yellow .. "=== Bardcraft Song Browser ===\n" .. color.White ..
        "Choose a category:\n\n" ..
        "Custom Songs: " .. customCount .. "\n" ..
        "Preset Songs: " .. presetCount .. "\n"

    tes3mp.CustomMessageBox(pid, menu.GUI_IDS.CATEGORY_SELECT, message,
        "Custom Songs;Preset Songs;Back")
end

function menu.ShowSongList(pid, category)
    -- category can be "custom", "preset", or nil (for all songs - admin only)

    -- Build song list with optional category filter
    local songs = {}
    for songId, song in pairs(Bardcraft.midi.songs) do
        -- Apply category filter if specified
        local includeThis = true
        if category then
            if category == "preset" and song.category ~= "preset" then
                includeThis = false
            elseif category == "custom" and song.category == "preset" then
                includeThis = false
            end
        end

        if includeThis then
            table.insert(songs, {
                id = songId,
                title = song.title,
                parts = #song.parts,
                tempo = song.tempo or 120,
                category = song.category or "custom"
            })
        end
    end

    -- Sort by title
    table.sort(songs, function(a, b) return a.title < b.title end)

    if #songs == 0 then
        tes3mp.SendMessage(pid, color.Orange .. "No songs loaded.\n", false)
        return
    end

    -- Store for session, including the current category
    menu.sessions[pid] = menu.sessions[pid] or {}
    menu.sessions[pid].songs = songs
    menu.sessions[pid].currentCategory = category

    -- Build list items for ListBox with Back/Close options
    -- Only color the navigation items, not the songs (so highlighting works)
    local listItems = color.Red .. "< Back to Main Menu >\n"

    for i, s in ipairs(songs) do
        -- Optionally show category in the list for admins viewing all
        local categoryTag = ""
        if not category and menu.IsAdmin(pid) then
            categoryTag = string.format("[%s]", s.category or "custom")
        end
        listItems = listItems .. string.format("%s%s (%d parts, %d BPM)\n",
            s.title, categoryTag, s.parts, s.tempo)
    end

    -- Add close option at bottom
    listItems = listItems .. color.Red .. "< Close Menu >"

    local categoryName = category and (category == "preset" and "Preset" or "Custom") or "All"
    local message = color.Yellow .. string.format("=== %s Songs ===\n", categoryName) ..
        color.White .. "Total: " .. #songs .. " songs\n" ..
        "Select a song to view details:"

    -- Use ListBox - items should be newline separated, not semicolon!
    tes3mp.ListBox(pid, menu.GUI_IDS.SONG_LIST, message, listItems)

    logger.info(logger.CATEGORIES.MENU,
        string.format("%s viewing %s song list (%d songs)",
            Players[pid].name, categoryName, #songs))
end

-- Show details for a specific song
function menu.ShowSongDetails(pid, songIndex)
    if not menu.IsAdmin(pid) then return end

    local session = menu.sessions[pid]
    if not session or not session.songs[songIndex] then
        logger.warn(logger.CATEGORIES.MENU,
            string.format("Admin GUI: Invalid song index %s for pid %d",
                tostring(songIndex), pid))
        return
    end


    local songData = session.songs[songIndex]
    local song = Bardcraft.midi.songs[songData.id]

    if not song then
        tes3mp.SendMessage(pid, color.Red .. "Song not found!\n", false)
        return
    end

    -- Store selected song
    session.selectedSong = song
    session.selectedSongId = songData.id
    session.selectedSongIndex = songIndex

    -- Build parts list
    local partsInfo = ""
    for i, part in ipairs(song.parts) do
        partsInfo = partsInfo .. string.format(" Part %d: %s (%s)\n",
            i, part.title or "Untitled", part.instrument or "Unknown")
    end

    -- Check if admin is a band leader
    local b = Bardcraft.band.GetBand(pid)
    local isBandLeader = b and b.leader == pid

    local message = color.Yellow .. "=== Song Details ===\n" .. color.White ..
        "Title: " .. song.title .. "\n" ..
        "Tempo: " .. (song.tempo or 120) .. " BPM\n" ..
        "Resolution: " .. (song.resolution or 96) .. "\n" ..
        "Parts: " .. #song.parts .. "\n" ..
        partsInfo .. "\n" ..
        "What would you like to do?"

    local buttons
    if isBandLeader then
        buttons = "Adjust Tempo;Manage Parts;Test Play;Start Band Performance;Back to List"
    else
        buttons = "Adjust Tempo;Manage Parts;Test Play;Back to List"
    end

    tes3mp.CustomMessageBox(pid, menu.GUI_IDS.SONG_DETAILS, message, buttons)
end

-- Show parts management menu
function menu.ShowPartsMenu(pid)
    if not menu.IsAdmin(pid) then return end

    local session = menu.sessions[pid]
    if not session or not session.selectedSong then return end

    local song = session.selectedSong

    if #song.parts == 0 then
        tes3mp.SendMessage(pid, color.Orange .. "This song has no parts!\n", false)
        menu.ShowSongDetails(pid, session.selectedSongIndex)
        return
    end

    -- Instrument ID to name mapping (from midi.lua)
    local instrumentNames = {
        [1] = "Lute",
        [2] = "BassFlute",
        [3] = "Ocarina",
        [4] = "Fiddle",
        [5] = "Drum",
        [0] = "None"
    }

    -- Build parts list with buttons for each part
    local buttonList = {}

    for i, part in ipairs(song.parts) do
        local instrumentName = instrumentNames[part.instrument] or "Unknown"
        table.insert(buttonList, instrumentName) -- Just the instrument name as button text
    end

    table.insert(buttonList, "Delete a Part")
    table.insert(buttonList, "Back to Song Details")

    local message = color.Yellow .. "=== Manage Parts ===\n" .. color.White ..
        "Song: " .. song.title .. "\n" ..
        "Total Parts: " .. #song.parts .. "\n\n" ..
        "Select a part to change its instrument:"

    tes3mp.CustomMessageBox(pid, menu.GUI_IDS.PARTS_MENU, message,
        table.concat(buttonList, ";"))
end

-- Cycle instrument for a part
function menu.CyclePartInstrument(pid, partIndex)
    if not menu.IsAdmin(pid) then return end

    local session = menu.sessions[pid]
    if not session or not session.selectedSong then return end


    local song = Bardcraft.midi.songs[session.selectedSongId]

    if not song or not song.parts[partIndex] then
        tes3mp.SendMessage(pid, color.Red .. "Invalid part!\n", false)
        return
    end

    local part = song.parts[partIndex]

    -- Define available instruments (from midi.lua instrument mappings)
    local instrumentList = {
        { id = 1, name = "Lute" },
        { id = 2, name = "BassFlute" },
        { id = 3, name = "Ocarina" },
        { id = 4, name = "Fiddle" },
        { id = 5, name = "Drum" },
    }

    -- Find current instrument index
    local currentId = part.instrument
    if type(currentId) ~= "number" then
        currentId = 1 -- Default to Lute
    end

    local currentIndex = 1
    for i, inst in ipairs(instrumentList) do
        if inst.id == currentId then
            currentIndex = i
            break
        end
    end

    -- Cycle to next instrument
    local nextIndex = (currentIndex % #instrumentList) + 1
    local newInstrument = instrumentList[nextIndex]

    -- Update the part
    local oldInstrumentName = instrumentList[currentIndex].name
    part.instrument = newInstrument.id
    part.title = newInstrument.name
    if #song.parts > 1 then
        -- Add number suffix if multiple parts
        local sameInstrumentCount = 0
        for i = 1, partIndex do
            if song.parts[i].instrument == newInstrument.id then
                sameInstrumentCount = sameInstrumentCount + 1
            end
        end
        if sameInstrumentCount > 0 then
            part.title = newInstrument.name .. " " .. sameInstrumentCount
        end
    end

    tes3mp.SendMessage(pid, color.Green ..
        string.format("[Bardcraft Menu] Changed Part %d instrument: %s → %s\n",
            partIndex, oldInstrumentName, newInstrument.name), false)

    logger.info(logger.CATEGORIES.MENU,
        string.format("Admin %s changed part %d instrument in '%s': %s → %s",
            Players[pid].name, partIndex, song.title, oldInstrumentName, newInstrument.name))

    -- Return to parts menu to show updated instrument
    menu.ShowPartsMenu(pid)
end

-- Show delete part confirmation
function menu.ShowDeletePartConfirm(pid)
    if not menu.IsAdmin(pid) then return end

    local session = menu.sessions[pid]
    if not session or not session.selectedSong then return end

    local song = session.selectedSong

    if #song.parts == 0 then
        tes3mp.SendMessage(pid, color.Orange .. "This song has no parts to delete!\n", false)
        menu.ShowPartsMenu(pid)
        return
    end

    -- Build parts list for deletion
    local buttonList = {}

    for i, part in ipairs(song.parts) do
        local instrumentName = part.title or part.instrument or "Unknown"
        table.insert(buttonList, string.format("Delete Part %d: %s", i, instrumentName))
    end

    table.insert(buttonList, "Cancel")

    local message = color.Yellow .. "=== Delete Part ===\n" .. color.Red ..
        "WARNING: This will permanently remove the part!\n" .. color.White ..
        "Song: " .. song.title .. "\n" ..
        "Select part to delete:"

    tes3mp.CustomMessageBox(pid, menu.GUI_IDS.CONFIRM_DELETE_PART, message,
        table.concat(buttonList, ";"))
end

-- Delete a part from the song
function menu.DeletePart(pid, partIndex)
    if not menu.IsAdmin(pid) then return end

    local session = menu.sessions[pid]
    if not session or not session.selectedSong or not session.selectedSongId then return end


    local song = Bardcraft.midi.songs[session.selectedSongId]

    if not song or not song.parts[partIndex] then
        tes3mp.SendMessage(pid, color.Red .. "Invalid part!\n", false)
        return
    end

    local deletedPart = song.parts[partIndex]
    local deletedPartName = deletedPart.title or deletedPart.instrument or "Unknown"

    -- Remove the part from the parts array
    table.remove(song.parts, partIndex)

    -- Remove all notes belonging to this part
    local removedNoteCount = 0
    local newNotes = {}
    for _, note in ipairs(song.notes or {}) do
        if note.part ~= partIndex then
            -- Keep notes from other parts, but adjust part index if needed
            if note.part > partIndex then
                note.part = note.part - 1
            end
            table.insert(newNotes, note)
        else
            removedNoteCount = removedNoteCount + 1
        end
    end
    song.notes = newNotes

    -- Update part indices for remaining parts
    for i, part in ipairs(song.parts) do
        part.index = i
    end

    tes3mp.SendMessage(pid, color.Green ..
        string.format("[Bardcraft Menu] Deleted Part %d (%s) from '%s'\n" ..
            "Removed %d notes.\n",
            partIndex, deletedPartName, song.title, removedNoteCount), false)

    logger.info(logger.CATEGORIES.MENU,
        string.format("Admin %s deleted part %d (%s) from '%s', removed %d notes",
            Players[pid].name, partIndex, deletedPartName, song.title, removedNoteCount))

    -- Return to parts menu
    menu.ShowPartsMenu(pid)
end

function menu.ShowTempoAdjust(pid)
    if not menu.IsAdmin(pid) then return end

    local session = menu.sessions[pid]
    if not session or not session.selectedSong then return end

    local song = session.selectedSong
    local currentTempo = song.tempo or 120

    local message = color.Yellow .. "=== Adjust Tempo ===\n" .. color.White ..
        "Song: " .. song.title .. "\n" ..
        "Current Tempo: " .. currentTempo .. " BPM\n\n" ..
        "Enter new tempo (60-240 BPM):"

    tes3mp.InputDialog(pid, menu.GUI_IDS.TEMPO_ADJUST, message, tostring(currentTempo))
end

-- Confirm reload MIDI files
function menu.ShowReloadConfirm(pid)
    if not menu.IsAdmin(pid) then return end

    local message = color.Yellow .. "=== Reload MIDI Files ===\n" .. color.White ..
        "This will reload all MIDI files from disk.\n" ..
        "Any performances in progress will continue with old data.\n\n" ..
        "Are you sure?"

    tes3mp.CustomMessageBox(pid, menu.GUI_IDS.CONFIRM_RELOAD, message,
        "Yes, Reload;Cancel")
end

-- Handle reload action
function menu.ReloadMidiFiles(pid)
    if not menu.IsAdmin(pid) then return end

    tes3mp.SendMessage(pid, color.Green .. "[Bardcraft Menu] Reloading MIDI files...\n", false)


    local oldCount = tableHelper.getCount(Bardcraft.midi.songs)

    -- Reload
    Bardcraft.midi.LoadMidiFiles()

    local newCount = tableHelper.getCount(Bardcraft.midi.songs)

    tes3mp.SendMessage(pid, color.Green ..
        string.format("[Bardcraft Menu] Reload complete! Songs: %d → %d\n",
            oldCount, newCount), false)

    logger.info(logger.CATEGORIES.MENU,
        string.format("Admin %s reloaded MIDI files: %d → %d songs",
            Players[pid].name, oldCount, newCount))
end

-- Handle tempo change with proper input sanitization
function menu.SetTempo(pid, newTempo)
    if not menu.IsAdmin(pid) then return end

    local session = menu.sessions[pid]
    if not session or not session.selectedSong or not session.selectedSongId then
        logger.warn(logger.CATEGORIES.MENU,
            string.format("Admin GUI: No selected song for pid %d", pid))
        return
    end

    -- Sanitize input - convert to string first, then extract only digits
    local cleanInput = tostring(newTempo):gsub("[^0-9]", "")

    if cleanInput == "" then
        tes3mp.SendMessage(pid, color.Red .. "Invalid tempo! Please enter a number between 60-240.\n", false)
        logger.warn(logger.CATEGORIES.MENU,
            string.format("Admin %s entered invalid tempo: '%s'",
                Players[pid].name, tostring(newTempo)))
        return
    end

    local tempo = tonumber(cleanInput)

    if not tempo then
        tes3mp.SendMessage(pid, color.Red .. "Invalid tempo! Could not parse number.\n", false)
        return
    end

    if tempo < 60 or tempo > 240 then
        tes3mp.SendMessage(pid, color.Red ..
            string.format("Invalid tempo! Must be 60-240 BPM (you entered %d).\n", tempo), false)
        return
    end


    local song = Bardcraft.midi.songs[session.selectedSongId]

    if not song then
        tes3mp.SendMessage(pid, color.Red .. "Song not found!\n", false)
        return
    end

    local oldTempo = song.tempo or 120

    -- CRITICAL FIX: Only update if tempo actually changed
    -- This prevents potential issues with redundant updates
    if oldTempo == tempo then
        tes3mp.SendMessage(pid, color.Orange ..
            string.format("[Bardcraft Menu] Tempo already set to %d BPM.\n", tempo), false)
        return
    end

    song.tempo = tempo

    tes3mp.SendMessage(pid, color.Green ..
        string.format("[Bardcraft Menu] Changed tempo for '%s': %d → %d BPM\n",
            song.title, oldTempo, tempo), false)

    logger.info(logger.CATEGORIES.MENU,
        string.format("Admin %s changed tempo for '%s': %d → %d",
            Players[pid].name, song.title, oldTempo, tempo))

    -- Don't immediately show another GUI - just send a message
    -- User can navigate back manually
    tes3mp.SendMessage(pid, color.Yellow .. "Use /bcadmin to return to the menu.\n", false)
end

function menu.ShowPlayerMenu(pid)
    local songCount = 0
    for _ in pairs(Bardcraft.midi.songs) do
        songCount = songCount + 1
    end

    -- Check if player is currently performing
    local isPerforming = Bardcraft.performers[pid] and Bardcraft.performers[pid].playing
    local b = Bardcraft.band.GetBand(pid)
    local isBandLeader = b and b.leader == pid

    -- Check if there's an active performance in the cell
    local cellDescription = Players[pid].data.location.cell
    local cellPerf = Bardcraft.conductor.GetCellPerformance(cellDescription)

    local message = color.Yellow .. "=== Bardcraft Song Browser ===\n" .. color.White ..
        "Loaded Songs: " .. songCount .. "\n"

    if isPerforming then
        local perf = Bardcraft.conductor.performances[pid]
        if perf and perf.song then
            message = message .. color.Green .. "Now Playing: " .. perf.song.title ..
                " (" .. (perf.instrument or "Unknown") .. ")\n"
        end
    elseif cellPerf then
        local song = Bardcraft.midi.GetSongById(cellPerf.songId)
        if song then
            message = message .. color.Cyan .. "Nearby Performance: " .. song.title .. "\n"
        end
    end

    message = message .. "\nBrowse and play songs from the library."

    local buttons = "Song List;"

    if isPerforming then
        -- Add "Change Part" button when performing
        buttons = buttons .. "Change Part;"

        if isBandLeader then
            buttons = buttons .. "Stop Band Performance;"
        else
            buttons = buttons .. "Stop Performance;"
        end
    end

    buttons = buttons .. "Volume;Exit"

    tes3mp.CustomMessageBox(pid, menu.GUI_IDS.MAIN_MENU, message, buttons)
end

function menu.ShowCurrentSongPartSelection(pid)
    local perf = Bardcraft.conductor.performances[pid]

    if not perf or not perf.song then
        tes3mp.SendMessage(pid, color.Red .. "You're not currently performing!\n", false)
        if menu.IsAdmin(pid) then
            menu.ShowMainMenu(pid)
        else
            menu.ShowPlayerMenu(pid)
        end
        return
    end

    -- Set up session with current song
    local session = menu.sessions[pid] or {}
    menu.sessions[pid] = session

    session.selectedSong = perf.song
    session.selectedSongId = perf.song.id
    session.joiningPerformance = false
    session.changingPart = true -- Flag to indicate we're switching parts seamlessly

    -- Show the part selection menu
    menu.ShowPartSelection(pid)
end

function menu.ShowCurrentSongPartSelection(pid)
    local perf = Bardcraft.conductor.performances[pid]

    if not perf or not perf.song then
        tes3mp.SendMessage(pid, color.Red .. "You're not currently performing!\n", false)
        menu.ShowPlayerMenu(pid)
        return
    end

    -- Set up session with current song
    local session = menu.sessions[pid] or {}
    menu.sessions[pid] = session

    session.selectedSong = perf.song
    session.selectedSongId = perf.song.id
    session.joiningPerformance = false -- We're switching parts, not joining
    session.changingPart = true        -- Flag to indicate we're changing parts mid-performance

    -- Show the part selection menu
    menu.ShowPartSelection(pid)
end

function menu.ShowPlayerSongDetails(pid, songIndex)
    local session = menu.sessions[pid]

    -- Safety check: ensure we have session and songs array
    if not session or not session.songs then
        logger.warn(logger.CATEGORIES.MENU,
            string.format("No session or songs array for pid %d", pid))
        menu.ShowPlayerMenu(pid)
        return
    end

    if not session.songs[songIndex] then
        logger.warn(logger.CATEGORIES.MENU,
            string.format("Song index %s out of range for pid %d",
                tostring(songIndex), pid))
        menu.ShowPlayerMenu(pid)
        return
    end

    local songData = session.songs[songIndex]
    local song = Bardcraft.midi.songs[songData.id]

    if not song then
        tes3mp.SendMessage(pid, color.Red .. "Song not found!\n", false)
        return
    end

    -- Store selected song
    session.selectedSong = song
    session.selectedSongId = songData.id
    session.selectedSongIndex = songIndex

    -- Build parts list
    local instrumentNames = {
        [1] = "Lute",
        [2] = "BassFlute",
        [3] = "Ocarina",
        [4] = "Fiddle",
        [5] = "Drum",
        [0] = "None"
    }

    local partsInfo = ""
    for i, part in ipairs(song.parts) do
        local instrumentName = instrumentNames[part.instrument] or "Unknown"
        partsInfo = partsInfo .. string.format(" Part %d: %s\n", i, instrumentName)
    end

    -- Check for ongoing performance in cell
    local cellDescription = Players[pid].data.location.cell
    local cellPerf = Bardcraft.conductor.GetCellPerformance(cellDescription)
    local hasOngoingPerf = cellPerf and cellPerf.songId == song.id

    local message = color.Yellow .. "=== Song Details ===\n" .. color.White ..
        "Title: " .. song.title .. "\n" ..
        "Tempo: " .. (song.tempo or 120) .. " BPM\n" ..
        "Parts: " .. #song.parts .. "\n" ..
        partsInfo

    if hasOngoingPerf then
        message = message .. "\n" .. color.Green ..
            "This song is currently being performed nearby!\n"
    end

    message = message .. "\nWhat would you like to do?"

    -- Check if player is a band leader
    local b = Bardcraft.band.GetBand(pid)
    local isBandLeader = b and b.leader == pid

    local buttons
    if hasOngoingPerf then
        buttons = "Join Performance;Choose Part (Solo);Back to List"
    elseif isBandLeader then
        buttons = "Play with Band;Choose Part (Solo);Back to List"
    else
        buttons = "Choose Part (Solo);Back to List"
    end

    tes3mp.CustomMessageBox(pid, menu.GUI_IDS.SONG_DETAILS, message, buttons)
end

function menu.ShowPartSelection(pid)
    local session = menu.sessions[pid]
    if not session or not session.selectedSong then return end

    local song = session.selectedSong
    local instrumentNames = {
        [1] = "Lute",
        [2] = "BassFlute",
        [3] = "Ocarina",
        [4] = "Fiddle",
        [5] = "Drum",
        [0] = "None"
    }

    -- Initialize selected instruments if not already set
    if not session.selectedInstruments then
        session.selectedInstruments = {}
        for i, part in ipairs(song.parts) do
            session.selectedInstruments[i] = part.instrument
        end
    end

    -- Build part list with current instrument selections
    local partsInfo = ""
    for i, part in ipairs(song.parts) do
        local currentInstrument = session.selectedInstruments[i] or part.instrument
        local instrumentName = instrumentNames[currentInstrument] or "Unknown"
        partsInfo = partsInfo .. string.format("Part %d: %s\n", i, instrumentName)
    end

    local message = color.Yellow .. "=== Choose Your Part ===\n" .. color.White ..
        "Song: " .. song.title .. "\n\n" ..
        partsInfo .. "\n" ..
        "Click a part to toggle instrument, or Play:"

    -- Create buttons: one for each part + Play + Back
    local buttons = {}
    for i, part in ipairs(song.parts) do
        local currentInstrument = session.selectedInstruments[i] or part.instrument
        local instrumentName = instrumentNames[currentInstrument] or "Unknown"
        table.insert(buttons, string.format("Part %d: %s", i, instrumentName))
    end
    table.insert(buttons, "Play")
    table.insert(buttons, "Back")

    tes3mp.CustomMessageBox(pid, menu.GUI_IDS.PART_SELECTION, message,
        table.concat(buttons, ";"))
end

function menu.TogglePartSelectionInstrument(pid, partIndex)
    local session = menu.sessions[pid]
    if not session or not session.selectedSong or not session.selectedInstruments then
        return
    end

    local song = session.selectedSong
    if partIndex < 1 or partIndex > #song.parts then
        return
    end

    -- Define available instruments
    local instrumentList = { 1, 2, 3, 4, 5 } -- Lute, BassFlute, Ocarina, Fiddle, Drum

    -- Find current instrument index
    local currentInstrument = session.selectedInstruments[partIndex]
    local currentIndex = 1
    for i, instId in ipairs(instrumentList) do
        if instId == currentInstrument then
            currentIndex = i
            break
        end
    end

    -- Cycle to next instrument
    local nextIndex = (currentIndex % #instrumentList) + 1
    session.selectedInstruments[partIndex] = instrumentList[nextIndex]

    -- Show updated menu
    menu.ShowPartSelection(pid)
end

function menu.PlayWithSelectedInstruments(pid)
    local session = menu.sessions[pid]
    if not session or not session.selectedSong or not session.selectedInstruments then
        return
    end

    local song = session.selectedSong

    -- Apply the selected instruments to the song parts TEMPORARILY
    -- We'll restore them when the performance ends or when backing out

    -- Store original instruments if not already stored
    if not session.originalInstruments then
        session.originalInstruments = {}
        for i, part in ipairs(song.parts) do
            session.originalInstruments[i] = {
                instrument = part.instrument,
                title = part.title
            }
        end
    end

    -- Apply selected instruments to song parts
    local instrumentNames = {
        [1] = "Lute",
        [2] = "BassFlute",
        [3] = "Ocarina",
        [4] = "Fiddle",
        [5] = "Drum",
        [0] = "None"
    }

    for i, part in ipairs(song.parts) do
        local newInstrument = session.selectedInstruments[i]
        if newInstrument then
            part.instrument = newInstrument
            part.title = instrumentNames[newInstrument]

            -- Add number suffix if multiple parts have same instrument
            local sameInstrumentCount = 0
            for j = 1, i do
                if song.parts[j].instrument == newInstrument then
                    sameInstrumentCount = sameInstrumentCount + 1
                end
            end
            if sameInstrumentCount > 1 then
                part.title = instrumentNames[newInstrument] .. " " .. (sameInstrumentCount - 1)
            end
        end
    end

    -- Now show menu to pick which part to actually perform
    local buttons = {}
    for i = 1, #song.parts do
        local instrumentName = instrumentNames[session.selectedInstruments[i]] or "Unknown"
        table.insert(buttons, string.format("Play Part %d (%s)", i, instrumentName))
    end
    table.insert(buttons, "Back")

    local message = color.Yellow .. "=== Select Part to Play ===\n" .. color.White ..
        "Song: " .. song.title .. "\n\n" ..
        "Which part do you want to perform?"

    -- Store a flag to indicate we're in "play selection" mode
    session.playSelectionMode = true

    tes3mp.CustomMessageBox(pid, menu.GUI_IDS.PART_SELECTION, message,
        table.concat(buttons, ";"))
end

-- Show volume control menu
function menu.ShowVolumeMenu(pid)
    -- Check if player is in a band
    local b = Bardcraft.band.GetBand(pid)

    if b and b.leader == pid then
        -- Band leader - show band volume menu
        menu.ShowBandVolumeMenu(pid)
    else
        -- Solo performer - show personal volume menu
        menu.ShowPersonalVolumeMenu(pid)
    end
end

-- Show personal volume menu for solo performers
function menu.ShowPersonalVolumeMenu(pid)
    -- Get current volume and step amount from player data
    local currentVolume = Players[pid].data.customVariables.bardcraft.instrumentVolume or 1.0
    local volumePercent = math.floor(currentVolume * 100)
    local stepAmount = Players[pid].data.customVariables.bardcraft.volumeStep or 10

    local message = color.Yellow .. "=== Volume Control ===\n" .. color.White ..
        "Current Volume: " .. volumePercent .. "%\n" ..
        "Step Amount: " .. stepAmount .. "%\n\n" ..
        "Adjust your instrument volume:"

    tes3mp.CustomMessageBox(pid, menu.GUI_IDS.VOLUME_MENU, message,
        string.format("Volume Up (+%d%%);Volume Down (-%d%%);Change Step;Back", stepAmount, stepAmount))
end

function menu.ToggleInventoryRequirement(pid)
    if not menu.IsAdmin(pid) then return end

    Bardcraft.config.requireInstrumentInInventory = not Bardcraft.config.requireInstrumentInInventory

    local status = Bardcraft.config.requireInstrumentInInventory and "REQUIRED" or "NOT REQUIRED"
    local description = Bardcraft.config.requireInstrumentInInventory and
        "Players must now have bcw_ instruments in inventory to perform." or
        "Players can now perform without having instruments in inventory."

    tes3mp.SendMessage(pid, color.Green ..
        string.format("Instrument Inventory %s\n%s\n", status, description), false)

    logger.info(logger.CATEGORIES.MENU,
        string.format("Admin %s set requireInstrumentInInventory to %s",
            Players[pid].name, tostring(Bardcraft.config.requireInstrumentInInventory)))

    menu.ShowMainMenu(pid)
end

-- Show step amount adjustment dialog
function menu.ShowVolumeStepAdjust(pid)
    local currentStep = Players[pid].data.customVariables.bardcraft.volumeStep or 10

    local message = color.Yellow .. "=== Volume Step Amount ===\n" .. color.White ..
        "Current Step: " .. currentStep .. "%\n\n" ..
        "Enter new step amount (1-100):"

    tes3mp.InputDialog(pid, menu.GUI_IDS.VOLUME_STEP_ADJUST, message, tostring(currentStep))
end

-- Adjust player volume
function menu.AdjustVolume(pid, delta)
    local currentVolume = Players[pid].data.customVariables.bardcraft.instrumentVolume or 1.0
    local volumePercent = math.floor(currentVolume * 100)

    -- Apply delta
    volumePercent = volumePercent + delta

    -- Clamp to 0-1000
    volumePercent = math.max(0, math.min(1000, volumePercent))

    -- Save new volume
    local newVolume = volumePercent / 100.0
    Players[pid].data.customVariables.bardcraft.instrumentVolume = newVolume
    Players[pid]:Save()

    tes3mp.SendMessage(pid, color.Green ..
        string.format("Volume set to %d%% (%.1fx)\n", volumePercent, newVolume), false)

    -- Show menu again
    menu.ShowPersonalVolumeMenu(pid)
end

-- Set volume step amount
function menu.SetVolumeStep(pid, stepInput)
    local step = tonumber(stepInput)

    if not step or step < 1 or step > 100 then
        tes3mp.SendMessage(pid, color.Red .. "Invalid step amount! Must be 1-100.\n", false)
        menu.ShowPersonalVolumeMenu(pid)
        return
    end

    -- Save to player data
    Players[pid].data.customVariables.bardcraft.volumeStep = step
    Players[pid]:Save()

    tes3mp.SendMessage(pid, color.Green ..
        string.format("Volume step set to %d%%\n", step), false)

    logger.info(logger.CATEGORIES.MENU,
        string.format("Player %d set volume step to %d", pid, step))

    menu.ShowPersonalVolumeMenu(pid)
end

-- Show band volume control menu
function menu.ShowBandVolumeMenu(pid)
    local b = Bardcraft.band.GetBand(pid)

    if not b or b.leader ~= pid then
        tes3mp.SendMessage(pid, color.Red .. "Only the band leader can adjust band volumes.\n", false)
        return
    end

    local session = menu.sessions[pid] or {}
    menu.sessions[pid] = session

    -- Get step amount from player data
    local stepAmount = Players[pid].data.customVariables.bardcraft.bandVolumeStep or 10

    -- Build member list with volumes
    local memberInfo = ""
    for _, memberId in ipairs(b.members) do
        if Players[memberId] and Players[memberId]:IsLoggedIn() then
            local volume = Players[memberId].data.customVariables.bardcraft.instrumentVolume or 1.0
            local volumePercent = math.floor(volume * 100)
            local prefix = (memberId == b.leader) and "* " or "  "
            memberInfo = memberInfo .. string.format("%s%s: %d%%\n",
                prefix, Players[memberId].name, volumePercent)
        end
    end

    -- Build buttons for each member
    local buttons = {}
    for _, memberId in ipairs(b.members) do
        if Players[memberId] and Players[memberId]:IsLoggedIn() then
            table.insert(buttons, Players[memberId].name .. " +")
            table.insert(buttons, Players[memberId].name .. " -")
        end
    end
    table.insert(buttons, "Change Step")
    table.insert(buttons, "Back")

    local message = color.Yellow .. "=== Band Volume Control ===\n" .. color.White ..
        "Step Amount: " .. stepAmount .. "%\n\n" ..
        memberInfo .. "\n" ..
        "Select member to adjust:"

    tes3mp.CustomMessageBox(pid, menu.GUI_IDS.BAND_VOLUME_MENU, message,
        table.concat(buttons, ";"))

    -- Store member list for processing button clicks
    session.bandMembers = b.members
end

-- Adjust band member volume
function menu.AdjustBandMemberVolume(pid, memberIndex, delta)
    local session = menu.sessions[pid]
    if not session or not session.bandMembers then return end

    local b = Bardcraft.band.GetBand(pid)
    if not b or b.leader ~= pid then return end

    local memberId = session.bandMembers[memberIndex]
    if not memberId or not Players[memberId] or not Players[memberId]:IsLoggedIn() then
        tes3mp.SendMessage(pid, color.Red .. "Invalid band member.\n", false)
        menu.ShowBandVolumeMenu(pid)
        return
    end

    local currentVolume = Players[memberId].data.customVariables.bardcraft.instrumentVolume or 1.0
    local volumePercent = math.floor(currentVolume * 100)

    volumePercent = volumePercent + delta
    volumePercent = math.max(0, math.min(1000, volumePercent))

    local newVolume = volumePercent / 100.0
    Players[memberId].data.customVariables.bardcraft.instrumentVolume = newVolume
    Players[memberId]:Save()

    tes3mp.SendMessage(pid, color.Green ..
        string.format("%s's volume set to %d%%\n", Players[memberId].name, volumePercent), false)

    tes3mp.SendMessage(memberId, color.Yellow ..
        string.format("Band leader adjusted your volume to %d%%\n", volumePercent), false)

    menu.ShowBandVolumeMenu(pid)
end

-- Set band volume step amount
function menu.SetBandVolumeStep(pid, stepInput)
    local step = tonumber(stepInput)

    if not step or step < 1 or step > 100 then
        tes3mp.SendMessage(pid, color.Red .. "Invalid step amount! Must be 1-100.\n", false)
        menu.ShowBandVolumeMenu(pid)
        return
    end

    -- Save to player data
    Players[pid].data.customVariables.bardcraft.bandVolumeStep = step
    Players[pid]:Save()

    tes3mp.SendMessage(pid, color.Green ..
        string.format("Band volume step set to %d%%\n", step), false)

    logger.info(logger.CATEGORIES.MENU,
        string.format("Player %d set band volume step to %d", pid, step))

    menu.ShowBandVolumeMenu(pid)
end

function menu.ToggleChaosMode(pid)
    if not menu.IsAdmin(pid) then return end


    Bardcraft.config.allowChaos = not Bardcraft.config.allowChaos

    local status = Bardcraft.config.allowChaos and "ENABLED" or "DISABLED"
    local description = Bardcraft.config.allowChaos and
        "Players can now play different songs in the same area." or
        "Players must join the same song when performing together."

    tes3mp.SendMessage(pid, color.Green ..
        string.format("Chaos Mode %s\n%s\n", status, description), false)

    logger.info(logger.CATEGORIES.MENU,
        string.format("Admin %s set allowChaos to %s",
            Players[pid].name, tostring(Bardcraft.config.allowChaos)))

    logger.info(logger.CATEGORIES.MENU,
        string.format("Chaos mode toggled to %s by admin %s",
            status, Players[pid].name))

    menu.ShowMainMenu(pid)
end

function menu.OnGUIAction(eventStatus, pid, idGui, data)
    -- Early return if not an admin GUI
    if idGui ~= menu.GUI_IDS.MAIN_MENU and
        idGui ~= menu.GUI_IDS.CATEGORY_SELECT and
        idGui ~= menu.GUI_IDS.SONG_LIST and
        idGui ~= menu.GUI_IDS.SONG_DETAILS and
        idGui ~= menu.GUI_IDS.TEMPO_ADJUST and
        idGui ~= menu.GUI_IDS.CONFIRM_RELOAD and
        idGui ~= menu.GUI_IDS.PARTS_MENU and
        idGui ~= menu.GUI_IDS.CONFIRM_DELETE_PART and
        idGui ~= menu.GUI_IDS.PART_SELECTION and
        idGui ~= menu.GUI_IDS.CHAOS_TOGGLE and
        idGui ~= menu.GUI_IDS.LOGGER_MENU and
        idGui ~= menu.GUI_IDS.CONFIRM_STOP_ALL and
        idGui ~= menu.GUI_IDS.VOLUME_MENU and
        idGui ~= menu.GUI_IDS.VOLUME_STEP_ADJUST and
        idGui ~= menu.GUI_IDS.BAND_VOLUME_MENU then
        return
    end

    -- Log all GUI actions
    logger.info(logger.CATEGORIES.MENU,
        string.format("menu.LUA GUI Action: pid=%d, gui=%d, data='%s'",
            pid, idGui, tostring(data)))

    -- Prevent duplicate processing
    local now = tes3mp.GetMillisecondsSinceServerStart() / 1000
    local actionKey = string.format("%d_%d_%s", pid, idGui, tostring(data))

    if menu.lastAction and menu.lastAction.key == actionKey and (now - menu.lastAction.time) < 0.1 then
        logger.warn(logger.CATEGORIES.MENU,
            string.format("Prevented duplicate GUI action: %s", actionKey))
        return
    end

    menu.lastAction = { key = actionKey, time = now }

    local isAdmin = menu.IsAdmin(pid)

    -- CATEGORY_SELECT (NEW)
    if idGui == menu.GUI_IDS.CATEGORY_SELECT then
        local buttonIndex = tonumber(data)

        if buttonIndex == 0 then
            -- Custom Songs
            menu.ShowSongList(pid, "custom")
        elseif buttonIndex == 1 then
            -- Preset Songs
            menu.ShowSongList(pid, "preset")
        else
            -- Back
            if isAdmin then
                menu.ShowMainMenu(pid)
            else
                menu.ShowPlayerMenu(pid)
            end
        end
        -- MAIN_MENU
        -- MAIN_MENU
        -- MAIN_MENU
    elseif idGui == menu.GUI_IDS.MAIN_MENU then
        local buttonIndex = tonumber(data)

        if isAdmin then
            -- Check if admin is performing to calculate button offsets
            local isPerforming = Bardcraft.performers[pid] and Bardcraft.performers[pid].playing
            local b = Bardcraft.band.GetBand(pid)
            local isBandLeader = b and b.leader == pid

            if buttonIndex == 0 then
                -- Reload MIDI Files
                menu.ShowReloadConfirm(pid)
            elseif buttonIndex == 1 then
                -- Song List
                menu.ShowCategorySelect(pid)
            elseif isPerforming and buttonIndex == 2 then
                -- Change Part (only when performing)
                menu.ShowCurrentSongPartSelection(pid)
            elseif isPerforming and buttonIndex == 3 then
                -- Stop Performance (only when performing)
                menu.StopCurrentPerformance(pid)
                menu.ShowMainMenu(pid)
            elseif buttonIndex == (isPerforming and 4 or 2) then
                -- Stop All Performances
                menu.ShowStopAllConfirm(pid)
            elseif buttonIndex == (isPerforming and 5 or 3) then
                -- Toggle Chaos Mode
                menu.ToggleChaosMode(pid)
            elseif buttonIndex == (isPerforming and 6 or 4) then
                -- Toggle Inventory Requirement
                menu.ToggleInventoryRequirement(pid)
            elseif buttonIndex == (isPerforming and 7 or 5) then
                -- Volume
                menu.ShowVolumeMenu(pid)
            elseif buttonIndex == (isPerforming and 8 or 6) then
                -- Logger Settings
                menu.ShowLoggerMenu(pid)
            elseif buttonIndex == (isPerforming and 9 or 7) then
                -- Exit
                menu.sessions[pid] = nil
            else
                menu.sessions[pid] = nil
            end
        else
            -- Player menu
            local isPerforming = Bardcraft.performers[pid] and Bardcraft.performers[pid].playing
            local b = Bardcraft.band.GetBand(pid)
            local isBandLeader = b and b.leader == pid

            if buttonIndex == 0 then
                -- Song List
                menu.ShowCategorySelect(pid)
            elseif isPerforming and buttonIndex == 1 then
                -- Change Part (only shown when performing)
                menu.ShowCurrentSongPartSelection(pid)
            elseif isPerforming and buttonIndex == 2 then
                -- Stop Performance (shown when performing)
                menu.StopCurrentPerformance(pid)
                menu.ShowPlayerMenu(pid)
            elseif buttonIndex == (isPerforming and 3 or 1) then
                -- Volume
                menu.ShowVolumeMenu(pid)
            elseif buttonIndex == (isPerforming and 4 or 2) then
                -- Exit
                menu.sessions[pid] = nil
            else
                menu.sessions[pid] = nil
            end
        end
    elseif idGui == menu.GUI_IDS.LOGGER_MENU then
        menu.OnLoggerMenuAction(pid, data)

        -- SONG_LIST
    elseif idGui == menu.GUI_IDS.SONG_LIST then
        local selectedIndex = tonumber(data)

        if selectedIndex == nil or selectedIndex == -1 then
            -- Go back to category selection
            menu.ShowCategorySelect(pid)
            return
        end

        local session = menu.sessions[pid]
        if not session then return end

        if selectedIndex == 0 then
            -- Back button - return to category select
            menu.ShowCategorySelect(pid)
            return
        end

        if selectedIndex == #session.songs + 1 then
            menu.sessions[pid] = nil
            return
        end

        local songIndex = selectedIndex

        if songIndex < 1 or songIndex > #session.songs then
            -- Invalid selection, show list again
            menu.ShowSongList(pid, session.currentCategory)
            return
        end

        if isAdmin then
            menu.ShowSongDetails(pid, songIndex)
        else
            menu.ShowPlayerSongDetails(pid, songIndex)
        end

        -- SONG_DETAILS
    elseif idGui == menu.GUI_IDS.SONG_DETAILS then
        local buttonIndex = tonumber(data)
        local session = menu.sessions[pid]

        if isAdmin then
            local b = Bardcraft.band.GetBand(pid)
            local isBandLeader = b and b.leader == pid

            if buttonIndex == 0 then
                menu.ShowTempoAdjust(pid)
            elseif buttonIndex == 1 then
                menu.ShowPartsMenu(pid)
            elseif buttonIndex == 2 then
                menu.ShowPartSelection(pid)
                -- Set flag to indicate this is NOT joining an existing performance
                session.joiningPerformance = false
            elseif buttonIndex == 3 then
                if isBandLeader then
                    -- Start Band Performance
                    if session and session.selectedSong then
                        Bardcraft.band.StartPerformance(b.id, session.selectedSong.title)
                    end
                else
                    -- Back to List (when not a band leader, this is button 3)
                    menu.ShowSongList(pid)
                end
            elseif buttonIndex == 4 then
                -- Back to List (when band leader, this is button 4)
                menu.ShowSongList(pid)
            else
                menu.sessions[pid] = nil
            end
        else
            local b = Bardcraft.band.GetBand(pid)
            local isBandLeader = b and b.leader == pid

            local cellDescription = Players[pid].data.location.cell
            local cellPerf = Bardcraft.conductor.GetCellPerformance(cellDescription)
            local hasOngoingPerf = cellPerf and session and session.selectedSong and
                cellPerf.songId == session.selectedSong.id

            if hasOngoingPerf then
                if buttonIndex == 0 then
                    menu.ShowPartSelection(pid)
                    session.joiningPerformance = true
                elseif buttonIndex == 1 then
                    menu.ShowPartSelection(pid)
                    session.joiningPerformance = false
                elseif buttonIndex == 2 then
                    menu.ShowSongList(pid)
                else
                    menu.sessions[pid] = nil
                end
            elseif isBandLeader then
                if buttonIndex == 0 then
                    if session and session.selectedSong then
                        Bardcraft.band.StartPerformance(b.id, session.selectedSong.title)
                    end
                elseif buttonIndex == 1 then
                    menu.ShowPartSelection(pid)
                    session.joiningPerformance = false
                elseif buttonIndex == 2 then
                    menu.ShowSongList(pid)
                else
                    menu.sessions[pid] = nil
                end
            else
                if buttonIndex == 0 then
                    menu.ShowPartSelection(pid)
                    session.joiningPerformance = false
                elseif buttonIndex == 1 then
                    menu.ShowSongList(pid)
                else
                    menu.sessions[pid] = nil
                end
            end
        end

        -- PART_SELECTION
    elseif idGui == menu.GUI_IDS.PART_SELECTION then
        local buttonIndex = tonumber(data)
        local session = menu.sessions[pid]

        if not session or not session.selectedSong then return end

        local numParts = #session.selectedSong.parts

        -- Check if we're in "play selection" mode (after clicking "Play" button)
        if session.playSelectionMode then
            -- User is selecting which part to actually perform
            if buttonIndex >= 0 and buttonIndex < numParts then
                local partIndex = buttonIndex + 1
                local part = session.selectedSong.parts[partIndex]

                -- The part already has the correct instrument assigned from PlayWithSelectedInstruments
                local instrumentName = part.title or "Lute"

                -- Check if we're changing parts mid-performance (seamless switch)
                if session.changingPart then
                    -- Use the new SwitchPerformancePart function for seamless transition
                    local success = Bardcraft.conductor.SwitchPerformancePart(pid, part, instrumentName)

                    if success then
                        tes3mp.SendMessage(pid, color.Green ..
                            string.format("Switched to: %s\n", instrumentName), false)
                    else
                        tes3mp.SendMessage(pid, color.Red ..
                            "Failed to switch part!\n", false)
                    end
                else
                    -- Starting a new performance (not switching)
                    if session.joiningPerformance then
                        Bardcraft.conductor.JoinCellPerformance(pid, partIndex)
                    else
                        Bardcraft.conductor.StartPerformance(pid, session.selectedSong.title, instrumentName)
                    end
                end

                -- Clear flags
                session.joiningPerformance = nil
                session.playSelectionMode = nil
                session.selectedInstruments = nil
                session.changingPart = nil

                -- Restore original instruments after starting/switching performance
                if session.originalInstruments then
                    local song = session.selectedSong
                    for i, original in ipairs(session.originalInstruments) do
                        if song.parts[i] then
                            song.parts[i].instrument = original.instrument
                            song.parts[i].title = original.title
                        end
                    end
                    session.originalInstruments = nil
                end
            else
                -- Back button - restore original instruments
                if session.originalInstruments then
                    local song = session.selectedSong
                    for i, original in ipairs(session.originalInstruments) do
                        if song.parts[i] then
                            song.parts[i].instrument = original.instrument
                            song.parts[i].title = original.title
                        end
                    end
                    session.originalInstruments = nil
                end
                session.playSelectionMode = nil
                session.changingPart = nil
                menu.ShowPartSelection(pid)
            end
        else
            -- User is toggling instruments or clicking Play/Back
            if buttonIndex >= 0 and buttonIndex < numParts then
                -- Toggle instrument for this part
                menu.TogglePartSelectionInstrument(pid, buttonIndex + 1)
            elseif buttonIndex == numParts then
                -- Play button
                menu.PlayWithSelectedInstruments(pid)
            else
                -- Back button - restore original instruments if they exist
                if session.originalInstruments then
                    local song = session.selectedSong
                    for i, original in ipairs(session.originalInstruments) do
                        if song.parts[i] then
                            song.parts[i].instrument = original.instrument
                            song.parts[i].title = original.title
                        end
                    end
                    session.originalInstruments = nil
                end
                session.selectedInstruments = nil
                -- Check if we have selectedSongIndex (came from song list)
                -- or if we're in changingPart mode (came from Change Part button)
                if session.selectedSongIndex and not session.changingPart then
                    if menu.IsAdmin(pid) then
                        menu.ShowSongDetails(pid, session.selectedSongIndex)
                    else
                        menu.ShowPlayerSongDetails(pid, session.selectedSongIndex)
                    end
                else
                    -- We came from "Change Part" button, go back to main menu
                    session.changingPart = nil
                    if menu.IsAdmin(pid) then
                        menu.ShowMainMenu(pid)
                    else
                        menu.ShowPlayerMenu(pid)
                    end
                end
            end
        end

        -- TEMPO_ADJUST
    elseif idGui == menu.GUI_IDS.TEMPO_ADJUST then
        if not isAdmin then return end

        if data and data ~= "" then
            menu.SetTempo(pid, data)
        else
            local session = menu.sessions[pid]
            if session and session.selectedSongIndex then
                menu.ShowSongDetails(pid, session.selectedSongIndex)
            end
        end

        -- CONFIRM_RELOAD
    elseif idGui == menu.GUI_IDS.CONFIRM_RELOAD then
        if not isAdmin then return end

        local buttonIndex = tonumber(data)
        if buttonIndex == 0 then
            menu.ReloadMidiFiles(pid)
            menu.ShowMainMenu(pid)
        else
            menu.ShowMainMenu(pid)
        end

        -- PARTS_MENU
    elseif idGui == menu.GUI_IDS.PARTS_MENU then
        if not isAdmin then return end

        local buttonIndex = tonumber(data)
        local session = menu.sessions[pid]

        if not session or not session.selectedSong then return end

        local numParts = #session.selectedSong.parts

        if buttonIndex >= 0 and buttonIndex < numParts then
            menu.CyclePartInstrument(pid, buttonIndex + 1)
        elseif buttonIndex == numParts then
            menu.ShowDeletePartConfirm(pid)
        else
            menu.ShowSongDetails(pid, session.selectedSongIndex)
        end

        -- CONFIRM_DELETE_PART
    elseif idGui == menu.GUI_IDS.CONFIRM_DELETE_PART then
        if not isAdmin then return end

        local buttonIndex = tonumber(data)
        local session = menu.sessions[pid]

        if not session or not session.selectedSong then return end

        local numParts = #session.selectedSong.parts

        if buttonIndex >= 0 and buttonIndex < numParts then
            menu.DeletePart(pid, buttonIndex + 1)
        else
            menu.ShowPartsMenu(pid)
        end

        -- CONFIRM_STOP_ALL
    elseif idGui == menu.GUI_IDS.CONFIRM_STOP_ALL then
        if not isAdmin then return end

        local buttonIndex = tonumber(data)
        if buttonIndex == 0 then
            menu.StopAllPerformances(pid)
            menu.ShowMainMenu(pid)
        else
            menu.ShowMainMenu(pid)
        end

        -- VOLUME_MENU
    elseif idGui == menu.GUI_IDS.VOLUME_MENU then
        local buttonIndex = tonumber(data)
        local stepAmount = Players[pid].data.customVariables.bardcraft.volumeStep or 10

        if buttonIndex == 0 then
            -- Volume Up
            menu.AdjustVolume(pid, stepAmount)
        elseif buttonIndex == 1 then
            -- Volume Down
            menu.AdjustVolume(pid, -stepAmount)
        elseif buttonIndex == 2 then
            -- Change Step
            menu.ShowVolumeStepAdjust(pid)
        else
            -- Back
            if isAdmin then
                menu.ShowMainMenu(pid)
            else
                menu.ShowPlayerMenu(pid)
            end
        end

        -- VOLUME_STEP_ADJUST
    elseif idGui == menu.GUI_IDS.VOLUME_STEP_ADJUST then
        if data and data ~= "" then
            local session = menu.sessions[pid]
            local b = Bardcraft.band.GetBand(pid)

            -- Check if this is for band volume or personal volume
            if b and b.leader == pid and session and session.bandMembers then
                menu.SetBandVolumeStep(pid, data)
            else
                menu.SetVolumeStep(pid, data)
            end
        else
            local b = Bardcraft.band.GetBand(pid)
            if b and b.leader == pid then
                menu.ShowBandVolumeMenu(pid)
            else
                menu.ShowPersonalVolumeMenu(pid)
            end
        end

        -- BAND_VOLUME_MENU
    elseif idGui == menu.GUI_IDS.BAND_VOLUME_MENU then
        local buttonIndex = tonumber(data)
        local session = menu.sessions[pid]

        if not session or not session.bandMembers then
            menu.ShowBandVolumeMenu(pid)
            return
        end

        local numMembers = #session.bandMembers
        local numButtons = numMembers * 2 -- +/- for each member
        local stepAmount = Players[pid].data.customVariables.bardcraft.bandVolumeStep or 10

        if buttonIndex < numButtons then
            -- Member volume adjustment
            local memberIndex = math.floor(buttonIndex / 2) + 1
            local isIncrease = (buttonIndex % 2) == 0
            local delta = isIncrease and stepAmount or -stepAmount

            menu.AdjustBandMemberVolume(pid, memberIndex, delta)
        elseif buttonIndex == numButtons then
            -- Change Step
            local currentStep = Players[pid].data.customVariables.bardcraft.bandVolumeStep or 10
            local message = color.Yellow .. "=== Band Volume Step ===\n" .. color.White ..
                "Current Step: " .. currentStep .. "%\n\n" ..
                "Enter new step amount (1-100):"

            tes3mp.InputDialog(pid, menu.GUI_IDS.VOLUME_STEP_ADJUST, message, tostring(currentStep))
        else
            -- Back
            if isAdmin then
                menu.ShowMainMenu(pid)
            else
                menu.ShowPlayerMenu(pid)
            end
        end
    end
end

-- Chat command
function menu.ChatCommand(pid, cmd)
    if not Players[pid] or not Players[pid]:IsLoggedIn() then return end

    if not menu.IsAdmin(pid) then
        tes3mp.SendMessage(pid, color.Red .. "You don't have permission to use admin commands.\n", false)
        return
    end

    local subcommand = cmd[2]

    if not subcommand or subcommand == "menu" then
        menu.ShowMainMenu(pid)
    elseif subcommand == "reload" then
        menu.ReloadMidiFiles(pid)
    elseif subcommand == "songs" then
        menu.ShowSongList(pid)
    elseif subcommand == "help" then
        local helpText = color.Yellow .. "Bardcraft Menu Commands:\n" .. color.White ..
            "/bcadmin - Open admin menu\n" ..
            "/bcadmin reload - Reload MIDI files\n" ..
            "/bcadmin songs - List all songs\n"
        tes3mp.SendMessage(pid, helpText, false)
    else
        tes3mp.SendMessage(pid, color.Orange .. "Unknown subcommand. Use /bcadmin help\n", false)
    end
end

return menu
