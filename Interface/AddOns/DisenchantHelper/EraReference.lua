-- Small, numeric pre-squish reference, checked 2026-10-27. Not Forever measurements.
-- S1: https://www.wowhead.com/classic/guide/enchanting-leveling-1-300-wow-classic
--     corroborates material families / item-level bands, NOT all chances/amounts.
-- S2: https://warcraft.wiki.gg/wiki/Disenchanting_tables
--     supplies the explicit armor/weapon chances and conditional quantities below.
-- S3: https://github.com/ClassicWoWCommunity/forever-bugs/issues/351
--     reports divergent Forever weapon results. Never claim Era = verified Forever.
-- Numbers only; no third-party addon code, prose, images or database dumps included.
local _, ns = ...
local Ref = { weight = 4 }
ns.EraReference = Ref

-- ilvl min/max, dust ID/min/max, essence ID/min/max, shard ID,
-- armor dust/essence/shard %, weapon dust/essence/shard %.
local uncommon = {
    {5,15,10940,1,2,10938,1,2,nil,80,20,0,20,80,0}, -- S2 armor 5-15 / weapons 6-15
    {16,20,10940,2,3,10939,1,2,10978,75,20,5,20,75,5}, -- S2; S1 dust/shard bands
    {21,25,10940,4,6,10998,1,2,10978,75,15,10,15,75,10}, -- S2; S1 bands; S3 caveat
    {26,30,11083,1,2,11082,1,2,11084,75,20,5,20,75,5}, -- S1+S2; S3 caveat
    {31,35,11083,2,5,11134,1,2,11138,75,20,5,20,75,5}, -- S1+S2
    {36,40,11137,1,2,11135,1,2,11139,75,20,5,20,75,5}, -- S1+S2
    {41,45,11137,2,5,11174,1,2,11177,75,20,5,20,75,5}, -- S1+S2
    {46,50,11176,1,2,11175,1,2,11178,75,20,5,20,75,5}, -- S1+S2
    {51,55,11176,2,5,16202,1,2,14343,75,20,5,22,75,3}, -- S1+S2, weapon rates differ
    {56,60,16204,1,2,16203,1,2,14344,75,20,5,22,75,3}, -- S1+S2
    {61,65,16204,2,5,16203,2,3,14344,75,20,5,22,75,3}, -- S2
}
local rare = {
    {1,25,10978}, -- S2 Rare; S1 corroborates 20-25
    {26,30,11084}, -- S1+S2
    {31,35,11138}, -- S1+S2
    {36,40,11139}, -- S1+S2
    {41,45,11177}, -- S1+S2
    {46,50,11178}, -- S1+S2
    {51,55,14343}, -- S1+S2
    {56,65,14344,20725}, -- S2: 99.5% shard / 0.5% crystal
}
local epic = {
    {40,45,11177,2,4}, -- S2 Epic: no unsupported below-40 extrapolation
    {46,50,11178,2,4}, -- S2
    {51,55,14343,2,4}, -- S2
    {56,60,20725,1,1}, -- S2
    {61,88,20725,1,2}, -- S2; weapon 76-80 has special mean, handled below
}

function Ref.Client()
    local version = GetBuildInfo and GetBuildInfo()
    if type(version) == "string" then
        if version:match("^1%.60%.") then return "forever" end
        if version:match("^1%.15%.") then return "era" end
    end
    return nil -- no Era prior on Retail or unknown/progression clients
end

function Ref.Lookup(quality, kind, ilvl)
    local client = Ref.Client()
    if not client or (kind ~= "A" and kind ~= "W") or type(ilvl) ~= "number" then return nil end
    local mats = {}
    local function add(id, lo, hi, chance, avg)
        if id and chance > 0 then
            mats[#mats+1] = {id=id,minQty=lo,maxQty=hi,avgQty=avg or (lo+hi)/2,chance=chance/100}
        end
    end
    local rows = quality == 2 and uncommon or quality == 3 and rare or quality == 4 and epic
    if not rows then return nil end
    for _, row in ipairs(rows) do
        if ilvl >= row[1] and ilvl <= row[2] then
            if quality == 2 then
                if kind == "W" and ilvl < 6 then return nil end
                local offset = kind == "A" and 10 or 13
                add(row[3],row[4],row[5],row[offset])
                add(row[6],row[7],row[8],row[offset+1])
                add(row[9],1,1,row[offset+2])
            elseif quality == 3 then
                add(row[3],1,1,row[4] and 99.5 or 100)
                add(row[4],1,1,0.5)
            else
                local avg = kind == "W" and ilvl >= 76 and ilvl <= 80 and 1.67 or nil
                add(row[3],row[4],row[5],100,avg)
            end
            return {mats=mats,weight=Ref.weight,client=client}
        end
    end
end
