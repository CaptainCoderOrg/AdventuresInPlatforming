# The Crystal Ball Quest

## Overview
The Adept believes gnomos stole his crystal ball, but it's actually on his cottage roof. The player must navigate this misunderstanding with multiple possible outcomes.

## Quest Start
Trigger: Ask the Adept about the locked chest behind him.

The Adept explains he's lost the key along with his crystal ball, and blames the gnomos who live in the caves below the valley.

## Quest Paths

### Path A: Peaceful Resolution
1. Find crystal ball on the cottage roof (before fighting gnomos)
2. Return to Adept - he realizes his mistake
3. Receive Adept's Apology letter
4. Deliver apology to gnomo brothers
5. Return to Adept
6. Receive: Adept's Key + Orb of Teleportation

**Flags set:** `crystal_returned`, `apology_delivered_to_gnomos`, `received_orb`

### Path B: Guilt Path (No Ball)
1. Defeat gnomo brothers (without finding crystal ball)
2. Return to Adept - he asks about the crystal ball
3. Gnomos didn't have it - Adept realizes his mistake
4. Receive: Adept's Key only
5. Later: Find crystal ball on roof
6. Return to Adept - confirms his guilt
7. Receive: Orb of Teleportation

**Flags set:** `gnomos_wrongly_killed`, `crystal_returned`, `received_orb`

### Path C: Tragic Path
1. Defeat gnomo brothers
2. Find crystal ball on roof
3. Return to Adept with the ball
4. Adept realizes he sent you to kill innocents
5. Receive: Adept's Key + Orb of Teleportation

**Flags set:** `gnomos_wrongly_killed`, `crystal_returned`, `received_orb`

## Items Involved

| Item | Source | Purpose |
|------|--------|---------|
| Crystal Ball | Cottage roof | Quest item, becomes Orb |
| Adept's Apology | Adept (Path A) | Deliver to gnomos |
| Adept's Key | Adept (all paths) | Opens cottage chest |
| Orb of Teleportation | Adept (all paths) | Fast travel reward |

## Dialogue Flags

| Flag | Set When |
|------|----------|
| `met_adept` | Complete introduction |
| `asked_about_chest` | Ask about chest/key |
| `crystal_returned` | Give ball to Adept |
| `gnomos_wrongly_killed` | Kill gnomos, ball not with them |
| `apology_delivered_to_gnomos` | Complete gnomo dialogue (separate tree) |
| `received_orb` | Receive Orb of Teleportation |

## Boss Check
The quest checks `defeated_boss_gnomo_brothers` to determine if gnomos are alive or dead when the player returns to the Adept.
