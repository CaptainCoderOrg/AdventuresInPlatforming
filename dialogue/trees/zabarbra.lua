--- Zabarbra the Witch NPC dialogue tree
--- First meeting gives Minor Healing, subsequent visits offer upgrades
return {
    id = "zabarbra",
    start_node = "greeting",
    nodes = {
        greeting = {
            text = "...",
            options = {
                -- First meeting
                { text = "Hello?", next = "introduction", condition = "not_met_zabarbra" },
                -- Return visits
                { text = "I need your services.", next = "hub", condition = "met_zabarbra" },
                { text = "Leave", next = nil, condition = "met_zabarbra" },
            },
        },

        -- First meeting introduction
        introduction = {
            text = "Well, well... a visitor! I am Zabarbra, purveyor of enchantments and collector of rare curiosities. You look like you could use some help staying alive.",
            actions = { "set_flag_met_zabarbra" },
            options = {
                { text = "Can you help me?", next = "offer_healing" },
                { text = "Who are you?", next = "who_are_you" },
            },
        },

        who_are_you = {
            text = "A witch, dear. The good kind... mostly. I deal in enchantments, upgrades, the occasional hex removal. Business has been slow since the troubles began.",
            options = {
                { text = "What troubles?", next = "troubles" },
                { text = "Can you help me?", next = "offer_healing" },
            },
        },

        troubles = {
            text = "Oh, you know... the darkness creeping in, monsters everywhere, the Great Eye watching from beyond. The usual. But never mind that - I have something for you.",
            options = {
                { text = "For me?", next = "offer_healing" },
            },
        },

        offer_healing = {
            text = "Every traveler needs to know how to mend themselves. Here - I'll teach you Minor Healing. Consider it a free sample. Assign it to an ability slot, then hold the key to channel energy into health.",
            options = {
                { text = "Thank you!", next = nil },
                { text = "What's the catch?", next = "the_catch" },
            },
        },

        the_catch = {
            text = "No catch! Well... if you happen to come across any rare materials in your travels, I could enhance your equipment. For a modest fee, of course.",
            options = {
                { text = "I'll keep that in mind.", next = nil },
            },
        },

        -- Hub node: shown after first meeting and on all return visits
        hub = {
            text = "What can I do for you?",
            options = {
                { text = "Arcane Shard", next = "arcane_offer", condition = "has_item_arcane_shard", condition2 = "not_has_item_shuriken" },
                { text = "Upgrade Equipment", next = nil, actions = { "set_flag_open_upgrades" }, keep_camera = true },
                { text = "Leave", next = nil },
            },
        },

        -- Arcane shard trade
        arcane_offer = {
            text = "Oh my, is that an Arcane Shard? Those are exceedingly rare! I could transmute it into a throwing weapon - a Shuriken, enchanted with magical energy. Would you like to trade?",
            options = {
                { text = "Trade Arcane Shard for Shuriken", next = "arcane_accept" },
                { text = "Not right now.", next = "hub" },
            },
        },

        arcane_accept = {
            text = "Excellent! Let me work my magic... There! A fine enchanted Shuriken, perfect for dispatching enemies from afar.",
            actions = { "set_flag_trade_shuriken" },
            options = {
                { text = "Thanks!", next = nil },
            },
        },
    },
}
