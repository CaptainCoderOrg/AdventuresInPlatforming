--- Journal entry registry
--- Static definitions for all journal entries with hierarchical nesting via parent field
return {
    -- Top-level: Awakening
    awakening = {
        title = "Awakening",
        description = "I woke up in a small cottage with no memory of who I am. I need to figure out who I am and why I have no memories.",
        parent = nil, sort_order = 1,
    },
    spoke_with_adept = {
        title = "Spoke with Adept",
        description = "The Adept says he found me collapsed near the cliffside and brought me to his cottage to rest.",
        parent = "awakening", sort_order = 1,
    },

    -- Top-level: Arcane Shard
    arcane_shard_quest = {
        title = "Bring Arcane Shard to Zabarbra",
        description = "I found a crystallized fragment of magical energy. Zabarbra might be able to do something with it.",
        parent = nil, sort_order = 3,
    },

    -- Top-level: The Adept
    the_adept = {
        title = "The Adept",
        description = "An old scholar who found me near the cliffside. He seems to know more than he lets on.",
        parent = nil, sort_order = 2,
    },

    -- Level 2: Find Crystal Ball (child of The Adept)
    find_crystal_ball = {
        title = "Find Crystal Ball",
        description = "The Adept lost his crystal ball and believes the gnomos stole it. He asked me to retrieve it from their caves below the valley.",
        parent = "the_adept", sort_order = 1,
    },

    -- Level 3: Crystal ball quest sub-entries (children of Find Crystal Ball)
    killed_gnomos = {
        title = "Killed Gnomos",
        description = "I fought the 4 gnomo brothers. I didn't find the crystal ball on them. I should report back to the Adept.",
        parent = "find_crystal_ball", sort_order = 1,
    },
    crystal_found_roof = {
        title = "Crystal Found on Roof",
        description = "The crystal ball was on the Adept's roof the whole time. The gnomos were innocent.",
        parent = "find_crystal_ball", sort_order = 2,
    },
    apology_letter = {
        title = "Apology Letter",
        description = "The Adept wrote a letter of apology for the gnomo brothers. He asked me to deliver it along with the crystal ball as a peace offering.",
        parent = "find_crystal_ball", sort_order = 3,
    },
    apology_delivered = {
        title = "Apology Accepted",
        description = "The gnomo brothers accepted the Adept's apology and forgave him.",
        parent = "find_crystal_ball", sort_order = 4,
    },
    received_orb = {
        title = "Received Orb",
        description = "The Adept imbued the crystal ball with magic and gave it to me as the Orb of Teleportation. I can use it to travel to any campfire I've visited.",
        parent = "find_crystal_ball", sort_order = 5,
    },

    -- Level 2: Adept's Longsword (child of The Adept)
    adepts_longsword = {
        title = "Adept's Longsword",
        description = "I found a longsword in the Adept's chest. I should ask him about it.",
        parent = "the_adept", sort_order = 5,
    },

    -- Level 2: Find Adept's Shield (child of The Adept)
    find_adepts_shield = {
        title = "The Adept's Shield",
        description = "The Adept believes the Valkyrie in the Crypt stole his shield.",
        parent = "the_adept", sort_order = 6,
    },

    -- Level 3: Shield quest sub-entries (children of Find Adept's Shield)
    shield_found_attic = {
        title = "Shield Found in Attic",
        description = "The Adept's shield was in the attic all along. The Valkyrie was innocent.",
        parent = "find_adepts_shield", sort_order = 1,
    },
    valkyrie_apology_letter = {
        title = "Apology to the Valkyrie",
        description = "The Adept wrote a letter of apology for the Valkyrie.",
        parent = "find_adepts_shield", sort_order = 2,
    },
    valkyrie_apology_delivered = {
        title = "Valkyrie Forgives",
        description = "The Valkyrie accepted the Adept's apology and forgave him.",
        parent = "find_adepts_shield", sort_order = 3,
    },
    killed_valkyrie = {
        title = "Valkyrie Defeated",
        description = "The Valkyrie of the Crypts has been slain.",
        parent = "find_adepts_shield", sort_order = 4,
    },

    -- Level 2: Purgatory Reveal (child of The Adept)
    purgatory_revealed = {
        title = "The Truth",
        description = "The Adept revealed the truth about this realm.",
        parent = "the_adept", sort_order = 7,
    },
}
