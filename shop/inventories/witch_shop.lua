--- Witch shop inventory
--- Items sold by the witch NPC
return {
    id = "witch_shop",
    name = "Witch's Wares",
    greeting = "Welcome, traveler. Browse my wares...",
    items = {
        {
            type = "stackable",
            item_id = "dungeon_key",
            name = "Dungeon Key",
            description = "Opens locked doors in the dungeon.",
            price = 50,
            amount = 1,
        },
        {
            type = "stat",
            stat_key = "max_health",
            stat_value = 1,
            name = "Health Upgrade",
            description = "Permanently increase your maximum health by 1.",
            price = 200,
        },
        {
            type = "stat",
            stat_key = "max_stamina",
            stat_value = 10,
            name = "Stamina Upgrade",
            description = "Permanently increase your maximum stamina by 10.",
            price = 150,
        },
    },
}
