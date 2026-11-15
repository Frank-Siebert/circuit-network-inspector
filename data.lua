
data.raw["gui-style"].default["cni_forward_frame"] = {
    type = "frame_style",
    parent = "train_schedule_station_frame",
    graphical_set = arrow_forward(grey_arrow_tileset, arrow_disabled_index, "glow", default_dirt_color),
}

data.raw["gui-style"].default["cni_button_like_frame"] = {
    type = "frame_style",
    parent = "frame",

    graphical_set = {
        base = {position = {0, 17}, corner_size = 8},
        shadow = default_dirt
    }
}

data:extend({
  {
    type = "custom-input",
    name = "my-mod-nav-back",
    key_sequence = "ALT + LEFT",
    alternative_key_sequence = "mouse-button-4", -- Optional: matches mouse back button
    consuming = "none",
    action = "lua"
  },
  {
    type = "custom-input",
    name = "my-mod-nav-forward",
    key_sequence = "ALT + RIGHT",
    alternative_key_sequence = "mouse-button-5", -- Optional: matches mouse forward button
    consuming = "none",
    action = "lua"
  }
})
