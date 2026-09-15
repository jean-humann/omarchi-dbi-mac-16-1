-- SDDM greeter Hyprland for MacBookPro16,1 (keyboard layout left to the user).
-- Hardware cursors on the AMD 5500M (USB-C / hybrid) show as a black square.
-- Do not edit /usr/share/sddm/hyprland.lua (Omarchy overwrites it).

hl.env("XCURSOR_THEME", "Adwaita")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "Adwaita")
hl.env("HYPRCURSOR_SIZE", "24")

hl.config({
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    force_default_wallpaper = 0,
  },

  animations = {
    enabled = false,
  },

  cursor = {
    no_hardware_cursors = true,
  },
})
