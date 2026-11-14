local _, FLT = ...

-- Stat caps for the gear planner's "Value" (UI/GearValue.lua): past its cap a stat adds nothing, so hit and defense
-- on an item count only up to the cap (with what the rest of your gear and your talents already give).
-- Classic values - WoW Forever has not published its own; change them here if it differs.
-- raid = level 60 against raid bosses (3 levels above you), leveling = below 60 against mobs 2 levels above you.
-- hit / spellHit: % to never miss (melee and ranged / spells; casters are specs whose weights have no attack power).
-- def: defense skill from gear a level 60 tank needs so a raid boss cannot crit (440 - 300 base).
FLT.GEAR_CAPS = {
  raid = { hit = 9, spellHit = 16, def = 140 },
  leveling = { hit = 6, spellHit = 5 },
}
