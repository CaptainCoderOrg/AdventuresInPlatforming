return {
	-- Lerp speeds
	default_lerp = 0.05,
	fall_lerp_min = 0.08,  -- Slower initial fall tracking
	fall_lerp_max = 0.25,  -- Moderate speed at terminal velocity
	fall_lerp_ramp_duration = 0.5,  -- Gradual ramp

	-- Look-ahead
	look_ahead_distance_x = 3,
	look_ahead_speed_x = 0.05,

	-- Manual look controls
	manual_look_up_framing = 0.333,
	manual_look_down_framing = 0.833,
	manual_look_speed = 0.1,
	manual_look_horizontal_distance = 4,

	-- Framing ratios (from top of viewport)
	framing_falling = 0.10,         -- Player at 10% when falling fast
	framing_default = 0.667,        -- Player at 2/3 (show more below)
	framing_climbing_down = 0.333,  -- Player at 1/3 (show more above)
	framing_climbing_idle = 0.5,    -- Centered on ladder

	-- Ground detection
	raycast_distance = 5,          -- Tiles to search below player
	terminal_velocity = 20,         -- Pixels/frame threshold for "falling fast"

	-- Wall slide transition (from falling)
	wall_slide_transition_duration = 2.0,  -- Seconds to use slow lerp after entering wall slide from fall
	wall_slide_transition_lerp = 0.02,     -- Lerp speed during transition (slower than default 0.05)

	-- Camera bounds transition
	bounds_transition_duration = 0.8,  -- Seconds to use slow lerp when entering new bounds area
	bounds_transition_lerp = 0.03,     -- Lerp speed during bounds transition
	bounds_settle_threshold = 0.1,     -- Continue slow lerp until within this many tiles of target

	-- Misc
	ladder_exit_offset = 0.8,       -- Tiles above ladder top for exit
	epsilon = 0.01,                 -- Snap threshold to prevent drift
}
