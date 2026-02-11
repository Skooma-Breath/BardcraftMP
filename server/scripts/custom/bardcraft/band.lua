--[[
Bardcraft Band System
Manages groups of players performing together in sync
]]

local band = {}

local logger = require("custom.bardcraft.logger")

-- Active bands: bandId -> band data
band.activeBands = {}
band.nextBandId = 1

-- Player to band mapping: pid -> bandId
band.playerBands = {}

-- Pending invitations: targetPid -> { inviterPid, timestamp }
band.pendingInvites = {}

--[[
Band structure:
{
    id = number,
    leader = pid,
    members = { pid1, pid2, ... },
    currentSong = songId or nil,
    startTime = os.clock() or nil,
    assignedParts = { [pid] = partIndex }
}
]]

-- Create a new band with the given leader
function band.Create(leaderPid)
    local bandId = band.nextBandId
    band.nextBandId = band.nextBandId + 1

    band.activeBands[bandId] = {
        id = bandId,
        leader = leaderPid,
        members = { leaderPid },
        currentSong = nil,
        startTime = nil,
        assignedParts = {}
    }

    band.playerBands[leaderPid] = bandId

    logger.info(logger.CATEGORIES.BAND,
        string.format("Created band %d with leader %d", bandId, leaderPid))

    return bandId
end

-- Disband a band
function band.Disband(bandId)
    local b = band.activeBands[bandId]
    if not b then return end

    -- Remove all members from the band mapping
    for _, pid in ipairs(b.members) do
        band.playerBands[pid] = nil

        -- Stop any active performance
        local Bardcraft = require("custom.bardcraft.init")
        if Bardcraft.performers[pid] and Bardcraft.performers[pid].playing then
            Bardcraft.conductor.StopPerformance(pid)
        end

        tes3mp.SendMessage(pid, color.Orange .. "Band has been disbanded.\n", false)
    end

    band.activeBands[bandId] = nil

    logger.info(logger.CATEGORIES.BAND,
        string.format("Disbanded band %d", bandId))
end

-- Invite a player to a band
function band.Invite(inviterPid, targetPid)
    -- Check if inviter is in a band or create one
    local bandId = band.playerBands[inviterPid]
    if not bandId then
        bandId = band.Create(inviterPid)
        tes3mp.SendMessage(inviterPid, color.Green .. "Created a new band!\n", false)
    end

    local b = band.activeBands[bandId]
    if not b then
        tes3mp.SendMessage(inviterPid, color.Red .. "Band error!\n", false)
        return
    end

    -- Check if target is already in a band
    if band.playerBands[targetPid] then
        tes3mp.SendMessage(inviterPid, color.Red ..
            Players[targetPid].name .. " is already in a band!\n", false)
        return
    end

    -- Check if target is already invited
    if band.pendingInvites[targetPid] then
        tes3mp.SendMessage(inviterPid, color.Red ..
            Players[targetPid].name .. " already has a pending invitation!\n", false)
        return
    end

    -- Send invitation
    band.pendingInvites[targetPid] = {
        inviterPid = inviterPid,
        bandId = bandId,
        timestamp = tes3mp.GetMillisecondsSinceServerStart() / 1000
    }

    tes3mp.SendMessage(inviterPid, color.Green ..
        "Sent band invitation to " .. Players[targetPid].name .. "\n", false)

    -- Show accept/decline menu to target
    band.ShowInviteMenu(targetPid, inviterPid)
end

-- Show invitation menu to target player
function band.ShowInviteMenu(targetPid, inviterPid)
    local Bardcraft = require("custom.bardcraft.init")
    local message = Players[inviterPid].name .. " invites you to join their band!"

    tes3mp.CustomMessageBox(targetPid, Bardcraft.config.customMenuIds.bandInvite,
        message, "Accept;Decline")
end

-- Accept a band invitation
function band.AcceptInvite(targetPid)
    local invite = band.pendingInvites[targetPid]
    if not invite then
        tes3mp.SendMessage(targetPid, color.Red .. "No pending invitation!\n", false)
        return
    end

    local b = band.activeBands[invite.bandId]
    if not b then
        tes3mp.SendMessage(targetPid, color.Red .. "Band no longer exists!\n", false)
        band.pendingInvites[targetPid] = nil
        return
    end

    -- Add to band
    table.insert(b.members, targetPid)
    band.playerBands[targetPid] = invite.bandId
    band.pendingInvites[targetPid] = nil

    -- Notify everyone
    tes3mp.SendMessage(targetPid, color.Green ..
        "Joined " .. Players[b.leader].name .. "'s band!\n", false)

    for _, pid in ipairs(b.members) do
        if pid ~= targetPid then
            tes3mp.SendMessage(pid, color.Green ..
                Players[targetPid].name .. " joined the band!\n", false)
        end
    end

    logger.info(logger.CATEGORIES.BAND,
        string.format("Player %d joined band %d", targetPid, invite.bandId))
end

-- Decline a band invitation
function band.DeclineInvite(targetPid)
    local invite = band.pendingInvites[targetPid]
    if not invite then return end

    tes3mp.SendMessage(invite.inviterPid, color.Orange ..
        Players[targetPid].name .. " declined your band invitation.\n", false)
    tes3mp.SendMessage(targetPid, color.Orange .. "Declined band invitation.\n", false)

    band.pendingInvites[targetPid] = nil
end

-- Leave a band
function band.Leave(pid)
    local bandId = band.playerBands[pid]
    if not bandId then
        tes3mp.SendMessage(pid, color.Red .. "You're not in a band!\n", false)
        return
    end

    local b = band.activeBands[bandId]
    if not b then
        band.playerBands[pid] = nil
        return
    end

    -- Remove from members
    for i, memberId in ipairs(b.members) do
        if memberId == pid then
            table.remove(b.members, i)
            break
        end
    end

    band.playerBands[pid] = nil

    -- Stop any active performance
    local Bardcraft = require("custom.bardcraft.init")
    if Bardcraft.performers[pid] and Bardcraft.performers[pid].playing then
        Bardcraft.conductor.StopPerformance(pid)
    end

    -- Notify
    tes3mp.SendMessage(pid, color.Orange .. "Left the band.\n", false)

    for _, memberId in ipairs(b.members) do
        tes3mp.SendMessage(memberId, color.Orange ..
            Players[pid].name .. " left the band.\n", false)
    end

    -- If leader left or band is empty, disband
    if pid == b.leader or #b.members == 0 then
        band.Disband(bandId)
    end
end

-- Get band for a player
function band.GetBand(pid)
    local bandId = band.playerBands[pid]
    if not bandId then return nil end
    return band.activeBands[bandId]
end

-- Check if players are in the same cell
function band.AreInSameCell(pid1, pid2)
    if not Players[pid1] or not Players[pid2] then return false end
    return Players[pid1].data.location.cell == Players[pid2].data.location.cell
end

-- Get all band members in the same cell as the given player
function band.GetMembersInSameCell(pid)
    local b = band.GetBand(pid)
    if not b then return {} end

    local cellMembers = {}
    local playerCell = Players[pid].data.location.cell

    for _, memberId in ipairs(b.members) do
        if Players[memberId] and Players[memberId].data.location.cell == playerCell then
            table.insert(cellMembers, memberId)
        end
    end

    return cellMembers
end

-- Assign parts to band members for a song
function band.AssignParts(bandId, song)
    local b = band.activeBands[bandId]
    if not b then return false end

    -- Get members in the same cell as leader
    local activeMemberPids = {}
    local leaderCell = Players[b.leader].data.location.cell

    for _, pid in ipairs(b.members) do
        if Players[pid] and Players[pid].data.location.cell == leaderCell then
            table.insert(activeMemberPids, pid)
        end
    end

    if #activeMemberPids == 0 then return false end

    -- Get available parts from the song
    local parts = song.parts or {}
    if #parts == 0 then return false end

    -- Clear previous assignments
    b.assignedParts = {}

    -- Assign parts round-robin style
    for i, pid in ipairs(activeMemberPids) do
        local partIndex = ((i - 1) % #parts) + 1
        b.assignedParts[pid] = partIndex

        logger.info(logger.CATEGORIES.BAND,
            string.format("Assigned part %d to player %d", partIndex, pid))
    end

    return true
end

-- Start synchronized performance for a band
function band.StartPerformance(bandId, songName)
    local b = band.activeBands[bandId]
    if not b then return false end

    local Bardcraft = require("custom.bardcraft.init")

    -- Get the song
    local song = Bardcraft.midi.GetSongByName(songName)
    if not song then
        tes3mp.SendMessage(b.leader, color.Red .. "Song not found: " .. songName .. "\n", false)
        return false
    end

    -- Assign parts to members
    if not band.AssignParts(bandId, song) then
        tes3mp.SendMessage(b.leader, color.Red .. "No band members in same cell!\n", false)
        return false
    end

    -- Set band performance data
    b.currentSong = song.id
    b.startTime = tes3mp.GetMillisecondsSinceServerStart() / 1000

    -- Start performance for each member
    local startedCount = 0
    for pid, partIndex in pairs(b.assignedParts) do
        local part = song.parts[partIndex]
        if part then
            -- Create performer if it doesn't exist
            if not Bardcraft.performers[pid] then
                logger.info(logger.CATEGORIES.BAND,
                    string.format("Creating performer for pid %d", pid))
                Bardcraft.performers[pid] = Bardcraft.performer.New(pid)
            end

            if Bardcraft.performers[pid] then
                -- Get instrument name from part
                local instrumentName = part.title or tostring(part.instrument)
                if type(instrumentName) == "string" then
                    -- Remove trailing numbers like "Lute 2" -> "Lute"
                    instrumentName = instrumentName:gsub("%s+%d+$", "")
                end

                -- Start the performance with synchronized start time
                local success = Bardcraft.conductor.StartPerformanceWithTime(pid, song, part, instrumentName, b
                    .startTime)

                if success then
                    -- Register this performance in the cell so others can join
                    local cellDescription = Players[pid].data.location.cell
                    Bardcraft.conductor.RegisterCellPerformance(pid, cellDescription, song.id, b.startTime)

                    tes3mp.SendMessage(pid, color.Green ..
                        string.format("Now performing: %s (%s - Part %d)\n",
                            song.title, instrumentName, partIndex), false)
                    startedCount = startedCount + 1

                    logger.info(logger.CATEGORIES.BAND,
                        string.format(
                            "Started performance for pid %d, part %d (%s), registered in cell",
                            pid, partIndex, instrumentName))
                else
                    logger.warn(logger.CATEGORIES.BAND,
                        string.format("Failed to start performance for pid %d", pid))
                end
            else
                logger.error(logger.CATEGORIES.BAND,
                    string.format("Could not create performer for pid %d", pid))
            end
        else
            logger.warn(logger.CATEGORIES.BAND,
                string.format("Part %d not found in song", partIndex))
        end
    end

    if startedCount > 0 then
        logger.info(logger.CATEGORIES.BAND,
            string.format("Band %d started synchronized performance of %s (%d/%d members started)",
                bandId, song.title, startedCount, tableHelper.getCount(b.assignedParts)))
        return true
    else
        logger.error(logger.CATEGORIES.BAND,
            string.format("Band %d failed to start any performances!", bandId))
        tes3mp.SendMessage(b.leader, color.Red .. "Failed to start band performance!\n", false)
        return false
    end
end

-- Stop band performance
function band.StopPerformance(bandId)
    local b = band.activeBands[bandId]
    if not b then return end

    local Bardcraft = require("custom.bardcraft.init")

    -- Stop performance for all members
    for _, pid in ipairs(b.members) do
        if Bardcraft.performers[pid] and Bardcraft.performers[pid].playing then
            Bardcraft.conductor.StopPerformance(pid)
        end
    end

    b.currentSong = nil
    b.startTime = nil
    b.assignedParts = {}
end

return band
