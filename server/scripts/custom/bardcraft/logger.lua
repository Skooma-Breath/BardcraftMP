--[[
Bardcraft Logging Module
Provides modular logging with configurable categories and levels

USAGE:
  local logger = require("custom.bardcraft.logger")

  -- Log with specific category and level
  logger.info(logger.CATEGORIES.CHAOS, "Chaos mode is now enabled")
  logger.trace(logger.CATEGORIES.CHAOS, "Detailed chaos mode check: " .. details)

  -- Enable/disable categories at runtime
  logger.enableCategory(logger.CATEGORIES.CHAOS, logger.LEVELS.TRACE)
  logger.disableCategory(logger.CATEGORIES.MIDI)

  -- Toggle all logging
  logger.enabled = false  -- Disable all logs
  logger.enabled = true   -- Re-enable
]]

local logger = {}

-- Log categories for different subsystems
logger.CATEGORIES = {
    INIT = "INIT",           -- Initialization and startup
    MENU = "MENU",         -- Menu commands and menu actions
    BAND = "BAND",           -- Band management (invites, joins, etc.)
    CONDUCTOR = "CONDUCTOR", -- Performance conductor logic
    PERFORMER = "PERFORMER", -- Individual performer actions
    MIDI = "MIDI",           -- MIDI file loading and parsing
    GUI = "GUI",             -- GUI actions and debugging
    TIMER = "TIMER",         -- Timer callbacks and scheduling
    CELL = "CELL",           -- Cell management and transitions
    CONFIG = "CONFIG",       -- Configuration changes
    CUSTOMRECORDS = "CUSTOMRECORDS",       -- Custom Record creation
}

-- Log levels (matching tes3mp enumerations.log)
logger.LEVELS = {
    VERBOSE = 0,
    INFO = 1,
    WARN = 2,
    ERROR = 3,
    FATAL = 4,
}

-- Configuration: which categories are enabled at which levels
-- Set to nil to disable a category entirely
-- Set to a level to log that level and above
logger.config = {
    [logger.CATEGORIES.INIT] = logger.LEVELS.INFO,
    [logger.CATEGORIES.MENU] = logger.LEVELS.INFO,
    [logger.CATEGORIES.BAND] = logger.LEVELS.INFO,
    [logger.CATEGORIES.CONDUCTOR] = logger.LEVELS.INFO,
    [logger.CATEGORIES.PERFORMER] = logger.LEVELS.INFO,
    [logger.CATEGORIES.MIDI] = logger.LEVELS.WARN,
    [logger.CATEGORIES.GUI] = logger.LEVELS.WARN,
    [logger.CATEGORIES.TIMER] = logger.LEVELS.VERBOSE,
    [logger.CATEGORIES.CELL] = logger.LEVELS.INFO,
    [logger.CATEGORIES.CONFIG] = logger.LEVELS.INFO,
    [logger.CATEGORIES.CUSTOMRECORDS] = logger.LEVELS.WARN,
}

-- Enable/disable all logging
logger.enabled = true

-- Helper to check if a log should be written
local function shouldLog(category, level)
    if not logger.enabled then
        return false
    end

    local categoryLevel = logger.config[category]
    if categoryLevel == nil then
        return false -- Category disabled
    end

    return level <= categoryLevel
end

-- Main logging function
-- @param category: One of logger.CATEGORIES
-- @param level: One of logger.LEVELS
-- @param message: The log message (will be prefixed with [Bardcraft][Category])
function logger.log(category, level, message)
    if not shouldLog(category, level) then
        return
    end

    local prefix = string.format("[Bardcraft][%s]", category)
    local fullMessage = prefix .. " " .. message

    tes3mp.LogMessage(level, fullMessage)
end

-- Convenience functions for each level
function logger.fatal(category, message)
    logger.log(category, logger.LEVELS.FATAL, message)
end

function logger.error(category, message)
    logger.log(category, logger.LEVELS.ERROR, message)
end

function logger.warn(category, message)
    logger.log(category, logger.LEVELS.WARN, message)
end

function logger.info(category, message)
    logger.log(category, logger.LEVELS.INFO, message)
end

function logger.verbose(category, message)
    logger.log(category, logger.LEVELS.VERBOSE, message)
end

-- Quick enable/disable functions for categories
function logger.enableCategory(category, level)
    level = level or logger.LEVELS.INFO
    logger.config[category] = level
    logger.info(logger.CATEGORIES.CONFIG,
        string.format("Enabled category %s at level %d", category, level))
end

function logger.disableCategory(category)
    logger.config[category] = nil
    logger.info(logger.CATEGORIES.CONFIG,
        string.format("Disabled category %s", category))
end

-- Set log level for a category
function logger.setLevel(category, level)
    logger.config[category] = level
    logger.info(logger.CATEGORIES.CONFIG,
        string.format("Set category %s to level %d", category, level))
end

-- Get current configuration as a string
function logger.getConfig()
    local lines = { "Logger Configuration:" }
    table.insert(lines, "  Enabled: " .. tostring(logger.enabled))
    table.insert(lines, "  Categories:")

    for category, level in pairs(logger.config) do
        if level ~= nil then
            local levelName = "UNKNOWN"
            for name, val in pairs(logger.LEVELS) do
                if val == level then
                    levelName = name
                    break
                end
            end
            table.insert(lines, string.format("    %s: %s (%d)", category, levelName, level))
        else
            table.insert(lines, string.format("    %s: DISABLED", category))
        end
    end

    return table.concat(lines, "\n")
end

return logger
