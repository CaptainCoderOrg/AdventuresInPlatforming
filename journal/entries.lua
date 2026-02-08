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
}
