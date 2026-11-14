# BagBuddy (WoW Forever)

See what a friend or family member is wearing and carrying, and know at a glance whether an item would be an upgrade for them. Both of you install BagBuddy.

## What it does

- **Shares bags and gear.** Whenever your bags, gear, level, talents or gold change, BagBuddy tells everyone in your group who also has it. They get your worn gear, everything in your bags (with stack counts and which items are soulbound), free bag space, gold, level and talent tree. It's saved, so you can still look after they log off.
- **The window (`/bud`).** Pick a buddy at the top.
  - *Their gear & bags*: their gear laid out like the character window (with average item level, gold and bag space in the middle), then each of their bags with every slot, empty ones included. A green arrow marks items in their own bags that would be upgrades for them (maybe they forgot to put it on). Hover for the tooltip, shift-click to link it in chat, use the search box to find something.
  - *Upgrades in my bags*: items in **your** bags that would be upgrades for them, best first. Soulbound ones are flagged, since you can't trade those.
- **Tooltips.** Hover any item anywhere (your bags, loot, quest rewards, vendors, chat links) and you'll see a line per buddy:
  - `Kid: Upgrade +12%` (or `(empty slot)`), plus `at level 25` if they're too low to wear it yet, and which item it would replace
  - `Not an upgrade (-8%)`, `About the same`, `Wearing this`
  - `has 3` when they carry some of that item (handy for quest items and materials)
  - Nothing at all for gear their class can't wear.

## How upgrades are judged

Each item's stats are scored with stat weights for the buddy's class and the talent tree they've put the most points in (before talents, the usual leveling tree: Retribution, Shadow, Enhancement, Feral). The weights come from Forever++'s Upgrade Arrows (MIT). Rings and trinkets compare against the weaker of the two, two-handers against main hand plus off hand, and Warriors, Rogues and Hunters can dual wield. Armor and weapon types follow Classic rules (mail and plate from level 40).

It's a guide, not a sim: "use" and "chance on hit" effects (most trinkets) aren't counted. If the guess at their role is wrong, set it: `/bud role Kid tank`.

## Syncing

- **In a group** it just works, wherever you both are in the world.
- **Not grouped**: add each other to your friends lists, then `/bud add Name`. BagBuddy only whispers buddies the friends list shows online.
- `/bud sync` asks for fresh bags right away.
- Addon messages can be blocked in combat inside dungeons. BagBuddy waits and sends once it's allowed.

## Commands

| Command | Does |
|---|---|
| `/bud` | Open or close the window |
| `/bud sync` | Ask everyone for fresh bags now |
| `/bud add <name>` | Sync with them when not grouped (they must be on your friends list) |
| `/bud forget <name>` | Forget someone and their bags |
| `/bud list` | Who you have bags for, and how upgrades are judged for each |
| `/bud role <name> <role>` | `auto`, `strength`, `agility`, `ranged`, `caster`, `healer`, `tank` or `bear` |
| `/bud tips` | Tooltip lines on/off |
| `/bud debug` | Extra chat output |

## Installing

Download the zip from the latest [release](https://github.com/Shashakar/BagBuddy/releases/latest), or add this repository to an addon manager that installs from GitHub (such as WowUp) to get updates automatically.

1. Unzip `BagBuddy-vX.Y.Z.zip`.
2. Put the `BagBuddy` folder in `World of Warcraft\_forever_\Interface\AddOns\` (so you have `...\AddOns\BagBuddy\BagBuddy.toc`).
3. Restart the game, or type `/reload` if it's running. Check BagBuddy is ticked in the AddOns list on the character select screen.

## Credits

Stat weights and the talent-tree reading are adapted from [Forever++](https://github.com/xIGBClutchIx/ForeverPlusPlus) (MIT, Cameron Weaver).

## Releasing

Push a tag such as `v1.2.0`, or run the Release workflow by hand with a version (`gh workflow run release.yml -f version=v1.2.0`). It zips `BagBuddy/`, stamps the version into the TOC and publishes a GitHub release.
