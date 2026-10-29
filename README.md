# lwky only made ts bcs i needed mastery for pain 😭


# haunted-castle-farm

AFK farm for the Haunted Castle island in the Third Sea of Blox Fruits.

It gathers the island's NPCs into 3 groups spread around the island, tweens you to hover above the group with the most NPCs, auto-attacks, and uses your race V4 when it is ready. When a group is cleared it moves to the next one. If your health drops too low it flies you straight up, out of reach, until you have healed, then goes back to farming.

## Run it

Execute `haunted_castle_farm.lua` while you are on the Haunted Castle island.

- `J` turns the whole thing on or off
- `K` regroups the NPCs (use it after you move to another part of the island)
- `getgenv().HauntedGroup.stop()` stops it

## Executor functions needed

- `getgenv`
- `sethiddenproperty`
- `isnetworkowner` (optional, treated as always true if your executor does not have it)

## Options

Set them before running, for example `getgenv().HauntedGroupConfig = { Height = 12, RetreatHp = 6000 }`.

| Option | Default | What it does |
| --- | --- | --- |
| `Farm` | `true` | `false` only groups the NPCs and leaves you alone |
| `Groups` | `3` | how many groups to make |
| `PerGroup` | `12` | most NPCs in one group |
| `Range` | `1200` | how far from you (studs) NPCs are picked up |
| `Spread` | `3` | radius (studs) of the ring each group stands in |
| `Mobs` | the island's 4 mobs | list of NPC names to group, `false` for any NPC |
| `Height` | `14` | how far above the NPCs you hover (studs) |
| `RetreatHp` | `5000` | fly up and heal below this health |
| `ResumeHp` | `8000` | go back to farming at this health |
| `SafeHeight` | `120` | how far up you fly to heal (studs) |
| `TweenSpeed` | `300` | studs per second when travelling |
| `Interval` | `0.05` | seconds between hits, `false` uses the game's own timing |
| `MaxCombo` | `3` | how many hits of the M1 combo to cycle through (1 to 4) |
| `AutoAwaken` | `true` | use V4 whenever it is available |
| `ToggleKey` | `Enum.KeyCode.J` | on/off key |
| `ReclusterKey` | `Enum.KeyCode.K` | regroup key |
| `StartOn` | `true` | start running as soon as it is executed |

## Notes

- The built-in auto-attack is written for the Pain-Pain fruit.
- In testing, M1 hits landed from up to 14 studs above the NPCs and not from 16, so the default hover is 14. If no damage lands for a few seconds the script lowers the hover one stud at a time (down to 8).
- Grouping is by position, so each group sits on a spot where an NPC was already standing.
- Scripting in Roblox can get an account banned. Use it at your own risk.
