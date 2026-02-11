--[[
Bardcraft Inventory Management
Handles instrument inventory checks and swapping for performances
]]

local inventory = {}

local logger = require("custom.bardcraft.logger")

-- Mapping of instrument types to their bcw_ weapon IDs and bca_ animation prop IDs
inventory.INSTRUMENT_ITEMS = {
    Lute = {
        weapon = "bcw_lute",  -- Weapon version (inventory check)
        prop = "bca_lute",    -- Animation prop (equipped during performance)
        world = "bcw_lute_w", -- World model (dropped version)
    },
    Drum = {
        weapon = "bcw_drum",
        prop = "bca_drum",
        world = "misc_de_drum_02",
    },
    Fiddle = {
        weapon = "bca_fiddle_shield", -- not a weapon... oh well
        bow = "bcw_fiddle_bow",
        prop = "bca_fiddle",
        world = "bcw_fiddle_w",
    },
    Ocarina = {
        weapon = "bcw_ocarina",
        prop = "bca_ocarina",
        world = "bcw_ocarina_w",
    },
    BassFlute = {
        weapon = "bcw_bassflute",
        prop = "bca_bassflute",
        world = "bcw_bassflute_w",
    },
}

-- Store original equipped weapon state for restoration
inventory.equippedWeapons = {}
inventory.equippedGreaves = {} -- Also need to store greaves since bca_ uses that slot
inventory.equippedShields = {} -- Store shields for fiddle

-- Check if player has the required instrument in inventory
function inventory.HasInstrument(pid, instrumentType)
    local config = require("custom.bardcraft.config")
    local instrumentData = inventory.INSTRUMENT_ITEMS[instrumentType]

    if not instrumentData or not instrumentData.weapon then
        return false
    end

    -- Check if inventory requirement is enabled (default: true)
    local requireInstrument = config.requireInstrumentInInventory
    if requireInstrument == nil then
        requireInstrument = true
    end

    -- If requirement is disabled, always return true (admin bypass)
    if not requireInstrument then
        return true
    end

    local weaponId = instrumentData.weapon
    local playerInventory = Players[pid].data.inventory

    -- Special case for Fiddle: also need to check for bow
    if instrumentType == "Fiddle" and instrumentData.bow then
        local hasShield = false
        local hasBow = false

        for _, item in pairs(playerInventory) do
            if item.refId == weaponId and item.count > 0 then
                hasShield = true
            end
            if item.refId == instrumentData.bow and item.count > 0 then
                hasBow = true
            end
        end

        return hasShield and hasBow
    end

    -- Search through player's inventory for the weapon
    for _, item in pairs(playerInventory) do
        if item.refId == weaponId and item.count > 0 then
            return true
        end
    end

    return false
end

-- Get instrument type from weapon ID
function inventory.GetInstrumentTypeFromWeapon(weaponId)
    for instrumentType, data in pairs(inventory.INSTRUMENT_ITEMS) do
        if data.weapon == weaponId then
            return instrumentType
        end
    end
    return nil
end

-- Get instrument type from world ID
function inventory.GetInstrumentTypeFromWorld(worldId)
    for instrumentType, data in pairs(inventory.INSTRUMENT_ITEMS) do
        if data.world == worldId then
            return instrumentType
        end
    end
    return nil
end

-- Convert weapon ID to world ID for dropping
function inventory.ConvertWeaponToWorld(weaponId)
    for instrumentType, data in pairs(inventory.INSTRUMENT_ITEMS) do
        if data.weapon == weaponId then
            return data.world
        end
    end
    return weaponId -- Return original if not an instrument
end

-- Convert world ID to weapon ID for picking up
function inventory.ConvertWorldToWeapon(worldId)
    for instrumentType, data in pairs(inventory.INSTRUMENT_ITEMS) do
        if data.world == worldId then
            return data.weapon
        end
    end
    return worldId -- Return original if not an instrument
end

-- Check if an item is a bardcraft instrument (weapon or world version)
function inventory.IsBardcraftInstrument(refId)
    -- Check if it's a weapon version
    for _, data in pairs(inventory.INSTRUMENT_ITEMS) do
        if data.weapon == refId or data.world == refId then
            return true
        end
    end
    return false
end

function inventory.GetAvailableInstruments(pid)
    local available = {}

    for instrumentType, _ in pairs(inventory.INSTRUMENT_ITEMS) do
        if inventory.HasInstrument(pid, instrumentType) then
            table.insert(available, instrumentType)
        end
    end

    return available
end

-- Equip animation prop and unequip weapon when performance starts
function inventory.OnPerformanceStart(pid, instrumentType)
    local instrumentData = inventory.INSTRUMENT_ITEMS[instrumentType]
    if not instrumentData then
        logger.error(logger.CATEGORIES.INVENTORY,
            string.format("Unknown instrument type: %s", tostring(instrumentType)))
        return
    end

    -- Store currently equipped weapon (if any) for restoration later
    inventory.equippedWeapons[pid] = inventory.GetEquippedWeapon(pid)

    -- Store currently equipped greaves (since bca_ props use slot 2)
    local equipment = Players[pid].data.equipment
    if equipment[2] and equipment[2].refId and equipment[2].refId ~= "" then
        inventory.equippedGreaves[pid] = equipment[2].refId
        logger.info(logger.CATEGORIES.INVENTORY,
            string.format("Stored equipped greaves for pid %d: %s",
                pid, inventory.equippedGreaves[pid]))
    end

    -- Store currently equipped shield (for fiddle shield slot 8)
    if equipment[17] and equipment[17].refId and equipment[17].refId ~= "" then
        inventory.equippedShields[pid] = equipment[17].refId
        logger.info(logger.CATEGORIES.INVENTORY,
            string.format("Stored equipped shield for pid %d: %s",
                pid, inventory.equippedShields[pid]))
    end

    logger.info(logger.CATEGORIES.INVENTORY,
        string.format("Stored equipped weapon for pid %d: %s",
            pid, tostring(inventory.equippedWeapons[pid])))

    -- Special case for Fiddle: unequip shield if equipped, keep bow equipped
    if instrumentType == "Fiddle" then
        -- Check if the fiddle shield is currently equipped in slot 8 and unequip it
        if equipment[17] and equipment[17].refId == instrumentData.weapon then
            inventory.UnequipItem(pid, instrumentData.weapon)
            logger.info(logger.CATEGORIES.INVENTORY,
                string.format("Unequipped fiddle shield '%s' from slot 17 for pid %d",
                    instrumentData.weapon, pid))
        else
            logger.info(logger.CATEGORIES.INVENTORY,
                string.format("Fiddle shield not equipped in slot 8 for pid %d (shield slot: %s)",
                    pid, equipment[8] and equipment[8].refId or "empty"))
        end

        -- Check if bow is equipped, if not equip it
        local bowEquipped = equipment[16] and equipment[16].refId == instrumentData.bow
        if not bowEquipped then
            -- Unequip current weapon first (only if it's not the bow)
            if inventory.equippedWeapons[pid] and inventory.equippedWeapons[pid] ~= instrumentData.bow then
                inventory.UnequipItem(pid, inventory.equippedWeapons[pid])
                logger.info(logger.CATEGORIES.INVENTORY,
                    string.format("Unequipped weapon '%s' for pid %d",
                        inventory.equippedWeapons[pid], pid))
            end

            -- Equip the bow
            inventory.EquipItem(pid, instrumentData.bow)
            logger.info(logger.CATEGORIES.INVENTORY,
                string.format("Equipped fiddle bow '%s' for pid %d",
                    instrumentData.bow, pid))
        else
            logger.info(logger.CATEGORIES.INVENTORY,
                string.format("Fiddle bow already equipped for pid %d", pid))
        end
    else
        -- Unequip current weapon first (for non-fiddle instruments)
        if inventory.equippedWeapons[pid] then
            inventory.UnequipItem(pid, inventory.equippedWeapons[pid])
            logger.info(logger.CATEGORIES.INVENTORY,
                string.format("Unequipped weapon '%s' for pid %d",
                    inventory.equippedWeapons[pid], pid))
        end
    end

    -- Add and equip the animation prop (will go in slot 2 - greaves)
    local propId = instrumentData.prop
    inventory.AddItem(pid, propId, 1)

    logger.info(logger.CATEGORIES.INVENTORY,
        string.format("Added '%s' to inventory for pid %d", propId, pid))

    inventory.EquipItem(pid, propId)

    logger.info(logger.CATEGORIES.INVENTORY,
        string.format("Equipped '%s' for pid %d", propId, pid))
end

-- Remove animation prop and re-equip original weapon when performance ends
function inventory.OnPerformanceEnd(pid, instrumentType)
    local instrumentData = inventory.INSTRUMENT_ITEMS[instrumentType]
    if not instrumentData then
        logger.warn(logger.CATEGORIES.INVENTORY,
            string.format("Unknown instrument type on end: %s",
                tostring(instrumentType)))
        return
    end

    logger.info(logger.CATEGORIES.INVENTORY,
        string.format("Performance ending for pid %d, instrument: %s",
            pid, instrumentType))

    -- Remove the animation prop (from slot 2 - greaves)
    local propId = instrumentData.prop
    inventory.UnequipItem(pid, propId)
    logger.info(logger.CATEGORIES.INVENTORY,
        string.format("Unequipped '%s' for pid %d", propId, pid))

    -- Remove from inventory
    inventory.RemoveItem(pid, propId, 1)
    logger.info(logger.CATEGORIES.INVENTORY,
        string.format("Removed '%s' from inventory for pid %d", propId, pid))

    -- Re-equip original greaves if they were equipped before
    local originalGreaves = inventory.equippedGreaves[pid]
    if originalGreaves then
        logger.info(logger.CATEGORIES.INVENTORY,
            string.format("Attempting to re-equip original greaves '%s' for pid %d",
                originalGreaves, pid))

        if inventory.HasItemInInventory(pid, originalGreaves) then
            inventory.EquipItem(pid, originalGreaves)
            logger.info(logger.CATEGORIES.INVENTORY,
                string.format("Re-equipped greaves '%s' for pid %d",
                    originalGreaves, pid))
        end
    end

    -- Special case for Fiddle: re-equip shield if it was equipped before
    if instrumentType == "Fiddle" then
        local originalShield = inventory.equippedShields[pid]
        if originalShield then
            logger.info(logger.CATEGORIES.INVENTORY,
                string.format("Attempting to re-equip original shield '%s' for pid %d",
                    originalShield, pid))

            if inventory.HasItemInInventory(pid, originalShield) then
                inventory.EquipItem(pid, originalShield)
                logger.info(logger.CATEGORIES.INVENTORY,
                    string.format("Re-equipped shield '%s' for pid %d",
                        originalShield, pid))
            else
                logger.warn(logger.CATEGORIES.INVENTORY,
                    string.format("Original shield '%s' no longer in inventory for pid %d",
                        originalShield, pid))
            end
        end
    end

    -- Re-equip original weapon (special case for Fiddle: don't unequip the bow)
    local originalWeapon = inventory.equippedWeapons[pid]

    -- For Fiddle: only re-equip if the original weapon wasn't the bow
    if instrumentType == "Fiddle" then
        if originalWeapon and originalWeapon ~= instrumentData.bow then
            logger.info(logger.CATEGORIES.INVENTORY,
                string.format("Attempting to re-equip original weapon '%s' for pid %d",
                    originalWeapon, pid))

            if inventory.HasItemInInventory(pid, originalWeapon) then
                inventory.EquipItem(pid, originalWeapon)
                logger.info(logger.CATEGORIES.INVENTORY,
                    string.format("Re-equipped weapon '%s' for pid %d",
                        originalWeapon, pid))
            else
                logger.warn(logger.CATEGORIES.INVENTORY,
                    string.format("Original weapon '%s' no longer in inventory for pid %d",
                        originalWeapon, pid))
            end
        else
            logger.info(logger.CATEGORIES.INVENTORY,
                string.format("Leaving fiddle bow equipped for pid %d", pid))
        end
    else
        -- For other instruments: always try to re-equip original weapon
        if originalWeapon then
            logger.info(logger.CATEGORIES.INVENTORY,
                string.format("Attempting to re-equip original weapon '%s' for pid %d",
                    originalWeapon, pid))

            if inventory.HasItemInInventory(pid, originalWeapon) then
                inventory.EquipItem(pid, originalWeapon)
                logger.info(logger.CATEGORIES.INVENTORY,
                    string.format("Re-equipped weapon '%s' for pid %d",
                        originalWeapon, pid))
            else
                logger.warn(logger.CATEGORIES.INVENTORY,
                    string.format("Original weapon '%s' no longer in inventory for pid %d",
                        originalWeapon, pid))
            end
        else
            logger.info(logger.CATEGORIES.INVENTORY,
                string.format("No original weapon to re-equip for pid %d", pid))
        end
    end

    -- Clear stored equipment state
    inventory.equippedWeapons[pid] = nil
    inventory.equippedGreaves[pid] = nil
    inventory.equippedShields[pid] = nil
end

-- Helper: Get currently equipped weapon (returns refId or nil)
function inventory.GetEquippedWeapon(pid)
    local equipment = Players[pid].data.equipment

    -- Check weapon slot (slot 16 in TES3MP)
    local weaponSlot = 16


    if equipment[weaponSlot] and equipment[weaponSlot].refId and equipment[weaponSlot].refId ~= "" then
        logger.info(logger.CATEGORIES.INVENTORY,
            string.format("Found equipped weapon in slot %d: %s",
                weaponSlot, equipment[weaponSlot].refId))
        return equipment[weaponSlot].refId
    end


    logger.info(logger.CATEGORIES.INVENTORY,
        string.format("No weapon equipped for pid %d", pid))
    return nil
end

-- Helper: Check if player has item in inventory
function inventory.HasItemInInventory(pid, refId)
    local playerInventory = Players[pid].data.inventory

    for _, item in pairs(playerInventory) do
        if item.refId == refId and item.count > 0 then
            return true
        end
    end

    return false
end

-- Helper: Add item to player's inventory
function inventory.AddItem(pid, refId, count)
    -- Add to local inventory data
    local playerInventory = Players[pid].data.inventory
    local found = false

    for _, item in pairs(playerInventory) do
        if item.refId == refId then
            item.count = item.count + count
            found = true
            break
        end
    end

    if not found then
        table.insert(playerInventory, {
            refId = refId,
            count = count,
            charge = -1,
            enchantmentCharge = -1,
            soul = ""
        })
    end

    -- Send to client using proper API
    Players[pid]:LoadItemChanges({
        {
            refId = refId,
            count = count,
            charge = -1,
            enchantmentCharge = -1,
            soul = ""
        }
    }, enumerations.inventory.ADD)

    Players[pid]:Save()

    logger.info(logger.CATEGORIES.INVENTORY,
        string.format("Added %d x '%s' to pid %d", count, refId, pid))
end

-- Helper: Remove item from player's inventory
function inventory.RemoveItem(pid, refId, count)
    local playerInventory = Players[pid].data.inventory
    local found = false
    local removeCount = 0

    for index, item in pairs(playerInventory) do
        if item.refId == refId then
            found = true
            removeCount = math.min(item.count, count)

            -- Update local data
            item.count = item.count - removeCount
            if item.count <= 0 then
                playerInventory[index] = nil
            end

            -- Send to client
            Players[pid]:LoadItemChanges({
                {
                    refId = refId,
                    count = removeCount,
                    charge = -1,
                    enchantmentCharge = -1,
                    soul = ""
                }
            }, enumerations.inventory.REMOVE)

            Players[pid]:Save()

            logger.info(logger.CATEGORIES.INVENTORY,
                string.format("Removed %d x '%s' from pid %d",
                    removeCount, refId, pid))
            break
        end
    end

    if not found then
        logger.warn(logger.CATEGORIES.INVENTORY,
            string.format("Could not find '%s' to remove for pid %d",
                refId, pid))
    end
end

-- Helper: Determine equipment slot for an item based on refId
function inventory.GetItemSlot(refId)

    local refIdLower = refId:lower()

    -- bca_fiddle_shield goes in shield slot (slot 8)
    if refIdLower == "bca_fiddle_shield" then
        return 17 -- Shield slot
    end

    -- Other bca_ instruments (animation props) go in greaves slot for animations to work
    if refIdLower:match("^bca_") then
        return 2 -- Greaves slot (left pauldron) for animation props
    end

    -- bcw_ weapons and other weapons go in weapon slot
    if refIdLower:match("^bcw_") then
        return 16 -- Weapon slot for bardcraft weapons
    end

    -- Check for other weapon types
    if refIdLower:match("_bow") or refIdLower:match("bow_") then
        return 16
    end

    if refIdLower:match("sword") or refIdLower:match("axe") or
        refIdLower:match("mace") or refIdLower:match("dagger") or
        refIdLower:match("spear") or refIdLower:match("staff") or
        refIdLower:match("club") or refIdLower:match("blade") then
        return 16
    end

    -- Check for shields
    if refIdLower:match("shield") then
        return 8
    end

    -- Default to weapon slot if unknown
    return 16
end

-- Helper: Equip item
function inventory.EquipItem(pid, refId)
    -- Get the item from inventory to preserve its state
    local playerInventory = Players[pid].data.inventory
    local itemToEquip = nil

    for _, item in pairs(playerInventory) do
        if item.refId == refId then
            itemToEquip = item
            break
        end
    end

    if not itemToEquip then
        logger.warn(logger.CATEGORIES.INVENTORY,
            string.format("Cannot equip '%s' - not in inventory for pid %d",
                refId, pid))
        return false
    end

    -- Determine the appropriate slot for this item
    local slot = inventory.GetItemSlot(refId)

    -- Update local equipment data
    Players[pid].data.equipment[slot] = {
        refId = refId,
        count = 1,
        charge = itemToEquip.charge or -1,
        enchantmentCharge = itemToEquip.enchantmentCharge or -1,
        soul = itemToEquip.soul or ""
    }

    -- Send equipment packet to client
    Players[pid]:LoadEquipment()

    logger.info(logger.CATEGORIES.INVENTORY,
        string.format("Equipped '%s' in slot %d for pid %d", refId, slot, pid))

    return true
end

-- Helper: Unequip item
function inventory.UnequipItem(pid, refId)
    if not refId or refId == "" then
        logger.warn(logger.CATEGORIES.INVENTORY,
            string.format("Cannot unequip - empty refId for pid %d", pid))
        return false
    end

    local equipment = Players[pid].data.equipment
    local foundSlot = nil

    for slot, item in pairs(equipment) do
        if item and item.refId == refId then
            foundSlot = slot
            break
        end
    end

    if not foundSlot then
        logger.warn(logger.CATEGORIES.INVENTORY,
            string.format("Item '%s' not equipped for pid %d", refId, pid))
        return false
    end

    -- Clear the equipment slot in local data
    equipment[foundSlot] = {
        refId = "",
        count = 0,
        charge = -1,
        enchantmentCharge = -1,
        soul = ""
    }

    -- Send equipment update to client
    Players[pid]:LoadEquipment()

    logger.info(logger.CATEGORIES.INVENTORY,
        string.format("Unequipped '%s' from slot %d for pid %d",
            refId, foundSlot, pid))

    return true
end

-- Handle item being dropped into world
-- This should be called from OnObjectPlace or similar event
function inventory.OnItemDrop(pid, refId, count, itemData)
    local worldId = inventory.ConvertWeaponToWorld(refId)

    if worldId ~= refId then
        -- This is a bardcraft instrument, replace with world version
        logger.info(logger.CATEGORIES.INVENTORY,
            string.format("Converting dropped instrument '%s' -> '%s' for pid %d",
                refId, worldId, pid))

        -- Return the world ID to be used instead
        return worldId
    end

    -- Not a bardcraft instrument, return original
    return refId
end

-- Handle item being picked up from world
-- This should be called from OnObjectDelete or similar event
function inventory.OnItemPickup(pid, refId, count)
    local weaponId = inventory.ConvertWorldToWeapon(refId)

    if weaponId ~= refId then
        -- This is a bardcraft instrument world model, convert to weapon
        logger.info(logger.CATEGORIES.INVENTORY,
            string.format("Converting picked up instrument '%s' -> '%s' for pid %d",
                refId, weaponId, pid))

        -- Remove the world version (if somehow in inventory)
        inventory.RemoveItem(pid, refId, count)

        -- Add the weapon version
        inventory.AddItem(pid, weaponId, count)

        return weaponId
    end

    -- Not a bardcraft instrument, return original
    return refId
end

return inventory
