local berserkMode = {}


------------------------------------------------------------
-- B42 Stats API adapter
-- B42 removed setAnger/getAnger/setThirst/etc from Stats.
-- Now uses Stats:get(CharacterStat) / Stats:set(CharacterStat, float)
-- with CharacterStat.ANGER, CharacterStat.THIRST, etc.
------------------------------------------------------------

local function statGet(pStats, charStat)
    return pStats:get(charStat)
end

local function statSet(pStats, charStat, value)
    pStats:set(charStat, value)
end


---@param player IsoPlayer|IsoGameCharacter
function berserkMode.enter(player, berserkData)
    berserkMode.rollNextDuration(player, berserkData)
    berserkData.ready = false
    player:SayShout(SandboxVars.BerserkBeaver.message or "BERSERK")
    statSet(player:getStats(), CharacterStat.ANGER, 1)
    berserkData.stats = {}
    berserkData.skills = {}
    for i=1, Perks.getMaxIndex()-1 do
        ---@type PerkFactory.Perk
        local perk = Perks.fromIndex(i)
        if perk and (perk:getParent()==Perks.Combat or perk==Perks.Aiming) and perk~=Perks.Maintenance then

            local lvl = player:getPerkLevel(perk)
            local prevXP = (lvl > 0) and perk:getTotalXpForLevel(lvl) or 0
            local xp = player:getXp():getXP(perk) - prevXP

            berserkData.skills[perk:getId()] = {lvl=lvl,xp=xp}
            for n=lvl, 10 do player:LevelPerk(perk, false) end
            player:getXp():setXPToLevel(perk, player:getPerkLevel(perk))
        end
    end
end


---@param player IsoPlayer|IsoGameCharacter
function berserkMode.exit(player, berserkData)
    local pStats = player:getStats()
    statSet(pStats, CharacterStat.ANGER, 0)
    berserkMode.rollNextTime(player, berserkData)
    if getDebug() then print("BERSERK FINISHED: ") end

    if not berserkData.skills then return end
    local pXp = player:getXp()

    for perkID,lvlXp in pairs(berserkData.skills) do
        local perk = Perks[perkID]
        if perk then
            for i=10, lvlXp.lvl+1, -1 do player:LoseLevel(perk) end
            pXp:setXPToLevel(perk, player:getPerkLevel(perk))
            pXp:AddXP(perk, lvlXp.xp, true, false, true)
        end
    end

    berserkData.skills = {}

    if berserkData.stats then
        statSet(pStats, CharacterStat.THIRST,    berserkData.stats.thirst)
        statSet(pStats, CharacterStat.HUNGER,    berserkData.stats.hunger)
        statSet(pStats, CharacterStat.ENDURANCE, berserkData.stats.endurance)
        statSet(pStats, CharacterStat.FATIGUE,   berserkData.stats.fatigue)
        statSet(pStats, CharacterStat.STRESS,    berserkData.stats.stress)
        statSet(pStats, CharacterStat.PANIC,     berserkData.stats.panic)
        statSet(pStats, CharacterStat.MORALE,    berserkData.stats.morale)
        berserkData.stats = nil
    end
end


---@param player IsoPlayer|IsoGameCharacter
function berserkMode.rollNextTime(player, berserkData)
    local playerHoursSurvived = player:getHoursSurvived()
    local addedHourMin = SandboxVars.BerserkBeaver.minInterval
    local addedHourMax = SandboxVars.BerserkBeaver.maxInterval+1 --ZombRand is exclusive to max arg
    berserkData.timeToRage = math.max(playerHoursSurvived,berserkData.timeToRage) + ZombRand(addedHourMin,addedHourMax)
    berserkData.ready = false
    if getDebug() then print(" - berserkData.timeToRage: "..berserkData.timeToRage) end
end


function berserkMode.rollNextDuration(player, berserkData)
    local addedDurationMin = SandboxVars.BerserkBeaver.durationMin
    local addedDurationMax = SandboxVars.BerserkBeaver.durationMax+1 --ZombRand is exclusive to max arg
    berserkData.duration = ZombRand(addedDurationMin,addedDurationMax)
    if getDebug() then print(" - berserkData.duration: "..berserkData.duration) end
end

---set modData - or send back found data
function berserkMode.setOrGetBerserkData(player)
    local pMD = player:getModData()

    if pMD.berserkBigBadBeaverData then return pMD.berserkBigBadBeaverData end

    pMD.berserkBigBadBeaverData = {}
    pMD.berserkBigBadBeaverData.timeToRage = 0
    pMD.berserkBigBadBeaverData.duration = -1
    pMD.berserkBigBadBeaverData.ready = false

    berserkMode.rollNextTime(player, pMD.berserkBigBadBeaverData)

    return pMD.berserkBigBadBeaverData
end


---@param player IsoPlayer|IsoGameCharacter
function berserkMode.update(player)

    local playerHoursSurvived = player:getHoursSurvived()
    local berserkData = berserkMode.setOrGetBerserkData(player)

    if berserkData.duration > 0.00 then
        -- BERSERK ACTIVE: manage anger, suppress stats, tick down duration
        local pStats = player:getStats()

        if berserkData.duration > 2 then
            statSet(pStats, CharacterStat.ANGER, 1)
        else
            local angerLevel = berserkData.duration/2
            statSet(pStats, CharacterStat.ANGER, angerLevel)
        end

        if berserkData.stats then
            berserkData.stats.thirst = (berserkData.stats.thirst or 0) + (statGet(pStats, CharacterStat.THIRST)*SandboxVars.BerserkBeaver.recoilMultiplier)
            statSet(pStats, CharacterStat.THIRST, 0)
            berserkData.stats.hunger = (berserkData.stats.hunger or 0) + (statGet(pStats, CharacterStat.HUNGER)*SandboxVars.BerserkBeaver.recoilMultiplier)
            statSet(pStats, CharacterStat.HUNGER, 0)
            berserkData.stats.endurance = (berserkData.stats.endurance or 0) + ((1-statGet(pStats, CharacterStat.ENDURANCE))*SandboxVars.BerserkBeaver.recoilMultiplier)
            statSet(pStats, CharacterStat.ENDURANCE, 1)
            berserkData.stats.fatigue = (berserkData.stats.fatigue or 0) + (statGet(pStats, CharacterStat.FATIGUE)*SandboxVars.BerserkBeaver.recoilMultiplier)
            statSet(pStats, CharacterStat.FATIGUE, 0)
            berserkData.stats.stress = (berserkData.stats.stress or 0) + (statGet(pStats, CharacterStat.STRESS)*SandboxVars.BerserkBeaver.recoilMultiplier)
            statSet(pStats, CharacterStat.STRESS, 0)
            berserkData.stats.panic = (berserkData.stats.panic or 0) + (statGet(pStats, CharacterStat.PANIC)*SandboxVars.BerserkBeaver.recoilMultiplier)
            statSet(pStats, CharacterStat.PANIC, 0)
            berserkData.stats.morale = (berserkData.stats.morale or 0) + (statGet(pStats, CharacterStat.MORALE)*SandboxVars.BerserkBeaver.recoilMultiplier)
            statSet(pStats, CharacterStat.MORALE, 0)
        end

        local gameTime = getGameTime()
        local tick = 1 / gameTime:getMinutesPerDay() / 60 * gameTime:getMultiplier() / 2

        berserkData.duration = berserkData.duration-tick
        if berserkData.duration <= 0.000 then
            berserkData.duration = 0
            berserkMode.exit(player, berserkData)
        end

    elseif berserkData.timeToRage <= playerHoursSurvived and (not player:isAsleep()) then
        -- RAGE READY: timer expired, mark as ready and wait for combat trigger
        if not berserkData.ready then
            berserkData.ready = true
            if getDebug() then print("[BerserkBeaver] Rage fully accumulated. Awaiting combat trigger...") end
        end
        -- Hold anger at max while waiting for combat
        local pStats = player:getStats()
        statSet(pStats, CharacterStat.ANGER, 1)

    elseif berserkData.timeToRage > playerHoursSurvived then
        -- COOLDOWN: anger warmup in the last 2 hours
        local closeTo = berserkData.timeToRage - playerHoursSurvived
        local warmUp = 2
        if closeTo <= warmUp then
            local angerLevel = math.min(1, (warmUp-closeTo)/warmUp)*0.75
            local pStats = player:getStats()
            statSet(pStats, CharacterStat.ANGER, angerLevel)
        end
    end
end
Events.OnPlayerUpdate.Add(berserkMode.update)


------------------------------------------------------------
-- Combat trigger: berserk activates when player hits a zombie
-- while rage is fully accumulated (ready == true)
------------------------------------------------------------
function berserkMode.onWeaponHit(attacker, target, weapon, damage)
    if not attacker then return end
    if not target then return end

    -- Only trigger for player characters
    local player = getPlayer()
    if not player then return end
    if attacker ~= player then return end

    -- Only trigger on zombie targets
    if not instanceof(target, "IsoZombie") then return end

    local berserkData = berserkMode.setOrGetBerserkData(player)
    if berserkData.ready and berserkData.duration <= 0 then
        if getDebug() then print("[BerserkBeaver] Combat detected! Triggering BERSERK!") end
        berserkMode.enter(player, berserkData)
    end
end
Events.OnWeaponHitCharacter.Add(berserkMode.onWeaponHit)


------------------------------------------------------------
-- Debug commands (global table for Lua console access)
-- Usage in debug console:
--   BerserkDebug.enter()   -- force trigger berserk
--   BerserkDebug.exit()    -- force end berserk
--   BerserkDebug.status()  -- print current state
------------------------------------------------------------
function berserkMode.forceEnter()
    local player = getPlayer()
    if not player then
        print("[BerserkBeaver] ERROR: No player found.")
        return
    end
    local berserkData = berserkMode.setOrGetBerserkData(player)
    if berserkData.duration > 0 then
        print("[BerserkBeaver] Already in berserk mode! Duration remaining: "..berserkData.duration.." hours")
        return
    end
    print("[BerserkBeaver] FORCING BERSERK MODE!")
    berserkMode.enter(player, berserkData)
    print("[BerserkBeaver] Berserk activated. Duration: "..berserkData.duration.." hours")
end

function berserkMode.forceExit()
    local player = getPlayer()
    if not player then
        print("[BerserkBeaver] ERROR: No player found.")
        return
    end
    local berserkData = berserkMode.setOrGetBerserkData(player)
    if berserkData.duration <= 0 then
        print("[BerserkBeaver] Not in berserk mode.")
        return
    end
    print("[BerserkBeaver] FORCING BERSERK EXIT!")
    berserkData.duration = 0
    berserkMode.exit(player, berserkData)
    print("[BerserkBeaver] Berserk deactivated.")
end

function berserkMode.debugStatus()
    local player = getPlayer()
    if not player then
        print("[BerserkBeaver] ERROR: No player found.")
        return
    end
    local berserkData = berserkMode.setOrGetBerserkData(player)
    local hrs = player:getHoursSurvived()
    print("[BerserkBeaver] === STATUS ===")
    print("  Hours survived: "..hrs)
    print("  Time to rage:   "..tostring(berserkData.timeToRage))
    print("  Duration left:  "..tostring(berserkData.duration))
    print("  Ready (waiting for combat): "..tostring(berserkData.ready or false))
    if berserkData.duration > 0 then
        print("  STATE: BERSERK ACTIVE")
    elseif berserkData.ready then
        print("  STATE: RAGE FULL - waiting for zombie hit to trigger")
    elseif berserkData.timeToRage <= hrs then
        print("  STATE: READY TO ARM")
    else
        print("  STATE: COOLDOWN ("..(berserkData.timeToRage - hrs).." hrs until rage full)")
    end
end

BerserkDebug = {
    enter  = berserkMode.forceEnter,
    exit   = berserkMode.forceExit,
    status = berserkMode.debugStatus,
}

return berserkMode
