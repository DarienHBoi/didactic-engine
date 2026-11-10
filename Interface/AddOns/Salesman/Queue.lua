local _, S = ...
S.Queue = {}

-- One ad per ticked enchant, in the given recipe order. buildFn(recipe) returns text or nil, reason.
function S.Queue.build(recipes, picked, buildFn)
    local texts, skipped = {}, {}
    if type(recipes) ~= "table" or type(picked) ~= "table" then return texts, skipped end
    for _, r in ipairs(recipes) do
        if picked[r.key] then
            local text, err = buildFn(r)
            if text then
                texts[#texts + 1] = text
            else
                skipped[#skipped + 1] = { name = r.name, reason = err or "unknown" }
            end
        end
    end
    return texts, skipped
end

function S.Queue.new(texts)
    if type(texts) ~= "table" or #texts == 0 then return nil end
    return { items = texts, i = 1 }
end

function S.Queue.current(q)
    return q and q.items[q.i] or nil
end

-- Moves to the next ad; nil when the queue is finished.
function S.Queue.advance(q)
    if not q then return nil end
    q.i = q.i + 1
    return q.items[q.i]
end

function S.Queue.position(q) return q and q.i or 0 end
function S.Queue.total(q) return q and #q.items or 0 end
