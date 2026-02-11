--[[
Bardcraft for TES3MP
Basic port of the OpenMW Lua Bardcraft mod

Installation:
1. Create folder: server/scripts/custom/bardcraft/
2. Place all tes3mp scripts in that folder
3. Add to customScripts.lua: equire("custom.bardcraft.init")
4. Download and install the Bardcraft mod from https://www.nexusmods.com/morrowind/mods/56814?tab=files
]]

local Bardcraft = {}

local logger = require("custom.bardcraft.logger")

-- Dependencies
-- Bardcraft.data = require("custom.bardcraft.data")
Bardcraft.config = require("custom.bardcraft.config")
Bardcraft.performer = require("custom.bardcraft.performer")
Bardcraft.midi = require("custom.bardcraft.midi")
Bardcraft.instruments = require("custom.bardcraft.instruments")
Bardcraft.soundRecords = require("custom.bardcraft.soundRecords")
Bardcraft.band = require("custom.bardcraft.band")
Bardcraft.menu = require("custom.bardcraft.menu")
Bardcraft.Inventory = require("custom.bardcraft.inventory")
Bardcraft.conductor = require("custom.bardcraft.conductor")
if Bardcraft.menu and Bardcraft.menu.SetBardcraft then
    Bardcraft.menu.SetBardcraft(Bardcraft)
end
if Bardcraft.conductor and Bardcraft.conductor.SetBardcraft then
    Bardcraft.conductor.SetBardcraft(Bardcraft)
end
-- Storage for active performers
Bardcraft.performers = {}

-------------
-- METHODS --
-------------

function Bardcraft.OnObjectPlaceValidator(eventStatus, pid, cellDescription, objects)
    tes3mp.ReadReceivedObjectList()

    for objectIndex = 0, tes3mp.GetObjectListSize() - 1 do
        local refId = tes3mp.GetObjectRefId(objectIndex)

        if Bardcraft.Inventory.IsBardcraftInstrument(refId) then
            local worldId = Bardcraft.Inventory.ConvertWeaponToWorld(refId)

            if worldId ~= refId then
                -- Get object details before canceling
                local refNum = tes3mp.GetObjectRefNum(objectIndex)
                local mpNum = tes3mp.GetObjectMpNum(objectIndex)
                local count = tes3mp.GetObjectCount(objectIndex)
                local charge = tes3mp.GetObjectCharge(objectIndex)
                local enchantmentCharge = tes3mp.GetObjectEnchantmentCharge(objectIndex)
                local soul = tes3mp.GetObjectSoul(objectIndex)

                -- Get position
                local posX = tes3mp.GetObjectPosX(objectIndex)
                local posY = tes3mp.GetObjectPosY(objectIndex)
                local posZ = tes3mp.GetObjectPosZ(objectIndex)

                -- Get rotation
                local rotX = tes3mp.GetObjectRotX(objectIndex)
                local rotY = tes3mp.GetObjectRotY(objectIndex)
                local rotZ = tes3mp.GetObjectRotZ(objectIndex)

                logger.info(logger.CATEGORIES.INIT,
                    string.format("Intercepting drop of %s, will create %s instead",
                        refId, worldId))

                -- Build the world model object data
                local worldObject = {
                    refId = worldId,
                    count = count,
                    charge = charge,
                    enchantmentCharge = enchantmentCharge,
                    soul = soul,
                    location = {
                        posX = posX,
                        posY = posY,
                        posZ = posZ,
                        rotX = rotX,
                        rotY = rotY,
                        rotZ = rotZ
                    }
                }

                --offset position z down a bit to fix floating.
                if worldObject.refId == "bcw_lute_w" then worldObject.location.posZ = worldObject.location.posZ - 10.8 end
                if worldObject.refId == "misc_de_drum_02" then
                    worldObject.location.posZ = worldObject.location.posZ -
                        4.1
                end
                -- if worldObject.refId == "bcw_bassflute_w" then worldObject.location.posZ = worldObject.location.posZ - 3 end

                -- Create the world model at the location
                logicHandler.CreateObjectAtLocation(cellDescription, worldObject.location, worldObject, "place")
                logger.info(logger.CATEGORIES.INIT,
                    string.format("Created world model %s at %.2f, %.2f, %.2f",
                        worldId, posX, posY, posZ))

                -- Cancel the original placement and remove from player inventory
                Bardcraft.Inventory.RemoveItem(pid, refId, count)

                -- Return false to stop the default handler from processing this object
                return customEventHooks.makeEventStatus(false, false)
            end
        end
    end

    -- Allow default handler to continue
    return eventStatus
end

-- Handler for inventory changes - swap world instruments for weapon versions
function Bardcraft.OnPlayerInventory(eventStatus, pid)
    if not Players[pid] or not Players[pid]:IsLoggedIn() then return end

    -- Get the player's packet data that was already saved
    local playerPacket = Players[pid].data

    -- We need to check the last inventory action
    -- In TES3MP, by the time OnPlayerInventory fires, the item is already in the player's data
    -- So we check their current inventory for world instrument models

    local changesNeeded = {}

    -- Check all items currently in inventory for world models
    for index, item in pairs(Players[pid].data.inventory) do
        if item and item.refId then
            -- Check if this is a world instrument model
            if Bardcraft.Inventory.IsBardcraftInstrument(item.refId) then
                local weaponId = Bardcraft.Inventory.ConvertWorldToWeapon(item.refId)

                if weaponId ~= item.refId then
                    logger.info(logger.CATEGORIES.INIT,
                        string.format("Player %d has world instrument %s in inventory, will swap to %s",
                            pid, item.refId, weaponId))

                    -- Track this change
                    table.insert(changesNeeded, {
                        worldId = item.refId,
                        weaponId = weaponId,
                        count = item.count,
                        charge = item.charge or -1,
                        enchantmentCharge = item.enchantmentCharge or -1,
                        soul = item.soul or ""
                    })
                end
            end
        end
    end

    -- Apply all changes after checking the inventory
    for _, change in ipairs(changesNeeded) do
        -- Remove the world model from inventory
        Bardcraft.Inventory.RemoveItem(pid, change.worldId, change.count)

        -- Add the weapon version
        Bardcraft.Inventory.AddItem(pid, change.weaponId, change.count)

        logger.info(logger.CATEGORIES.INIT,
            string.format("Swapped %d x %s -> %s for pid %d",
                change.count, change.worldId, change.weaponId, pid))
    end

    return eventStatus
end

function Bardcraft.OnServerPostInit()
    logger.info(logger.CATEGORIES.INIT, "Initializing...")

    -- Initialize instrument records
    local customRecords = require("custom.bardcraft.customRecords")
    customRecords.Initialize()

    -- Load MIDI files
    Bardcraft.midi.LoadMidiFiles()

    for _, refId in pairs(Bardcraft.soundRecords.sounds.refIds) do
        local record = Bardcraft.soundRecords.sounds.records[refId]
        RecordStores[record.type].data.permanentRecords[refId] = tableHelper.deepCopy(record.data)
    end

    RecordStores["sound"]:Save()

    logger.info(logger.CATEGORIES.INIT, "Initialized successfully")
end

function Bardcraft.OnPlayerAuthentified(eventStatus, pid)
    if Players[pid] and Players[pid]:IsLoggedIn() then
        logger.info(logger.CATEGORIES.INIT,
            string.format("OnPlayerAuthentified for pid %d", pid))

        -- Initialize performer data for this player
        if not Players[pid].data.customVariables.bardcraft then
            Players[pid].data.customVariables.bardcraft = {
                knownSongs = {},
                performanceSkill = { level = 1, xp = 0 },
                reputation = 0,
                sheathedInstrument = nil,
                instrumentVolume = Bardcraft.config.defaultInstrumentVolume,
                noteCutoffEnabled = true,
                volumeStep = 10,     -- NEW: Personal volume step amount
                bandVolumeStep = 10, -- NEW: Band volume step amount
            }

            -- Add note cutoff setting to existing players who don't have it
            if Players[pid].data.customVariables.bardcraft.noteCutoffEnabled == nil then
                Players[pid].data.customVariables.bardcraft.noteCutoffEnabled = true
            end

            -- Add volume step settings to existing players who don't have them
            if Players[pid].data.customVariables.bardcraft.volumeStep == nil then
                Players[pid].data.customVariables.bardcraft.volumeStep = 10
            end
            if Players[pid].data.customVariables.bardcraft.bandVolumeStep == nil then
                Players[pid].data.customVariables.bardcraft.bandVolumeStep = 10
            end

            Players[pid]:Save()
            logger.info(logger.CATEGORIES.INIT,
                string.format("[Bardcraft] Created new bardcraft data for pid %d", pid))
        else
            -- Ensure existing players have the new volume step fields
            local needsSave = false

            if Players[pid].data.customVariables.bardcraft.volumeStep == nil then
                Players[pid].data.customVariables.bardcraft.volumeStep = 10
                needsSave = true
            end
            if Players[pid].data.customVariables.bardcraft.bandVolumeStep == nil then
                Players[pid].data.customVariables.bardcraft.bandVolumeStep = 10
                needsSave = true
            end

            if needsSave then
                Players[pid]:Save()
                logger.info(logger.CATEGORIES.INIT,
                    string.format("Added volume step settings for existing player %d", pid))
            end
        end

        Bardcraft.performers[pid] = Bardcraft.performer.New(pid)
        logger.info(logger.CATEGORIES.INIT,
            string.format("Created performer for pid %d", pid))
    end
end

function Bardcraft.OnPlayerDisconnect(eventStatus, pid)
    -- Stop any active performance
    if Bardcraft.performers[pid] and Bardcraft.performers[pid].playing then
        Bardcraft.conductor.StopPerformance(pid)
    end

    -- Remove performer object for this player
    Bardcraft.performers[pid] = nil

    -- Do NOT stop/free the conductor update timer here.
    -- The conductor.Update() function is responsible for stopping/freeing
    -- the timer when there are no active performances remaining.
end

function Bardcraft.OnPlayerCellChange(eventStatus, pid, playerPacket, previousCellDescription)
    if not Bardcraft.config.autoStopOnCellChange then return end

    local perf = Bardcraft.performers[pid]
    if not (perf and perf.playing) then return end

    local currentCell = tes3mp.GetCell(pid)

    local previousIsExterior = LoadedCells[previousCellDescription] and LoadedCells[previousCellDescription].isExterior
    local currentIsExterior = LoadedCells[currentCell] and LoadedCells[currentCell].isExterior

    -- Continue only if both previous and current cells are exteriors
    if previousIsExterior and currentIsExterior then
        logger.info(logger.CATEGORIES.INIT,
            string.format("Player %d moved between exterior cells, continuing performance: %s → %s",
                pid, previousCellDescription or "unknown", currentCell))
        return
    end

    -- Otherwise stop the performance
    logger.info(logger.CATEGORIES.INIT,
        string.format("Stopping performance for pid %d due to cell type change: %s → %s",
            pid, previousCellDescription or "unknown", currentCell))
    Bardcraft.conductor.StopPerformance(pid)
    tes3mp.SendMessage(pid, color.Orange .. "Performance stopped (changed location).\n", false)
end

function Bardcraft.OnGUIAction(eventStatus, pid, idGui, data)
    -- data comes in as a string, convert to number
    local buttonIndex = tonumber(data)

    -- Log all GUI actions
    logger.info(logger.CATEGORIES.INIT,
        string.format("OnGUIAction called: pid=%d, gui=%d, data='%s'",
            pid, idGui, tostring(data)))

    -- Prevent duplicate processing
    local now = tes3mp.GetMillisecondsSinceServerStart() / 1000
    local actionKey = string.format("%d_%d_%s", pid, idGui, tostring(data))

    -- if not Bardcraft.lastAction then
    --     Bardcraft.lastAction = {}
    -- end

    -- if Bardcraft.lastAction.key == actionKey and (now - Bardcraft.lastAction.time) < 0.1 then
    --     logger.warn(logger.CATEGORIES.INIT,
    --         string.format("Prevented duplicate GUI action: %s", actionKey))
    --     return
    -- end

    -- Bardcraft.lastAction = { key = actionKey, time = now }


    if idGui == Bardcraft.config.customMenuIds.playerActivate then
        logger.info(logger.CATEGORIES.INIT,
            string.format("playerActivate: buttonIndex=%d", buttonIndex))

        -- Player activation menu response
        local activationData = Bardcraft.activationTargets and Bardcraft.activationTargets[pid]
        if not activationData then return end

        local targetPid = activationData.targetPid
        local wasPerforming = activationData.wasPerforming

        logger.info(logger.CATEGORIES.INIT,
            string.format("wasPerforming=%s (stored at activation time)", tostring(wasPerforming)))

        if wasPerforming then
            -- Buttons: "Join Performance;Invite to Band;Cancel"
            if buttonIndex == 0 then     -- Join Performance
                Bardcraft.ShowJoinPerformanceMenu(pid, targetPid)
                return                   -- Don't clear activation target yet, we need it for part selection
            elseif buttonIndex == 1 then -- Invite to Band
                Bardcraft.band.Invite(pid, targetPid)
                Bardcraft.activationTargets[pid] = nil
                return
            else -- Cancel (buttonIndex == 2)
                Bardcraft.activationTargets[pid] = nil
                return
            end
        else
            -- Buttons: "Invite to Band;Cancel"
            if buttonIndex == 0 then -- Invite to Band
                Bardcraft.band.Invite(pid, targetPid)
                Bardcraft.activationTargets[pid] = nil
                return
            else -- Cancel (buttonIndex == 1)
                Bardcraft.activationTargets[pid] = nil
                return
            end
        end
    elseif idGui == Bardcraft.config.customMenuIds.joinPerformance then
        -- Part selection menu response
        local activationData = Bardcraft.activationTargets and Bardcraft.activationTargets[pid]
        if not activationData then return end

        local targetPid = activationData.targetPid

        -- Get the target's current performance
        local targetPerf = Bardcraft.conductor.performances[targetPid]
        if not targetPerf then
            tes3mp.SendMessage(pid, color.Red .. "That player is no longer performing!\n", false)
            Bardcraft.activationTargets[pid] = nil
            return
        end

        -- Check if they selected a valid part (not Cancel)
        local song = targetPerf.song
        if buttonIndex >= 0 and buttonIndex < #song.parts then
            local partIndex = buttonIndex + 1 -- Convert 0-based to 1-based
            Bardcraft.conductor.JoinCellPerformance(pid, partIndex)
        end

        Bardcraft.activationTargets[pid] = nil
    elseif idGui == Bardcraft.config.customMenuIds.bandInvite then
        -- Band invitation response
        if buttonIndex == 0 then     -- Accept
            Bardcraft.band.AcceptInvite(pid)
        elseif buttonIndex == 1 then -- Decline
            Bardcraft.band.DeclineInvite(pid)
        end
    elseif idGui == Bardcraft.menu.GUI_IDS.MAIN_MENU or
        idGui == Bardcraft.menu.GUI_IDS.CATEGORY_SELECT or
        idGui == Bardcraft.menu.GUI_IDS.SONG_LIST or
        idGui == Bardcraft.menu.GUI_IDS.SONG_DETAILS or
        idGui == Bardcraft.menu.GUI_IDS.TEMPO_ADJUST or
        idGui == Bardcraft.menu.GUI_IDS.CONFIRM_RELOAD or
        idGui == Bardcraft.menu.GUI_IDS.PARTS_MENU or
        idGui == Bardcraft.menu.GUI_IDS.CONFIRM_DELETE_PART or
        idGui == Bardcraft.menu.GUI_IDS.PART_SELECTION or
        idGui == Bardcraft.menu.GUI_IDS.CHAOS_TOGGLE or
        idGui == Bardcraft.menu.GUI_IDS.LOGGER_MENU or
        idGui == Bardcraft.menu.GUI_IDS.CONFIRM_STOP_ALL or
        idGui == Bardcraft.menu.GUI_IDS.VOLUME_MENU or
        idGui == Bardcraft.menu.GUI_IDS.VOLUME_STEP_ADJUST or
        idGui == Bardcraft.menu.GUI_IDS.BAND_VOLUME_MENU then
        -- Delegate to menu.lua
        Bardcraft.menu.OnGUIAction(eventStatus, pid, idGui, data)
    end
end

-- Show menu to select which part to play when joining a performance
function Bardcraft.ShowJoinPerformanceMenu(pid, targetPid)
    local targetPerf = Bardcraft.conductor.performances[targetPid]
    if not targetPerf then
        tes3mp.SendMessage(pid, color.Red .. "That player is no longer performing!\n", false)
        Bardcraft.activationTargets[pid] = nil -- Clear it here too
        return
    end

    local song = targetPerf.song
    if not song or not song.parts or #song.parts == 0 then
        tes3mp.SendMessage(pid, color.Red .. "No parts available in this song!\n", false)
        Bardcraft.activationTargets[pid] = nil -- Clear it here too
        return
    end

    -- Build the part list for the menu
    local partButtons = {}
    for i, part in ipairs(song.parts) do
        local partName = part.title or tostring(part.instrument)
        table.insert(partButtons, partName)
    end
    table.insert(partButtons, "Cancel")

    local message = string.format("Join %s's performance of %s\nSelect a part to play:",
        Players[targetPid].name, song.title)

    tes3mp.CustomMessageBox(pid, Bardcraft.config.customMenuIds.joinPerformance,
        message, table.concat(partButtons, ";"))

    logger.info(logger.CATEGORIES.INIT,
        string.format("Showing join performance menu to pid %d for %s (%d parts)",
            pid, song.title, #song.parts))
end

function Bardcraft.OnObjectActivate(eventStatus, pid, cellDescription, objects, targetPlayers)
    if not eventStatus.validDefaultHandler then return end

    -- Only handle player-to-player activation
    if not targetPlayers or tableHelper.isEmpty(targetPlayers) then return end

    -- Initialize activation targets table
    if not Bardcraft.activationTargets then
        Bardcraft.activationTargets = {}
    end

    -- Initialize activation timestamps to prevent duplicates
    if not Bardcraft.activationTimestamps then
        Bardcraft.activationTimestamps = {}
    end

    local prompt_msg
    local prompt_buttons

    -- Process each activated player
    for targetPid, targetPlayer in pairs(targetPlayers) do
        -- Make sure the activator exists in the targetPlayer data
        if targetPlayer.activatingPid and targetPlayer.activatingPid == pid then
            -- Make sure both players exist and are logged in
            if Players[pid] and Players[pid]:IsLoggedIn() and
                Players[targetPid] and Players[targetPid]:IsLoggedIn() then
                -- Check for duplicate activation (within 500ms)
                local now = tes3mp.GetMillisecondsSinceServerStart() / 1000
                local lastActivation = Bardcraft.activationTimestamps[pid]
                if lastActivation and (now - lastActivation) < 0.5 then
                    logger.info(logger.CATEGORIES.INIT,
                        string.format("Ignoring duplicate activation from pid %d (%.3fs since last)",
                            pid, now - lastActivation))
                    return
                end
                Bardcraft.activationTimestamps[pid] = now

                -- Check if target is performing
                local isPerforming = Bardcraft.performers[targetPid] and
                    Bardcraft.performers[targetPid].playing

                local message = "What would you like to do with " .. Players[targetPid].name .. "?"
                local buttons

                if isPerforming then
                    buttons = "Join Performance;Invite to Band;Cancel"
                else
                    buttons = "Invite to Band;Cancel"
                end

                -- Store the target pid AND whether they were performing
                Bardcraft.activationTargets[pid] = {
                    targetPid = targetPid,
                    wasPerforming = isPerforming
                }

                logger.info(logger.CATEGORIES.INIT,
                    string.format("Player %d activated player %d (performing: %s)",
                        pid, targetPid, tostring(isPerforming)))

                prompt_msg = message
                prompt_buttons = buttons
            end
        end
    end
    tes3mp.CustomMessageBox(pid, Bardcraft.config.customMenuIds.playerActivate,
        prompt_msg, prompt_buttons)
end

function Bardcraft.ChatCommand(pid, cmd)
    if not Players[pid] or not Players[pid]:IsLoggedIn() then return end

    local command = cmd[1]

    -- Ensure performer exists
    if not Bardcraft.performers[pid] then
        logger.warn(logger.CATEGORIES.INIT,
            string.format("No performer for pid %d in command handler, creating now", pid))
        Bardcraft.performers[pid] = Bardcraft.performer.New(pid)
    end

    if command == "play" then
        -- /play <songname> [instrument]
        local songName = cmd[2]
        local instrumentName = cmd[3] or "Lute"

        if not songName then
            tes3mp.SendMessage(pid, color.Orange .. "Usage: /play <songname> [instrument]\n", false)
            return
        end

        Bardcraft.conductor.StartPerformance(pid, songName, instrumentName)
    elseif command == "bcadmin" then
        Bardcraft.menu.ChatCommand(pid, cmd)
    elseif command == "bc" or command == "bardcraft" then
        -- New player-accessible song browser
        if not cmd[2] then
            -- Show browser menu
            if Players[pid]:IsAdmin() then
                Bardcraft.menu.ShowMainMenu(pid)
            else
                Bardcraft.menu.ShowPlayerMenu(pid)
            end
        elseif cmd[2] == "help" then
            local helpText = color.Orange .. "Bardcraft Commands:\n" ..
                "/bc or /bardcraft - Open song browser\n" ..
                "/play <song> [instrument] - Start performing\n" ..
                "/stop - Stop performing\n" ..
                "/volume [0-1000] - Set instrument volume\n" ..
                "/cutoff [on|off] - Toggle note cutoff\n" ..
                "/songs - List known songs\n" ..
                "/band - Band commands\n" ..
                "/bandplay <song> - Start band performance (leader)\n" ..
                "/bandstop - Stop band performance (leader)\n"

            if Players[pid]:IsAdmin() then
                helpText = helpText .. color.Yellow ..
                    "/bcadmin - Admin tools (reload, tempo, parts)\n"
            end

            tes3mp.SendMessage(pid, helpText, false)
        end
    elseif command == "timing" then
        -- Debug command to show current timing info
        local b = Bardcraft.band.GetBand(pid)
        local perf = Bardcraft.conductor.performances[pid]

        if perf then
            local elapsed = (tes3mp.GetMillisecondsSinceServerStart() / 1000) - perf.startTime
            local ticksPerSecond = (perf.bpm / 60) * (perf.song.resolution or 96)
            local exactTick = elapsed * ticksPerSecond

            local info = string.format(
                "Timing Info:\n" ..
                "  Elapsed: %.3f seconds\n" ..
                "  BPM: %d\n" ..
                "  Resolution: %d ticks/quarter\n" ..
                "  Current Tick: %.1f\n" ..
                "  Note Index: %d / %d\n" ..
                "  Update Interval: %dms\n",
                elapsed, perf.bpm, perf.song.resolution or 96,
                exactTick, perf.noteIndex, #perf.notes,
                Bardcraft.conductor.updateInterval
            )
            tes3mp.SendMessage(pid, color.Orange .. info, false)
        else
            tes3mp.SendMessage(pid, color.Red .. "You're not currently performing.\n", false)
        end
    elseif command == "cutoff" then
        -- /cutoff [on|off]
        local setting = cmd[2]

        if not setting then
            -- Show current setting
            local currentSetting = Players[pid].data.customVariables.bardcraft.noteCutoffEnabled
            if currentSetting == nil then
                currentSetting = true
            end
            local status = currentSetting and "ENABLED" or "DISABLED"
            tes3mp.SendMessage(pid, color.Orange ..
                "Note cutoff is currently: " .. status .. "\n" ..
                "Usage: /cutoff <on|off>\n" ..
                "  ON  = Notes stop when they should (cleaner, more precise)\n" ..
                "  OFF = Notes ring out naturally (fuller, more ambient)\n", false)
            return
        end

        local enabled
        if setting == "on" or setting == "1" or setting == "true" then
            enabled = true
        elseif setting == "off" or setting == "0" or setting == "false" then
            enabled = false
        else
            tes3mp.SendMessage(pid, color.Red .. "Invalid option. Use: /cutoff on  or  /cutoff off\n", false)
            return
        end

        Players[pid].data.customVariables.bardcraft.noteCutoffEnabled = enabled
        Players[pid]:Save()

        local status = enabled and "ENABLED" or "DISABLED"
        tes3mp.SendMessage(pid, color.Green ..
            "Note cutoff " .. status .. "\n" ..
            (enabled and "Notes will stop precisely as written in the music.\n" or
                "Notes will ring out naturally for fuller sound.\n"), false)

        logger.info(logger.CATEGORIES.INIT,
            string.format("[Bardcraft] Player %d set note cutoff to %s", pid, tostring(enabled)))
    elseif command == "stop" then
        Bardcraft.conductor.StopPerformance(pid)
    elseif command == "volume" then
        -- /volume [0-1000]
        local volumePercent = tonumber(cmd[2])

        if not volumePercent then
            -- Show current volume
            local currentVolume = Players[pid].data.customVariables.bardcraft.instrumentVolume or 1.0
            local currentPercent = math.floor(currentVolume * 100)
            tes3mp.SendMessage(pid, color.Orange ..
                "Current instrument volume: " .. currentPercent .. "%\n" ..
                "Usage: /volume <0-1000> (100 = default, 1000 = 10x louder)\n", false)
            return
        end

        -- Validate and set volume (allow 0-1000, which is 0-10x)
        volumePercent = math.max(0, math.min(1000, volumePercent))
        local volume = volumePercent / 100.0

        Players[pid].data.customVariables.bardcraft.instrumentVolume = volume
        Players[pid]:Save()

        tes3mp.SendMessage(pid, color.Green ..
            "Instrument volume set to " .. volumePercent .. "% (" ..
            string.format("%.1fx", volume) .. ")\n", false)

        logger.info(logger.CATEGORIES.INIT,
            string.format("[Bardcraft] Player %d set volume to %.2f", pid, volume))
    elseif command == "songs" then
        -- List known songs
        local performer = Bardcraft.performers[pid]
        if performer then
            local songList = "Known songs:\n"
            local count = 0
            for songId, _ in pairs(performer.data.knownSongs) do
                local song = Bardcraft.midi.GetSongById(songId)
                if song then
                    songList = songList .. "- " .. song.title .. "\n"
                    count = count + 1
                end
            end
            if count == 0 then
                songList = "You don't know any songs yet!"
            end
            tes3mp.SendMessage(pid, color.Orange .. songList, false)
        end
    elseif command == "teach" and cmd[2] then
        -- Debug command to teach a song
        local songName = cmd[2]
        local song = Bardcraft.midi.GetSongByName(songName)
        if song then
            Bardcraft.performer.TeachSong(pid, song.id)
            tes3mp.SendMessage(pid, color.Green .. "Learned: " .. song.title .. "\n", false)
        else
            tes3mp.SendMessage(pid, color.Red .. "Song not found: " .. songName .. "\n", false)
        end
    elseif command == "bardcraft" and cmd[2] == "help" then
        local helpText = color.Orange .. "Bardcraft Commands:\n" ..
            "/bc - Open song browser (easy song selection!)\n" ..
            "/play <song> [instrument] - Start performing\n" ..
            "/stop - Stop performing\n" ..
            "/volume [0-1000] - Set instrument volume (100=default, 1000=10x)\n" ..
            "/songs - List known songs\n" ..
            "/teach <song> - Learn a song (debug)\n" ..
            "/band - Band commands (see /band for details)\n" ..
            "/bandplay <song> - Start band performance (leader)\n" ..
            "/cutoff [on|off] - Toggle note cutoff (on=precise, off=ring out)\n" ..
            "/bandstop - Stop band performance (leader)\n"

        -- Add admin help for admins
        if Players[pid]:IsAdmin() then
            helpText = helpText .. color.Yellow ..
                "/bcadmin - Admin menu (reload MIDIs, adjust tempo)\n"
        end

        tes3mp.SendMessage(pid, helpText, false)
    elseif command == "bandplay" then
        -- /bandplay <songname> - Start synchronized band performance
        local songName = cmd[2]

        if not songName then
            tes3mp.SendMessage(pid, color.Orange .. "Usage: /bandplay <songname>\n", false)
            return
        end

        local b = Bardcraft.band.GetBand(pid)
        if not b then
            tes3mp.SendMessage(pid, color.Red .. "You're not in a band!\n", false)
            return
        end

        if b.leader ~= pid then
            tes3mp.SendMessage(pid, color.Red .. "Only the band leader can start performances!\n", false)
            return
        end

        Bardcraft.band.StartPerformance(b.id, songName)
    elseif command == "bandstop" then
        -- /bandstop - Stop band performance
        local b = Bardcraft.band.GetBand(pid)
        if not b then
            tes3mp.SendMessage(pid, color.Red .. "You're not in a band!\n", false)
            return
        end

        if b.leader ~= pid then
            tes3mp.SendMessage(pid, color.Red .. "Only the band leader can stop performances!\n", false)
            return
        end

        Bardcraft.band.StopPerformance(b.id)
        tes3mp.SendMessage(pid, color.Green .. "Band performance stopped.\n", false)
    elseif command == "band" then
        -- /band <subcommand>
        local subCmd = cmd[2]

        if subCmd == "leave" then
            Bardcraft.band.Leave(pid)
        elseif subCmd == "disband" then
            local b = Bardcraft.band.GetBand(pid)
            if not b then
                tes3mp.SendMessage(pid, color.Red .. "You're not in a band!\n", false)
                return
            end

            if b.leader ~= pid then
                tes3mp.SendMessage(pid, color.Red .. "Only the band leader can disband!\n", false)
                return
            end

            Bardcraft.band.Disband(b.id)
        elseif subCmd == "info" then
            local b = Bardcraft.band.GetBand(pid)
            if not b then
                tes3mp.SendMessage(pid, color.Orange .. "You're not in a band.\n", false)
                return
            end

            local info = "Band Members:\n"
            for _, memberId in ipairs(b.members) do
                local prefix = (memberId == b.leader) and "* " or "  "
                info = info .. prefix .. Players[memberId].name .. "\n"
            end

            tes3mp.SendMessage(pid, color.Orange .. info, false)
        else
            local helpText = color.Orange .. "Band Commands:\n" ..
                "/band info - Show band members\n" ..
                "/band leave - Leave your current band\n" ..
                "/band disband - Disband your band (leader only)\n" ..
                "/bandplay <song> - Start synchronized performance (leader only)\n" ..
                "/bandstop - Stop band performance (leader only)\n" ..
                "Activate another player to invite them to your band!\n"
            tes3mp.SendMessage(pid, helpText, false)
        end
    end
end

function Bardcraft.OnServerUpdate()
    -- Update conductor (handles performance timing)
    Bardcraft.conductor.Update()
end

------------
-- EVENTS --
------------
customEventHooks.registerValidator("OnObjectPlace", Bardcraft.OnObjectPlaceValidator)

customEventHooks.registerHandler("OnServerPostInit", Bardcraft.OnServerPostInit)
customEventHooks.registerHandler("OnPlayerAuthentified", Bardcraft.OnPlayerAuthentified)
customEventHooks.registerHandler("OnPlayerDisconnect", Bardcraft.OnPlayerDisconnect)
customEventHooks.registerHandler("OnObjectActivate", Bardcraft.OnObjectActivate)
customEventHooks.registerHandler("OnGUIAction", Bardcraft.OnGUIAction)
customEventHooks.registerHandler("OnPlayerCellChange", Bardcraft.OnPlayerCellChange)
customEventHooks.registerHandler("OnPlayerInventory", Bardcraft.OnPlayerInventory)


customEventHooks.registerHandler("OnPlayerDisconnect", function(eventStatus, pid)
    Bardcraft.OnPlayerDisconnect(eventStatus, pid)
    -- Also clean up band membership when player disconnects
    Bardcraft.band.Leave(pid)
end)


-- Register chat commands - each command registered separately
customCommandHooks.registerCommand("band", Bardcraft.ChatCommand)
customCommandHooks.registerCommand("bandplay", Bardcraft.ChatCommand)
customCommandHooks.registerCommand("bandstop", Bardcraft.ChatCommand)
customCommandHooks.registerCommand("play", Bardcraft.ChatCommand)
customCommandHooks.registerCommand("stop", Bardcraft.ChatCommand)
customCommandHooks.registerCommand("songs", Bardcraft.ChatCommand)
customCommandHooks.registerCommand("teach", Bardcraft.ChatCommand)
customCommandHooks.registerCommand("volume", Bardcraft.ChatCommand)
customCommandHooks.registerCommand("bcadmin", Bardcraft.ChatCommand)
customCommandHooks.registerCommand("cutoff", Bardcraft.ChatCommand)
customCommandHooks.registerCommand("bc", Bardcraft.ChatCommand)
customCommandHooks.registerCommand("bardcraft", Bardcraft.ChatCommand)

customCommandHooks.registerCommand("midilist", function(pid, cmd)
    local midi = require("custom.bardcraft.midi")
    local names = midi.GetAllSongNames()
    if #names == 0 then
        tes3mp.SendMessage(pid, color.Orange .. "No songs loaded\n", false)
        return
    end
    local msg = "Loaded songs:\n"
    for _, name in ipairs(names) do
        msg = msg .. "- " .. name .. "\n"
    end
    tes3mp.SendMessage(pid, color.Orange .. msg, false)
end)


-- TODO: attempt to silence the logging for console commands related to playing notes
-- Monkey-patch OnConsoleCommand to prevent kicks from bardcraft sound commands
local originalOnConsoleCommand = eventHandler.OnConsoleCommand
eventHandler.OnConsoleCommand = function(pid, cellDescription)
    -- Check if player is not logged in
    if not (Players[pid] ~= nil and Players[pid]:IsLoggedIn()) then
        -- Read the console command to check if it's bardcraft-related
        tes3mp.ReadReceivedObjectList()
        local consoleCommand = tes3mp.GetObjectListConsoleCommand()

        -- If it's a bardcraft sound command, just ignore it instead of kicking
        if consoleCommand and (
                consoleCommand:match("Lute_") or
                consoleCommand:match("Harp_") or
                consoleCommand:match("Flute_") or
                consoleCommand:match("Drum_") or
                consoleCommand:match("PlayLoopSound3DVP") or
                consoleCommand:match("PlaySound3DVP") or
                consoleCommand:match("StopSound")
            ) then
            logger.warn(logger.CATEGORIES.INIT,
                string.format("Ignored console command from not-yet-logged-in player %d: %s",
                    pid, consoleCommand))
            return -- Don't kick, just return
        end
    end

    -- Call original handler
    return originalOnConsoleCommand(pid, cellDescription)
end


Bardcraft.conductor.Init()


return Bardcraft
