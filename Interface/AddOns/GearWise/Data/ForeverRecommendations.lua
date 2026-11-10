local _,ns=...
-- Editorial ordering, not measured DPS, average attributes, proc rate or upgrade size.
-- Rules are opt-in by spell ID, role and class. Unreviewed effects get no priority.
-- Tanks, ranged and shapeshift builds need their own evaluation rather than inheriting
-- a melee-damage recommendation. Availability and item restrictions still apply.
ns.procRecommendations={
 [20034]={
  physical={classes={PALADIN=true,WARRIOR=true,ROGUE=true,SHAMAN=true},
   priority=1,label=ns.L("Sehr passend"),reason=ns.L("Zeitweiser Stärke-Bonus für Nahkampfangriffe.")},
 },
}

ns.Locale.Track(ns.procRecommendations)
