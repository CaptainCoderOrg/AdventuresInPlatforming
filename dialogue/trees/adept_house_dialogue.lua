--- Adept NPC dialogue tree - Introduction and lore
return {
    id = "adept_house_dialogue",
    start_node = "greeting",
    nodes = {
        greeting = {
            text = "Ah, a visitor. I am studying the ancient texts.",
            options = {
                { text = "What are you reading?", next = "reading" },
                { text = "Any advice for a traveler?", next = "advice" },
                { text = "I'll leave you to it.", next = nil },
            },
        },
        reading = {
            text = "Tales of the old kingdom, before the darkness came. Knowledge is power, young one.",
            options = {
                { text = "Tell me more.", next = "lore" },
                { text = "I see. Farewell.", next = nil },
            },
        },
        advice = {
            text = "Press {block} to raise your shield. Timing is everything.",
            options = {
                { text = "Thanks for the tip.", next = "greeting" },
            },
        },
        lore = {
            text = "The gnomes were once peaceful... but something changed them. Be wary in the depths.",
            options = {
                { text = "I will. Thank you.", next = nil },
            },
        },
    },
}
