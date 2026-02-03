--- Static registry of all tilesets for Canvas export compatibility.
--- Dynamic requires break Canvas static analysis, so we use this registry
--- with static requires that Canvas can trace.
return {
    tileset_dungeon = require("Tilemaps/tileset_dungeon"),
    spawns = require("Tilemaps/spawns"),
    enemy_spawns = require("Tilemaps/enemy_spawns"),
    ["test-level"] = require("Tilemaps/test-level"),
    decorations = require("Tilemaps/decorations"),
    tileset_garden = require("Tilemaps/tileset_garden"),
    NPCS = require("Tilemaps/NPCS"),
    tileset_witch_shop = require("Tilemaps/tileset_witch_shop"),
    shop = require("Tilemaps/shop"),
    outside_tileset = require("Tilemaps/outside_tileset"),
    garden = require("Tilemaps/garden"),
    dungeon = require("Tilemaps/dungeon"),
    unique_items = require("Tilemaps/unique_items"),
    alchemy_room_tileset = require("Tilemaps/alchemy_room_tileset"),
    tileset_library = require("Tilemaps/tileset_library"),
    adepts_house = require("Tilemaps/adepts_house"),
    caves_tileset = require("Tilemaps/caves_tileset"),
}
