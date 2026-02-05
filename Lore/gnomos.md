# The Gnomos

## Overview
A group of colorful gnome-like creatures who live in underground tunnels beneath the garden. They emerge through holes in the boss arena to defend their territory.

## The Gnomo Boss Encounter
The player encounters the gnomos in their lair after the Adept accuses them of stealing his crystal ball. Four gnomos (green, red, blue, orange) coordinate their attacks in a multi-phase boss fight.

## Peaceful Resolution Path (Not Yet Implemented)

### Prerequisites
- Player must have the `adept_apology` item (obtained by finding the crystal ball on the Adept's roof and getting his written apology)

### Intended Sequence
When the player enters the boss room with the apology letter:

1. **Cinematic intro** (same as combat path)
   - Player walks to position
   - Door closes behind them
   - Player shows "?" reaction
   - Gnomos show "!!" reaction

2. **Green gnomo descends**
   - The green gnomo jumps down from his platform to speak with the player

3. **Dialogue exchange**
   ```
   Gnomo: "Hmm? What's this? A letter from the old man?"
   Player: [Give apology]

   Gnomo: "...'I wrongly accused you of theft. The crystal ball was on my
          roof all along. Please accept my sincerest apology.' ...He finally
          admits it!"
   Player: "He feels terrible about it."

   Gnomo: "We accept his apology. We're glad he'll stop slandering our good
          name! Here, take this axe as thanks for being a messenger of peace."
   Player: "What about the crystal ball?"

   Gnomo: "We have no need for it. Keep it - consider it a gift. Now go,
          tell the old man we hold no grudge."
   Player: "Thank you."
   ```

4. **Post-dialogue sequence**
   - The `adept_apology` item is consumed
   - Flag `apology_delivered_to_gnomos` is set
   - Green gnomo tosses his throwing axe into the air
   - The axe flies up and lands at a collection point
   - Green gnomo runs off-screen and fades out
   - Other gnomos jump back into their holes and fade out

5. **Rewards**
   - XP burst (100 XP) spawns around player
   - Boss is marked as defeated
   - Player regains control to collect the throwing axe

6. **Exit**
   - After player collects the throwing axe, the boss door opens
   - Player can leave the arena

### Key Design Points
- Player should be locked during steps 1-4 (cinematic/dialogue)
- Player should be FREE during step 5-6 to collect the axe and leave
- The sequence should NOT require the combat coordinator to be active
- The throwing axe reward is unique to the peaceful path

### Dialogue Flags Set
- `apology_delivered_to_gnomos` - Peaceful resolution completed

### Items Involved
- `adept_apology` - Consumed when dialogue completes
- `throwing_axe` - Rewarded as thanks for delivering the apology

## Combat Resolution Path
If the player fights and defeats the gnomos:
- Standard boss victory sequence plays
- Boss door opens
- If the player later finds the crystal ball on the Adept's roof, they learn the gnomos were innocent (tragic path)
