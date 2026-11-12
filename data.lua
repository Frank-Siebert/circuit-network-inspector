
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
