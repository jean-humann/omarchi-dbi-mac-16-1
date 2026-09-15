-- Example / recipe LG. `apply display` generates the live file (lid-only omits the
-- external block). Do NOT disable eDP-1 or eDP-2 by connector name. Names flip with USB-C.
-- Match the lid by description. Disable the phantom eDP with mbp16-1-hypr-outputs.

local omarchy_gdk_scale = 2
local omarchy_monitor_scale = "auto"

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

hl.monitor({
  output = "desc:Apple Computer Inc Color LCD",
  mode = "3072x1920@60",
  position = "0x0",
  scale = 2,
})

hl.monitor({
  output = "desc:LG Electronics LG HDR 4K",
  mode = "3840x2160@60",
  position = "auto-center-up",
  scale = 1.5,
})
