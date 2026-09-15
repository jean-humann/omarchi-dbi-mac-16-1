-- SDDM greeter Hyprland for MacBookPro16,1.
-- Stock /usr/share/sddm/hyprland.lua has no XKB and no cursor theme.
-- The user session is fr(mac); this greeter is a separate compositor (sddm user).
-- Hardware cursors on the AMD 5500M (USB-C / hybrid) show as a black square.

hl.env("XCURSOR_THEME", "Adwaita")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "Adwaita")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("XKB_DEFAULT_LAYOUT", "fr")
hl.env("XKB_DEFAULT_VARIANT", "mac")

hl.config({
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    force_default_wallpaper = 0,
  },

  animations = {
    enabled = false,
  },

  input = {
    kb_layout = "fr",
    kb_variant = "mac",
    kb_options = "compose:caps,shift:both_capslock_cancel",
    numlock_by_default = true,
  },

  cursor = {
    no_hardware_cursors = true,
  },
})
