-- Serializes Lua values to compact JSON. The API has no JSON module, and
-- string.format's %q can emit escapes that are not valid JSON.
local Json = {}

local MAX_DEPTH = 8

local ESCAPES = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

-- Bytes above 0x7f are escaped too, so the output is ASCII: a game string can
-- hold bytes that are not valid UTF-8, which would break JSON consumers. Text
-- that was UTF-8 therefore comes back as one code point per byte.
local function encodeString(str)
	local escaped = str:gsub('[%c"\\\128-\255]', function(char)
		return ESCAPES[char] or string.format("\\u%04x", char:byte())
	end)
	return '"' .. escaped .. '"'
end

local function isArray(tbl)
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count == #tbl
end

local function encode(value, depth)
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			return "null"
		end
		return string.format("%.14g", value)
	elseif kind == "string" then
		return encodeString(value)
	elseif kind ~= "table" then
		return encodeString(tostring(value))
	elseif depth >= MAX_DEPTH then
		return encodeString("<max depth>")
	end

	local parts = {}
	if isArray(value) then
		for i = 1, #value do
			parts[i] = encode(value[i], depth + 1)
		end
		return "[" .. table.concat(parts, ",") .. "]"
	end

	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = tostring(key)
	end
	table.sort(keys)
	local byName = {}
	for key, field in pairs(value) do
		byName[tostring(key)] = field
	end
	for i, key in ipairs(keys) do
		parts[i] = encodeString(key) .. ":" .. encode(byName[key], depth + 1)
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

function Json.encode(value)
	return encode(value, 0)
end

return Json
