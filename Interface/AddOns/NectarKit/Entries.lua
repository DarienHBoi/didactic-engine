-- The owner's own addons. Edit this table to add or remove entries; nothing else needs to change.
--   addon  = folder name (used for the loaded check and the .toc IconTexture lookup)
--   title  = text shown on hover
--   key    = SlashCmdList key the launcher calls with ""
--   slash  = the typed command (hover hint only)
--   icon   = built-in texture, used when the addon's .toc has no IconTexture
--   button = global name of the addon's own minimap button frame, if it has one (hidden by /nk buttons)
-- Left out on purpose: !ChatClickWatch (no slash command), TaxiSpike (throwaway).
local _, NK = ...

NK.Entries = {
    { addon = "Salesman",           title = "Salesman",            key = "SALESMAN",           slash = "/salesman",
      icon = "Interface\\Icons\\INV_Misc_Coin_01",         button = "SalesmanMinimapButton" },
    { addon = "Pricewatch",         title = "Pricewatch",          key = "PRICEWATCH",         slash = "/pricewatch",
      icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { addon = "Taxi",               title = "Taxi",                key = "TAXI",               slash = "/taxi",
      icon = "Interface\\Icons\\INV_Misc_Map_01",          button = "TaxiMinimapButton" },
    { addon = "MissingBuffWarning", title = "Missing Buff Warning", key = "MISSINGBUFFWARNING", slash = "/mbw",
      icon = "Interface\\Icons\\Spell_Holy_InnerFire",     button = "MissingBuffWarningMinimapButton" },
    { addon = "AddonPresets",       title = "Addon Presets",       key = "ADDONPRESETS",       slash = "/presets",
      icon = "Interface\\Icons\\INV_Misc_Book_09" },
    { addon = "LinkBisect",         title = "LinkBisect",          key = "LINKBISECT",         slash = "/lb",
      icon = "Interface\\Icons\\INV_Misc_Spyglass_02" },
    { addon = "!ErrorLog",          title = "Error log",           key = "ERRORLOG",           slash = "/errlog",
      icon = "Interface\\Icons\\INV_Misc_Bug_02" },
    { addon = "AscendXP_Tweaks",    title = "AscendXP Tweaks",     key = "AXPT",               slash = "/axpt",
      icon = "Interface\\Icons\\INV_Misc_Gear_01" },
    { addon = "Reaper",             title = "Reaper",              key = "REAPER",             slash = "/reaper",
      icon = "Interface\\Icons\\Spell_Shadow_DeathPact" },
    { addon = "NectarSellers",      title = "Nectar Sellers",      key = "NECTARSELLERS",      slash = "/sellers",
      icon = "Interface\\Icons\\INV_Misc_Coin_01" },
    { addon = "RingTheBell",        title = "Ring the Bell",       key = "RINGTHEBELL",        slash = "/bell",
      icon = "Interface\\AddOns\\RingTheBell\\Media\\Bell", button = "RingTheBellPip" },
}
