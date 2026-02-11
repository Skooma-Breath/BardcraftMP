--[[
Bardcraft Configuration
]]

local config                        = {}

-- Performance settings
config.defaultInstrumentVolume      = 6.0

-- config.enableAnimations        = true
-- config.baseXpPerNote           = 0.5

-- -- Performance types and XP multipliers
-- config.xpMultipliers           = {
--     Practice = 0.5,
--     Tavern = 1.0,
--     Street = 0.75,
-- }

-- -- Animation frame rate (Morrowind uses 24 FPS)
-- config.animFPS                 = 24
-- config.animFramesPerBeat       = 20

-- Update interval for performance timing (in seconds)
config.updateInterval               = 0.05

-- MIDI file directory
config.midiDirectories              = {
    tes3mp.GetDataPath() .. "/custom/bardcraft/custom",
    tes3mp.GetDataPath() .. "/custom/bardcraft/preset"
}

-- Custom menu IDs for band invitations
config.customMenuIds                = {
    bandInvite = 31337, -- Choose an ID that doesn't conflict with other mods
    playerActivate = 31338,
    joinPerformance = 31339
}

config.allowChaos                   = false -- If false, only one song can play per cell
config.autoStopOnCellChange         = true -- Stop performances when changing cells
config.requireInstrumentInInventory = true -- If true, players must have bcw_ instruments to play parts

return config
