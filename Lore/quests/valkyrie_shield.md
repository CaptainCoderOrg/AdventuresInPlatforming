# The Adept's Shield Quest

## Overview
After the crystal ball quest resolves, the Adept recalls his old shield from his warrior days and blames the Valkyrie in the Crypt for stealing it. This mirrors the gnomo quest structure with peaceful and tragic branching paths.

## Prerequisites
- Player has obtained the longsword (from the chest behind the Adept)
- Player has received the Orb of Teleportation (`received_orb` flag)

## Trigger
Greeting option "You look concerned." becomes available when:
- `has_item_longsword` (player opened the chest)
- `not_asked_about_shield` (hasn't started the quest yet)
- `received_orb` (crystal ball quest is complete)

## Items
| Item ID | Name | Type | Source |
|---------|------|------|--------|
| `adepts_shield` | Adept's Shield | secondary | Attic chest (`adepts_shield_chest`) |
| `valkyrie_apology` | Adept's Apology | no_equip | Given by Adept (peaceful path) |

## Paths

### Path A: Peaceful Resolution
1. Talk to Adept -> "You look concerned" -> learns about shield
2. Find `adepts_shield` in attic chest
3. Return to Adept -> "I found your shield" -> Adept realizes mistake
4. Receive `valkyrie_apology` letter
5. Enter valkyrie boss room with letter -> cinematic plays
6. Valkyrie reads letter, forgives, gives arcane shard
7. Return to Adept -> "I delivered your apology" -> quest resolved

### Path B: Tragic (Kill First)
1. Talk to Adept -> learns about shield
2. Kill Valkyrie in combat
3. Return to Adept -> "About the Valkyrie..." -> realizes shield wasn't his
4. Quest resolved with guilt

### Path C: Mixed (Kill + Find Shield)
1. Talk to Adept -> learns about shield
2. Kill Valkyrie in combat
3. Find `adepts_shield` in attic
4. Return to Adept -> "I found your shield" -> double guilt (killed + found)
5. Quest resolved

## Dialogue Flags
| Flag | Set When |
|------|----------|
| `asked_about_shield` | Player asks "You look concerned" |
| `valkyrie_quest_resolved` | Any resolution reported to Adept |
| `valkyrie_apology_delivered` | Apology cinematic completed |
| `purgatory_revealed` | Adept reveals the truth about purgatory |
| `show_credits` | Triggers credits screen after dialogue closes |

## Journal Entries
| Entry ID | Parent | Trigger |
|----------|--------|---------|
| `find_adepts_shield` | `the_adept` | Quest start |
| `shield_found_attic` | `find_adepts_shield` | Finding shield in attic |
| `valkyrie_apology_letter` | `find_adepts_shield` | Receiving apology letter |
| `valkyrie_apology_delivered` | `find_adepts_shield` | Cinematic completion |
| `killed_valkyrie` | `find_adepts_shield` | Victory sequence |
| `purgatory_revealed` | `the_adept` | Purgatory dialogue |

## Post-Quest: Purgatory Reveal
After `valkyrie_quest_resolved` is set, the greeting option "Tell me about myself." becomes available. This triggers a multi-node dialogue chain revealing:
- The player is dead
- This realm is purgatory
- The Evil Eye prevents memories from returning
- Defeating the Evil Eye is "an adventure for the future"

Sets `show_credits` flag which triggers the credits screen via the Adept NPC's `on_dialogue_close` callback.
