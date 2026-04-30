# Big Bad Beaver's Berserk — Unofficial B42 Compatibility Patch

> **⚠️ DISCLAIMER: This is an UNOFFICIAL compatibility patch. The original mod was created by [Chuckleberry Finn](https://steamcommunity.com/sharedfiles/filedetails/?id=2954181035). All credit for the original concept, design, and code goes to them. This patch will be removed immediately upon request from the original author.**

> **🤖 AI-GENERATED: The Build 42 adaptation code in this repository was generated with the assistance of AI (Claude), directed and tested by a human. The original game logic and mod concept remain the work of Chuckleberry Finn.**

## What is this?

This is a **Build 42.17+ compatibility patch** for the [Big Bad Beaver's Berserk](https://steamcommunity.com/sharedfiles/filedetails/?id=2954181035) mod for Project Zomboid. The original mod only supports Build 41 and does not function on Build 42 due to breaking API changes.

This patch adapts the mod to work with the new Build 42 API while adding several gameplay enhancements.

## Requirements

- **Project Zomboid Build 42.17 or newer**
- The original [Big Bad Beaver's Berserk](https://steamcommunity.com/sharedfiles/filedetails/?id=2954181035) mod is **NOT required** for this patch to function, as the B42 code is a standalone adaptation. However, please subscribe to the original mod to support the creator.

## Installation

1. Download or clone this repository
2. Copy the `bigBadBeaversBerserk` folder into your Project Zomboid mods directory:
   - **Linux**: `~/Zomboid/mods/`
   - **Windows**: `%USERPROFILE%\Zomboid\mods\`
3. Enable the mod in-game

## What Changed for B42?

### API Adaptation
- **Stats API**: Build 42 removed all individual stat getters/setters (`setAnger()`, `getThirst()`, etc.). Replaced with the new generic `Stats:get(CharacterStat)` / `Stats:set(CharacterStat, float)` API.

### Gameplay Enhancements

#### Combat-Triggered Berserk
Rage now accumulates over time but is **held** until the player actually strikes a zombie. This makes berserk feel more organic — you snap into rage during combat, not randomly while crafting.

#### Expanded Stat Suppression (B42)
In addition to the original 7 stats, the B42 version now also suppresses during berserk:
- **Pain** — You don't feel injuries during rage
- **Discomfort** — No physical complaints
- **Unhappiness** — Pure rage replaces sadness
- **Boredom** — Too busy rampaging
- **Wetness** — Rain? What rain?
- **Temperature** — Body temperature held stable (maintained at entry value)

All suppressed stats are accumulated and hit you at once when berserk ends (recoil).

#### 💪 Muscle Strain Immunity (B42)
Build 42's new muscle strain system is negated during berserk — unlimited combat without fatigue. A burst of muscle strain hits after berserk ends.

#### 🩸 Visual Feedback — Halo Text
Random rage text ("RAGE!", "BLOOD!", "KILL!", etc.) appears above the character's head periodically during berserk.

#### 🔊 Sound Effects
- **Heartbeat** plays while rage is fully accumulated and waiting for combat trigger
- **War cries** — Character randomly shouts battle cries during berserk

#### ⚡ Knockdown Resistance
Character **cannot be knocked down** by zombies during berserk — auto-recovery from any stagger.

#### 🩹 Wound Awareness
After berserk ends, the mod scans for injuries sustained during the rage and reports them via halo text (e.g., "You took 2 scratch(es), 1 bite(s) during your rage..."). The character only "notices" their wounds after calming down.

#### Longer Cooldown
Default interval between berserks increased from 2–3 hours to **12–18 hours** (adjustable via Sandbox Settings).

### Sandbox Settings
| Setting | Default | Description |
|---------|---------|-------------|
| `message` | BERSERK | Text the character shouts on activation |
| `recoilMultiplier` | 1.0 | Multiplier for accrued negative stats |
| `minInterval` | 12 hrs | Minimum hours between berserks |
| `maxInterval` | 18 hrs | Maximum hours between berserks |
| `durationMin` | 3 hrs | Minimum berserk duration |
| `durationMax` | 6 hrs | Maximum berserk duration |

## How It Works

1. **Cooldown** (12–18 hrs) — Anger gradually rises in the last 2 hours
2. **Rage Ready** — Anger maxed, heartbeat plays, waiting for combat
3. **Combat Trigger** — Player hits a zombie → **BERSERK activates**
4. **Berserk Active** (3–6 hrs) — Combat skills maxed, all negative stats suppressed, knockdown immune, periodic rage text and war cries
5. **Berserk Ends** — Skills restored, all suppressed stats hit at once (recoil), muscle strain burst, wound report displayed
6. Cycle repeats

## Debug Commands

Launch the game with `-debug` flag. Open Lua console with `~` key and type:

```lua
BerserkDebug.enter()   -- Force trigger berserk
BerserkDebug.exit()    -- Force end berserk
BerserkDebug.status()  -- Print current state/timers
```

## Credits

- **Original Mod**: [Big Bad Beaver's Berserk](https://steamcommunity.com/sharedfiles/filedetails/?id=2954181035) by **Chuckleberry Finn**
- **B42 Adaptation**: This repository

## Takedown / Contact

If you are the original author (**Chuckleberry Finn**) and want this repository removed, please open an [issue](https://github.com/myythedermit/bigBadBeaversBerserk-B42-Patch/issues) on this repo.

The repository will be taken down **immediately**, no questions asked.

## Legal Notice

This is a fan-made compatibility patch created for personal and community use. The original mod and its concept are the intellectual property of Chuckleberry Finn. This patch is provided as-is with no warranty. **If the original author requests removal, this repository will be taken down immediately.**

This patch is NOT authorized for reuploading to the Steam Workshop.
