-- Apple ISO French. Skip this file if your legends are not Mac AZERTY.
hl.config({
  input = {
    kb_layout = "fr",
    kb_variant = "mac",
    kb_options = "compose:caps,shift:both_capslock_cancel",

    repeat_rate = 40,
    repeat_delay = 250,
    numlock_by_default = true,

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
