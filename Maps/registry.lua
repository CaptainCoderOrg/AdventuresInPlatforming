--- Static registry of all map modules for Canvas export compatibility.
--- Dynamic requires break Canvas static analysis, so we use this registry
--- with static requires that Canvas can trace.
return {
    garden = require("Maps/garden"),
}
