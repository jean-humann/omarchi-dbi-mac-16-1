-- Trackpad on any 16,1 (keyboard layout is separate).
hl.config({
  input = {
    -- Small bump toward macOS tracking speed. Leave accel_profile unset (adaptive).
    sensitivity = 0.25,
    touchpad = {
      natural_scroll = true,
      clickfinger_behavior = true,
      scroll_factor = 0.4,
    },
  },
})

hl.device({
  name = "apple-inc.-apple-internal-keyboard-/-trackpad-1",
  natural_scroll = true,
  scroll_factor = 0.4,
  sensitivity = 0.25,
})
