local berserkMode = {}

------------------------------------------------------------
-- Constants
------------------------------------------------------------
local haloMessages = {"RAGE!", "BLOOD!", "AARRGH!", "DESTROY!", "KILL!", "SMASH!", "DIE!"}
local warCries = {"RAAAGH!", "COME ON!", "MORE!", "AAAARGH!", "GRAAAH!", "I'LL KILL YOU ALL!"}

------------------------------------------------------------
-- Wound counter helper
------------------------------------------------------------
local function countWounds(player)
    local result = {scratches=0, bites=0, deepWounds=0}
    pcall(function()
        local bd = player:getBodyDamage()
        local parts = bd:getBodyParts()
        for i = 0, parts:size() - 1 do
            local bp = parts:get(i)
            if bp:scratched() then result.scratches = result.scratches + 1 end
            if bp:bitten() then result.bites = result.bites + 1 end
            if bp:deepWounded() then result.deepWounds = result.deepWounds + 1 end
        end
    end)
    return result
end

------------------------------------------------------------
-- Core functions
------------------------------------------------------------

---@param player IsoPlayer|IsoGameCharacter
function berserkMode.enter(player, berserkData)
    berserkMode.rollNextDuration(player, berserkData)
    berserkData.ready = false
    player:SayShout(SandboxVars.BerserkBeaver.message or "BERSERK")
    player:getStats():setAnger(1)

    berserkData.stats = {}
    berserkData.haloTimer = 0
    berserkData.cryTimer = 0
    berserkData.woundsAtEntry = countWounds(player)

    berserkData.skills = {}
    for i=1, Perks.getMaxIndex()-1 do
        local perk = Perks.fromIndex(i)
        if perk and (perk:getParent()==Perks.Combat or perk==Perks.Aiming) and perk~=Perks.Maintenance then
            local lvl = player:getPerkLevel(perk)
            local prevXP = (lvl > 0) and perk:getTotalXpForLevel(lvl) or 0
            local xp = player:getXp():getXP(perk) - prevXP
            berserkData.skills[perk:getId()] = {lvl=lvl, xp=xp}
            for n=lvl, 10 do player:LevelPerk(perk, false) end
            player:getXp():setXPToLevel(perk, player:getPerkLevel(perk))
        end
    end
end


---@param player IsoPlayer|IsoGameCharacter
function berserkMode.exit(player, berserkData)
    local pStats = player:getStats()
    pStats:setAnger(0)
    berserkMode.rollNextTime(player, berserkData)
    if getDebug() then print("BERSERK FINISHED") end

    if berserkData.skills then
        local pXp = player:getXp()
        for perkID, lvlXp in pairs(berserkData.skills) do
            local perk = Perks[perkID]
            if perk then
                for i=10, lvlXp.lvl+1, -1 do player:LoseLevel(perk) end
                pXp:setXPToLevel(perk, player:getPerkLevel(perk))
                pXp:AddXP(perk, lvlXp.xp, true, false, true)
            end
        end
        berserkData.skills = {}
    end

    if berserkData.stats then
        pStats:setThirst(berserkData.stats.thirst or 0)
        pStats:setHunger(berserkData.stats.hunger or 0)
        pStats:setEndurance(berserkData.stats.endurance or 1)
        pStats:setFatigue(berserkData.stats.fatigue or 0)
        pStats:setStress(berserkData.stats.stress or 0)
        pStats:setPanic(berserkData.stats.panic or 0)
        pStats:setMorale(berserkData.stats.morale or 0)
        berserkData.stats = nil
    end

    -- Wound awareness report
    local woundsNow = countWounds(player)
    local entry = berserkData.woundsAtEntry or {scratches=0, bites=0, deepWounds=0}
    local nS = math.max(0, woundsNow.scratches - entry.scratches)
    local nB = math.max(0, woundsNow.bites - entry.bites)
    local nD = math.max(0, woundsNow.deepWounds - entry.deepWounds)
    if nS > 0 or nB > 0 or nD > 0 then
        local parts = {}
        if nS > 0 then table.insert(parts, nS .. " scratch(es)") end
        if nB > 0 then table.insert(parts, nB .. " bite(s)") end
        if nD > 0 then table.insert(parts, nD .. " deep wound(s)") end
        local msg = "You took " .. table.concat(parts, ", ") .. " during your rage..."
        pcall(function() player:setHaloNote(msg, 255, 50, 50, 255) end)
    end
    berserkData.woundsAtEntry = nil
end


function berserkMode.rollNextTime(player, berserkData)
    local hrs = player:getHoursSurvived()
    local addMin = SandboxVars.BerserkBeaver.minInterval
    local addMax = SandboxVars.BerserkBeaver.maxInterval + 1
    berserkData.timeToRage = math.max(hrs, berserkData.timeToRage) + ZombRand(addMin, addMax)
    berserkData.ready = false
    if getDebug() then print(" - berserkData.timeToRage: "..berserkData.timeToRage) end
end

function berserkMode.rollNextDuration(player, berserkData)
    local addMin = SandboxVars.BerserkBeaver.durationMin
    local addMax = SandboxVars.BerserkBeaver.durationMax + 1
    berserkData.duration = ZombRand(addMin, addMax)
    if getDebug() then print(" - berserkData.duration: "..berserkData.duration) end
end

function berserkMode.setOrGetBerserkData(player)
    local pMD = player:getModData()
    if pMD.berserkBigBadBeaverData then return pMD.berserkBigBadBeaverData end
    pMD.berserkBigBadBeaverData = {
        timeToRage = 0, duration = -1, ready = false,
        haloTimer = 0, cryTimer = 0, heartbeatTimer = 0,
    }
    berserkMode.rollNextTime(player, pMD.berserkBigBadBeaverData)
    return pMD.berserkBigBadBeaverData
end


---@param player IsoPlayer|IsoGameCharacter
function berserkMode.update(player)
    local hrs = player:getHoursSurvived()
    local bd = berserkMode.setOrGetBerserkData(player)
    local gameTime = getGameTime()
    local tick = 1 / gameTime:getMinutesPerDay() / 60 * gameTime:getMultiplier() / 2

    if bd.duration > 0.00 then
        local pStats = player:getStats()

        if bd.duration > 2 then pStats:setAnger(1) else pStats:setAnger(bd.duration/2) end

        if bd.stats then
            local r = SandboxVars.BerserkBeaver.recoilMultiplier
            bd.stats.thirst = (bd.stats.thirst or 0) + (pStats:getThirst()*r); pStats:setThirst(0)
            bd.stats.hunger = (bd.stats.hunger or 0) + (pStats:getHunger()*r); pStats:setHunger(0)
            bd.stats.endurance = (bd.stats.endurance or 0) + ((1-pStats:getEndurance())*r); pStats:setEndurance(1)
            bd.stats.fatigue = (bd.stats.fatigue or 0) + (pStats:getFatigue()*r); pStats:setFatigue(0)
            bd.stats.stress = (bd.stats.stress or 0) + (pStats:getStress()*r); pStats:setStress(0)
            bd.stats.panic = (bd.stats.panic or 0) + (pStats:getPanic()*r); pStats:setPanic(0)
            bd.stats.morale = (bd.stats.morale or 0) + (pStats:getMorale()*r); pStats:setMorale(0)
        end

        -- Knockdown resistance
        pcall(function() if player:isKnockedDown() then player:setKnockedDown(false) end end)

        -- Halo text
        bd.haloTimer = (bd.haloTimer or 0) + tick
        if bd.haloTimer >= 0.025 then
            bd.haloTimer = 0
            pcall(function() player:setHaloNote(haloMessages[ZombRand(1, #haloMessages+1)], 255, 30, 30, 255) end)
        end

        -- War cries
        if SandboxVars.BerserkBeaver.warCries then
            bd.cryTimer = (bd.cryTimer or 0) + tick
            if bd.cryTimer >= 0.067 then
                bd.cryTimer = 0
                player:SayShout(warCries[ZombRand(1, #warCries+1)])
            end
        end

        bd.duration = bd.duration - tick
        if bd.duration <= 0.000 then bd.duration = 0; berserkMode.exit(player, bd) end

    elseif bd.timeToRage <= hrs and (not player:isAsleep()) then
        if not bd.ready then bd.ready = true end
        player:getStats():setAnger(1)

    elseif bd.timeToRage > hrs then
        local closeTo = bd.timeToRage - hrs
        if closeTo <= 2 then
            player:getStats():setAnger(math.min(1, (2-closeTo)/2)*0.75)
        end
    end
end
Events.OnPlayerUpdate.Add(berserkMode.update)


------------------------------------------------------------
-- Combat trigger
------------------------------------------------------------
function berserkMode.onWeaponHit(attacker, target, weapon, damage)
    if not attacker or not target then return end
    local player = getPlayer()
    if not player or attacker ~= player then return end
    if not instanceof(target, "IsoZombie") then return end
    local bd = berserkMode.setOrGetBerserkData(player)
    if bd.ready and bd.duration <= 0 then berserkMode.enter(player, bd) end
end
Events.OnWeaponHitCharacter.Add(berserkMode.onWeaponHit)


return berserkMode