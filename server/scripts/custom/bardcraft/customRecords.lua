--[[
Bardcraft Custom Records
Defines custom armor and weapon records for instrument models
Used for visual representation during performance
Uses TES3MP's RecordStore system for permanent records

Mesh Structure:
- Bardcraft\play\*.nif - Meshes for armor records (playing animations)
- Bardcraft\hold\*_equipped.nif - Meshes for equipped weapons
- Bardcraft\hold\*_world.nif - Meshes for weapons on ground
]]

local customRecords = {}

-- Body part records for armor pieces (playing animations)
local bodyPartRecords = {
    -- Lute body part
    {
        id = "bcbp_lute",
        subtype = 2, -- armor
        model = "Bardcraft\\play\\musdelutethin.nif",
        part = 14    -- tail
    },
    -- Bass Flute body part
    {
        id = "bcbp_bassflute",
        subtype = 2,
        model = "Bardcraft\\play\\rlts_bc_bassflute.nif",
        part = 14
    },
    -- Ocarina body part
    {
        id = "bcbp_ocarina",
        subtype = 2,
        model = "Bardcraft\\play\\rlts_bc_ocarina.nif",
        part = 14
    },
    -- Fiddle body part
    {
        id = "bcbp_fiddle",
        subtype = 2,
        model = "Bardcraft\\play\\rlts_bc_fiddle.nif",
        part = 14
    },
    -- Fiddle shield
    {
        id = "bcbp_fiddle_shield",
        subtype = 2,
        model = "Bardcraft\\hold\\rlts_bc_fiddle_shield.nif",
        part = 10
    },
    -- Fiddle Bow body part
    {
        id = "bcbp_fiddle_bow",
        subtype = 2,
        model = "Bardcraft\\play\\rlts_bc_fiddle_bow.nif",
        part = 6
    },
    -- drum
    {
        id = "bcbp_drum",
        subtype = 2,
        model = "Bardcraft\\play\\drum_guar.nif",
        part = 6
    },
}

-- Custom armor records (used for playing animations)
local armorRecords = {
    -- Lute (playing model as greaves)
    {
        id = "bca_lute",
        name = "lute",
        subtype = 4, -- Greaves
        value = 1000,
        weight = 1,
        icon = "m\\tx_de_lute_01.dds",
        model = "Bardcraft\\play\\musdelutethin.nif",
        health = 1000,
        armorRating = 666,
        parts = { {
            partType = 5,
            malePart = "bcbp_lute"
        } }
    },

    -- Bass Flute (playing model as greaves)
    {
        id = "bca_bassflute",
        name = "bassflute",
        subtype = 4, -- Greaves
        value = 1000,
        weight = 1,
        icon = "Bardcraft\\tx_flute.dds",
        model = "Bardcraft\\play\\rlts_bc_bassflute.nif",
        health = 1000,
        armorRating = 666,
        parts = { {
            partType = 5,
            malePart = "bcbp_bassflute"
        } }
    },

    -- Ocarina (playing model as greaves)
    {
        id = "bca_ocarina",
        name = "ocarina",
        subtype = 4, -- Greaves
        value = 1000,
        weight = 1,
        icon = "Bardcraft\\tx_ocarina.dds",
        model = "Bardcraft\\play\\rlts_bc_ocarina.nif",
        health = 1000,
        armorRating = 666,
        parts = { {
            partType = 5,
            malePart = "bcbp_ocarina"
        } }
    },

    -- Fiddle (playing model as greaves)
    {
        id = "bca_fiddle",
        name = "fiddle",
        subtype = 4, -- Greaves
        value = 1000,
        weight = 1,
        icon = "Bardcraft\\tx_fiddle.dds",
        model = "Bardcraft\\play\\rlts_bc_fiddle.nif",
        health = 1000,
        armorRating = 666,
        parts = { {
            partType = 5, --skirt
            malePart = "bcbp_fiddle"
        } }
    },

    -- Fiddle (shield for holding wit bow weapon)
    {
        id = "bca_fiddle_shield",
        name = "fiddle",
        subtype = 8, -- shield
        value = 1000,
        weight = 1,
        icon = "Bardcraft\\tx_fiddle.dds",
        model = "Bardcraft\\hold\\rlts_bc_fiddle_shield.nif",
        health = 1000,
        armorRating = 666,
        parts = { {
            partType = 10, --shield
            malePart = "bcbp_fiddle_shield"
        } }
    },

    -- drum
    {
        id = "bca_drum",
        name = "Drum",
        subtype = 4, -- greaves
        value = 100,
        weight = 0.5,
        icon = "m\\tx_de_drum_01.dds",
        model = "Bardcraft\\play\\drum_guar.nif",
        health = 1000,
        armorRating = 666,
        parts = { {
            partType = 5, -- skirt
            malePart = "bcbp_drum"
        } }
    },
}

-- Custom weapon records (for holding/carrying)
-- These use _equipped.nif for when held and _world.nif for when on ground
local weaponRecords = {
    -- Lute (as 2-handed spear)
    {
        id = "bcw_lute",
        name = "lute",
        subtype = 6, -- Spear (2-handed)
        value = 1000,
        weight = 1,
        icon = "m\\tx_de_lute_01.dds",
        model = "Bardcraft\\hold\\musdelutethin.nif",
        health = 1000,
        speed = 1.0,
        reach = 1.0,
        enchantPts = 0,
        damageChop = {
            min = 6,
            max = 6
        },
        damageSlash = {
            min = 3,
            max = 3
        },
        damageThrust = {
            min = 3,
            max = 3
        },
        flags = 0
    },

    -- Bass Flute (as 2-handed spear)
    {
        id = "bcw_bassflute",
        name = "bassflute",
        subtype = 6, -- Spear (2-handed)
        value = 1000,
        weight = 1,
        icon = "Bardcraft\\tx_flute.dds",
        model = "Bardcraft\\hold\\rlts_bc_bassflute.nif",
        health = 1000,
        speed = 1.0,
        reach = 1.0,
        enchantPts = 0,
        damageChop = {
            min = 6,
            max = 6
        },
        damageSlash = {
            min = 3,
            max = 3
        },
        damageThrust = {
            min = 3,
            max = 3
        },
        flags = 0
    },

    -- Ocarina (as 2-handed spear)
    {
        id = "bcw_ocarina",
        name = "ocarina",
        subtype = 0, -- Spear (2-handed)
        value = 1000,
        weight = 1,
        icon = "Bardcraft\\tx_ocarina.dds",
        model = "Bardcraft\\hold\\rlts_bc_ocarina.nif",
        health = 1000,
        speed = 1.0,
        reach = 1.0,
        enchantPts = 0,
        damageChop = {
            min = 6,
            max = 6
        },
        damageSlash = {
            min = 3,
            max = 3
        },
        damageThrust = {
            min = 3,
            max = 3
        },
        flags = 0
    },

    -- Fiddle Bow (as dagger for right hand)
    {
        id = "bcw_fiddle_bow",
        name = "fiddle bow",
        subtype = 0, -- Short Blade One Hand (dagger)
        value = 100,
        weight = 0.5,
        icon = "Bardcraft\\tx_fiddle.dds",
        model = "Bardcraft\\hold\\rlts_bc_fiddle_bow.nif",
        health = 1000,
        speed = 1.0,
        reach = 1.0,
        enchantPts = 0,
        damageChop = {
            min = 6,
            max = 6
        },
        damageSlash = {
            min = 3,
            max = 3
        },
        damageThrust = {
            min = 3,
            max = 3
        },
        flags = 0
    },

    -- drum
    {
        id = "bcw_drum",
        name = "Drum",
        subtype = 6,
        value = 100,
        weight = 0.5,
        icon = "m\\tx_de_drum_01.dds",
        model = "Bardcraft\\hold\\drum_guar.nif",
        health = 1000,
        speed = 1.0,
        reach = 1.0,
        enchantPts = 0,
        damageChop = {
            min = 6,
            max = 6
        },
        damageSlash = {
            min = 3,
            max = 3
        },
        damageThrust = {
            min = 3,
            max = 3
        },
        flags = 0
    },
    -- Lute (as 2-handed spear)
    {
        id = "bcw_lute_w",
        name = "lute",
        subtype = 6, -- Spear (2-handed)
        value = 1000,
        weight = 1,
        icon = "Bardcraft\\tx_fiddle.dds",
        model = "Bardcraft\\hold\\musdelutethin_world.nif", -- World/ground mesh
        health = 1000,
        speed = 1.0,
        reach = 1.0,
        enchantPts = 0,
        damageChop = {
            min = 6,
            max = 6
        },
        damageSlash = {
            min = 3,
            max = 3
        },
        damageThrust = {
            min = 3,
            max = 3
        },
        flags = 0
    },

    -- Bass Flute (as 2-handed spear)
    {
        id = "bcw_bassflute_w",
        name = "bassflute",
        subtype = 6, -- Spear (2-handed)
        value = 1000,
        weight = 1,
        icon = "Bardcraft\\tx_flute.dds",
        model = "Bardcraft\\hold\\rlts_bc_bassflute_world.nif", -- World/ground mesh
        health = 1000,
        speed = 1.0,
        reach = 1.0,
        enchantPts = 0,
        damageChop = {
            min = 6,
            max = 6
        },
        damageSlash = {
            min = 3,
            max = 3
        },
        damageThrust = {
            min = 3,
            max = 3
        },
        flags = 0
    },

    -- Ocarina (as 2-handed spear)
    {
        id = "bcw_ocarina_w",
        name = "ocarina",
        subtype = 6, -- Spear (2-handed)
        value = 1000,
        weight = 1,
        icon = "Bardcraft\\tx_ocarina.dds",
        model = "Bardcraft\\hold\\rlts_bc_ocarina_world.nif", -- World/ground mesh
        health = 1000,
        speed = 1.0,
        reach = 1.0,
        enchantPts = 0,
        damageChop = {
            min = 6,
            max = 6
        },
        damageSlash = {
            min = 3,
            max = 3
        },
        damageThrust = {
            min = 3,
            max = 3
        },
        flags = 0
    },

    -- Fiddle (as light source for left hand)
    {
        id = "bcw_fiddle_w",
        name = "fiddle",
        subtype = 11, -- Light (left hand)
        value = 1000,
        weight = 1,
        icon = "Bardcraft\\tx_fiddle.dds",
        model = "Bardcraft\\hold\\rlts_bc_fiddle_world.nif", -- World/ground mesh
        health = 1000,
        speed = 1.0,
        reach = 1.0,
        enchantPts = 0,
        damageChop = {
            min = 6,
            max = 6
        },
        damageSlash = {
            min = 3,
            max = 3
        },
        damageThrust = {
            min = 3,
            max = 3
        },
        flags = 0
    },
}

local logger = require("custom.bardcraft.logger")

-- Initialize and create all custom records
function customRecords.Initialize()
    logger.warn(logger.CATEGORIES.CUSTOMRECORDS, "Initializing custom instrument records...")

    -- Create body part records
    for _, record in ipairs(bodyPartRecords) do
        local recordId = record.id
        local recordData = {}

        -- Copy all fields except id
        for key, value in pairs(record) do
            if key ~= "id" then
                recordData[key] = value
            end
        end

        -- Store in RecordStore as permanent record
        RecordStores["bodypart"].data.permanentRecords[recordId] = recordData

        logger.verbose(logger.CATEGORIES.CUSTOMRECORDS, "Created body part record: " .. recordId)
    end

    -- Create armor records
    for _, record in ipairs(armorRecords) do
        local recordId = record.id
        local recordData = {}

        -- Copy all fields except id
        for key, value in pairs(record) do
            if key ~= "id" then
                recordData[key] = value
            end
        end

        -- Store in RecordStore as permanent record
        RecordStores["armor"].data.permanentRecords[recordId] = recordData

        logger.verbose(logger.CATEGORIES.CUSTOMRECORDS, "Created armor record: " .. recordId)
    end

    -- Create weapon records
    for _, record in ipairs(weaponRecords) do
        local recordId = record.id
        local recordData = {}

        -- Copy all fields except id
        for key, value in pairs(record) do
            if key ~= "id" then
                recordData[key] = value
            end
        end

        -- Store in RecordStore as permanent record
        RecordStores["weapon"].data.permanentRecords[recordId] = recordData

        logger.verbose(logger.CATEGORIES.CUSTOMRECORDS, "Created weapon record: " .. recordId)
    end

    -- Save RecordStores to disk
    customRecords.SaveRecords()

    logger.warn(logger.CATEGORIES.CUSTOMRECORDS, "Custom instrument records initialized and saved")
end

-- Save records to disk
function customRecords.SaveRecords()
    RecordStores["bodypart"]:Save()
    RecordStores["armor"]:Save()
    RecordStores["weapon"]:Save()
    logger.warn(logger.CATEGORIES.CUSTOMRECORDS, "Saved body part, armor and weapon records to disk")
end

return customRecords
