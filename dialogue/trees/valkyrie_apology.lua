--- Valkyrie apology dialogue tree - Peaceful resolution path
--- Railroaded dialogue (no choices) for when player delivers adept's apology
return {
    id = "valkyrie_apology",
    start_node = "letter",
    nodes = {
        letter = {
            text = "What is this? A letter?",
            options = {
                { text = "[Show apology]", next = "reading" },
            },
        },

        reading = {
            text = "...'I wrongly accused you of stealing my shield...' ...The old man finally admits his mistake.",
            options = {
                { text = "He feels terrible about it.", next = "forgive" },
            },
        },

        forgive = {
            text = "I accept his apology. I never touched his shield. Take this shard - consider it a token of goodwill.",
            options = {
                { text = "Thank you.", next = "farewell" },
            },
        },

        farewell = {
            text = "Tell the old man to look more carefully before pointing fingers. Now go.",
            options = {
                { text = "Farewell.", next = nil },
            },
        },
    },
}
