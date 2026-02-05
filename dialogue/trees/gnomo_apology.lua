--- Gnomo apology dialogue tree - Peaceful resolution path
--- Railroaded dialogue (no choices) for when player delivers adept's apology
return {
    id = "gnomo_apology",
    start_node = "letter",
    nodes = {
        letter = {
            text = "Hmm? What's this? A letter from the old man?",
            options = {
                { text = "[Give apology]", next = "reading" },
            },
        },

        reading = {
            text = "...'I wrongly accused you...' ...He finally admits it!",
            options = {
                { text = "He feels terrible about it.", next = "acceptance" },
            },
        },

        acceptance = {
            text = "We accept his apology... Here, take this axe as thanks.",
            options = {
                { text = "What about the crystal ball?", next = "gift" },
            },
        },

        gift = {
            text = "Keep it - consider it a gift. Now go, tell him we hold no grudge.",
            options = {
                { text = "Thank you.", next = nil },
            },
        },
    },
}
