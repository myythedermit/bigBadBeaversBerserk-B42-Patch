local berserkMode = {}

------------------------------------------------------------
-- B42 Stats API
------------------------------------------------------------
local function statGet(pStats, cs) return pStats:get(cs) end
local function statSet(pStats, cs, v) pStats:set(cs, v) end

------------------------------------------------------------
-- Constants
------------------------------------------------------------
local haloMessages = {"RAGE!", "BLOOD!", "AARRGH!", "DESTROY!", "KILL!", "SMASH!", "DIE!"}
local warCries = {"RAAAGH!", "COME ON!", "MORE!", "AAAARGH!", "GRAAAH!", "I'LL KILL YOU ALL!"}

-- Suppress config: built lazily so CharacterStat is available
local _sCfg = nil
local function getSuppress()
    if _sCfg then return _sCfg end
    _sCfg = {
        {cs=CharacterStat.THIRST,      n=0, inv=false, k="thirst"},
        {cs=CharacterStat.HUNGER,      n=0, inv=false, k="hunger"},
        {cs=CharacterStat.ENDURANCE,   n=1, inv=true,  k="endurance"},
        {cs=CharacterStat.FATIGUE,     n=0, inv=false, k="fatigue"},
        {cs=CharacterStat.STRESS,      n=0, inv=false, k="stress"},
        {cs=CharacterStat.PANIC,       n=0, inv=false, k="panic"},
        {cs=CharacterStat.MORALE,      n=0, inv=false, k="morale"},
        {cs=CharacterStat.PAIN,        n=0, inv=false, k="pain"},
        {cs=CharacterStat.DISCOMFORT,  n=0, inv=false, k="discomfort"},
        {cs=CharacterStat.UNHAPPINESS, n=0, inv=false, k="unhappiness"},
        {cs=CharacterStat.BOREDOM,     n=0, inv=false, k="boredom"},
        {cs=CharacterStat.WETNESS,     n=0, inv=false, k="wetness"},
    }
    return _sCfg
end

------------------------------------------------------------
-- Wound counter helper
------------------------------------------------------------
local function countWounds(player)
    local result = {scratches=0, bites=0, deepWounds=0}
    local ok, _ = pcall(function()
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
    statSet(player:getStats(), CharacterStat.ANGER, 1)

    -- Init stat buffer and timers
    berserkData.stats = {}
    berserkData.haloTimer = 0
    berserkData.cryTimer = 0

    -- Save initial temperature (maintain during berserk, not accumulated)
    berserkData.stats.temperature_hold = statGet(player:getStats(), CharacterStat.TEMPERATURE)

    -- Snapshot wounds before berserk
    berserkData.woundsAtEntry = countWounds(player)

    -- Boost combat skills to 10
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
    statSet(pStats, CharacterStat.ANGER, 0)
    berserkMode.rollNextTime(player, berserkData)
    if getDebug() then print("BERSERK FINISHED") end

    -- Restore skills
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

    -- Restore suppressed stats (recoil)
    if berserkData.stats then
        local cfg = getSuppress()
        for _, e in ipairs(cfg) do
            if berserkData.stats[e.k] then
                if e.inv then
                    statSet(pStats, e.cs, e.n - berserkData.stats[e.k])
                else
                    statSet(pStats, e.cs, berserkData.stats[e.k])
                end
            end
        end
        -- Temperature: just let game take over naturally (don't dump)
        berserkData.stats = nil
    end

    -- Muscle strain recoil: add a burst of strain post-berserk
    pcall(function() player:addCombatMuscleStrain(0.5) end)
    pcall(function() player:addBothArmMuscleStrain(0.3) end)
    pcall(function() player:addBackMuscleStrain(0.3) end)

    -- Wound awareness: report injuries sustained during berserk
    local woundsNow = countWounds(player)
    local entry = berserkData.woundsAtEntry or {scratches=0, bites=0, deepWounds=0}
    local newScratches = math.max(0, woundsNow.scratches - entry.scratches)
    local newBites = math.max(0, woundsNow.bites - entry.bites)
    local newDeep = math.max(0, woundsNow.deepWounds - entry.deepWounds)

    if newScratches > 0 or newBites > 0 or newDeep > 0 then
        local parts = {}
        if newScratches > 0 then table.insert(parts, newScratches .. " scratch(es)") end
        if newBites > 0 then table.insert(parts, newBites .. " bite(s)") end
        if newDeep > 0 then table.insert(parts, newDeep .. " deep wound(s)") end
        local msg = "You took " .. table.concat(parts, ", ") .. " during your rage..."
        player:setHaloNote(msg, 255, 50, 50, 255)
        if getDebug() then print("[BerserkBeaver] " .. msg) end
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
        timeToRage = 0,
        duration = -1,
        ready = false,
        haloTimer = 0,
        cryTimer = 0,
        heartbeatTimer = 0,
    }
    berserkMode.rollNextTime(player, pMD.berserkBigBadBeaverData)
    return pMD.berserkBigBadBeaverData
end


------------------------------------------------------------
-- Main update loop
------------------------------------------------------------
---@param player IsoPlayer|IsoGameCharacter
function berserkMode.update(player)
    local hrs = player:getHoursSurvived()
    local bd = berserkMode.setOrGetBerserkData(player)
    local gameTime = getGameTime()
    local tick = 1 / gameTime:getMinutesPerDay() / 60 * gameTime:getMultiplier() / 2

    if bd.duration > 0.00 then
        -----------------------------------------------
        -- BERSERK ACTIVE
        -----------------------------------------------
        local pStats = player:getStats()

        -- Anger management
        if bd.duration > 2 then
            statSet(pStats, CharacterStat.ANGER, 1)
        else
            statSet(pStats, CharacterStat.ANGER, bd.duration / 2)
        end

        -- Suppress all stats (accumulate for recoil)
        if bd.stats then
            local recoil = SandboxVars.BerserkBeaver.recoilMultiplier
            local cfg = getSuppress()
            for _, e in ipairs(cfg) do
                local cur = statGet(pStats, e.cs)
                if e.inv then
                    bd.stats[e.k] = (bd.stats[e.k] or 0) + ((e.n - cur) * recoil)
                else
                    bd.stats[e.k] = (bd.stats[e.k] or 0) + (cur * recoil)
                end
                statSet(pStats, e.cs, e.n)
            end
            -- Temperature: hold at entry value
            if bd.stats.temperature_hold then
                statSet(pStats, CharacterStat.TEMPERATURE, bd.stats.temperature_hold)
            end
        end

        -- Note: Muscle strain cannot be negated via API (only additive).
        -- PAIN suppression already masks strain effects during berserk.

        -- Knockdown resistance
        pcall(function()
            if player:isKnockedDown() then player:setKnockedDown(false) end
        end)

        -- Periodic halo text (every ~1.5 minutes)
        bd.haloTimer = (bd.haloTimer or 0) + tick
        if bd.haloTimer >= 0.025 then
            bd.haloTimer = 0
            local msg = haloMessages[ZombRand(1, #haloMessages + 1)]
            pcall(function() player:setHaloNote(msg, 255, 30, 30, 255) end)
        end

        -- Periodic war cries (every ~4 minutes)
        bd.cryTimer = (bd.cryTimer or 0) + tick
        if bd.cryTimer >= 0.067 then
            bd.cryTimer = 0
            local cry = warCries[ZombRand(1, #warCries + 1)]
            player:SayShout(cry)
        end

        -- Tick down duration
        bd.duration = bd.duration - tick
        if bd.duration <= 0.000 then
            bd.duration = 0
            berserkMode.exit(player, bd)
        end

    elseif bd.timeToRage <= hrs and (not player:isAsleep()) then
        -----------------------------------------------
        -- RAGE READY: waiting for combat trigger
        -----------------------------------------------
        if not bd.ready then
            bd.ready = true
            if getDebug() then print("[BerserkBeaver] Rage accumulated. Awaiting combat...") end
        end
        statSet(player:getStats(), CharacterStat.ANGER, 1)

        -- Heartbeat sound while waiting (every ~10 seconds)
        bd.heartbeatTimer = (bd.heartbeatTimer or 0) + tick
        if bd.heartbeatTimer >= 0.003 then
            bd.heartbeatTimer = 0
            pcall(function() player:playSound("HeartBeat") end)
        end

    elseif bd.timeToRage > hrs then
        -----------------------------------------------
        -- COOLDOWN: anger warmup last 2 hours
        -----------------------------------------------
        local closeTo = bd.timeToRage - hrs
        if closeTo <= 2 then
            local anger = math.min(1, (2 - closeTo) / 2) * 0.75
            statSet(player:getStats(), CharacterStat.ANGER, anger)
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
    if bd.ready and bd.duration <= 0 then
        if getDebug() then print("[BerserkBeaver] Combat! BERSERK triggered!") end
        berserkMode.enter(player, bd)
    end
end
Events.OnWeaponHitCharacter.Add(berserkMode.onWeaponHit)


------------------------------------------------------------
-- Debug commands
------------------------------------------------------------
function berserkMode.forceEnter()
    local p = getPlayer()
    if not p then print("[BerserkBeaver] No player."); return end
    local bd = berserkMode.setOrGetBerserkData(p)
    if bd.duration > 0 then print("[BerserkBeaver] Already berserk! "..bd.duration.."hrs left"); return end
    berserkMode.enter(p, bd)
    print("[BerserkBeaver] Forced berserk. Duration: "..bd.duration.."hrs")
end

function berserkMode.forceExit()
    local p = getPlayer()
    if not p then print("[BerserkBeaver] No player."); return end
    local bd = berserkMode.setOrGetBerserkData(p)
    if bd.duration <= 0 then print("[BerserkBeaver] Not berserk."); return end
    bd.duration = 0
    berserkMode.exit(p, bd)
    print("[BerserkBeaver] Forced exit.")
end

function berserkMode.debugStatus()
    local p = getPlayer()
    if not p then print("[BerserkBeaver] No player."); return end
    local bd = berserkMode.setOrGetBerserkData(p)
    local hrs = p:getHoursSurvived()
    print("[BerserkBeaver] === STATUS ===")
    print("  Hours survived: "..hrs)
    print("  Time to rage:   "..tostring(bd.timeToRage))
    print("  Duration left:  "..tostring(bd.duration))
    print("  Ready:          "..tostring(bd.ready or false))
    if bd.duration > 0 then print("  STATE: BERSERK ACTIVE")
    elseif bd.ready then print("  STATE: RAGE FULL - hit a zombie to trigger")
    else print("  STATE: COOLDOWN ("..(bd.timeToRage - hrs).."hrs left)") end
end

BerserkDebug = {
    enter  = berserkMode.forceEnter,
    exit   = berserkMode.forceExit,
    status = berserkMode.debugStatus,
}

return berserkMode
