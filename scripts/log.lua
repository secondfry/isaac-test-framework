-- PROBE lines: the console, and log.txt as `Lua Debug: PROBE ...`.
local function P(...)
	local t = {}
	for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end
	local s = table.concat(t, " ")
	print(s)
	Isaac.DebugString("PROBE " .. s)
end

return { P = P }
