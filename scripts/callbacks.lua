-- Fired and not-fired counts of engine callbacks, per callback id and argument (the item id for MC_USE_ITEM).
-- main.lua registers each counter once and never removes it (vanilla RemoveCallback skips the next callback); a test's teardown clears the counts.
HARNESS.callbacks = HARNESS.callbacks or {}

local function keyOf(id, arg) return id .. ":" .. tostring(arg) end

-- The handler counting callback `id`, keyed by its first argument.
local function count(id)
	return function(_, arg)
		local C, k = HARNESS.callbacks, keyOf(id, arg)
		C[k] = (C[k] or 0) + 1
	end
end

-- The counts now, for since() to compare against.
local function mark()
	local m = {}
	for k, n in pairs(HARNESS.callbacks) do m[k] = n end
	return m
end

-- How often callback `id` fired with `arg` after `m`.
local function since(m, id, arg)
	local k = keyOf(id, arg)
	return (HARNESS.callbacks[k] or 0) - (m[k] or 0)
end

local function reset() HARNESS.callbacks = {} end

return { count = count, mark = mark, since = since, reset = reset }
