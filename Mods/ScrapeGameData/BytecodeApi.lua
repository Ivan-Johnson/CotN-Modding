-- Recovers a module's public API from its compiled LuaJIT bytecode. The game
-- ships its scripts with debug info, so the bytecode still has the names of
-- locals, upvalues and parameters, even though the source is gone.
--
-- Only the module's top-level code is followed, and only until it returns:
-- the table it returns is the API, and each `Module.name = value` assignment
-- to it is one member. Names starting with "_" and everything that is not
-- reachable from the returned table are private and left out.
--
-- Pure Lua with no game dependencies, so `Mods/test-bytecode-api.lua` can run
-- it under plain LuaJIT.
local BytecodeApi = {}

local byte = string.byte
local sub = string.sub
local floor = math.floor

local FLAG_BIG_ENDIAN = 1
local FLAG_STRIPPED = 2
local FLAG_FR2 = 8
local PROTO_VARARG = 2

-- Variable names below this byte are the compiler's own, e.g. "(for index)".
local VARNAME_MAX = 7

-- Opcode numbers of LuaJIT 2.1 (BCDEF order in lj_bc.h).
local OP_MOV = 18
local OP_KSTR = 39
local OP_KSHORT = 41
local OP_KNUM = 42
local OP_KPRI = 43
local OP_KNIL = 44
local OP_UGET = 45
local OP_FNEW = 51
local OP_TNEW = 52
local OP_TDUP = 53
local OP_GGET = 54
local OP_GSET = 55
local OP_TGETV = 56
local OP_TGETS = 57
local OP_TSETV = 60
local OP_TSETS = 61
local OP_CALLM = 65
local OP_CALLT = 68
local OP_RET1 = 76

local OP_CALL = 66

-- Opcodes that never write their A operand. Everything else is assumed to, so
-- that a stale guess about a register is dropped rather than trusted.
local function writesRegisterA(op)
	if op <= 11 or (op >= 14 and op <= 17) then
		return false
	end
	if op >= 46 and op <= 50 then
		return false
	end
	if op == OP_GSET or (op >= 60 and op <= 64) then
		return false
	end
	if op >= 72 and op <= 87 then
		return false
	end
	return true
end

local function readByte(reader)
	local value = byte(reader.bytes, reader.pos)
	if not value then
		error("unexpected end of bytecode")
	end
	reader.pos = reader.pos + 1
	return value
end

local function readUleb(reader)
	local value = 0
	local scale = 1
	local more = true
	while more do
		local b = readByte(reader)
		value = value + (b % 128) * scale
		scale = scale * 128
		more = b >= 128
	end
	return value
end

-- A number constant is either an integer or the two halves of a double. The
-- low bit of the first byte says which.
local function readUleb33(reader)
	local first = readByte(reader)
	local isDouble = first % 2 == 1
	local value = floor(first / 2) % 64
	if first >= 128 then
		local scale = 64
		local more = true
		while more do
			local b = readByte(reader)
			value = value + (b % 128) * scale
			scale = scale * 128
			more = b >= 128
		end
	end
	return value, isDouble
end

local function readString(reader, length)
	local text = sub(reader.bytes, reader.pos, reader.pos + length - 1)
	if #text ~= length then
		error("unexpected end of bytecode")
	end
	reader.pos = reader.pos + length
	return text
end

local function readCString(reader)
	local stop = string.find(reader.bytes, "\0", reader.pos, true)
	if not stop then
		error("unterminated string")
	end
	local text = sub(reader.bytes, reader.pos, stop - 1)
	reader.pos = stop + 1
	return text
end

local function asInt32(value)
	if value >= 2 ^ 31 then
		return value - 2 ^ 32
	end
	return value
end

local function asDouble(low, high)
	local negative = high >= 2 ^ 31
	local exponent = floor(high / 2 ^ 20) % 2048
	local mantissa = (high % 2 ^ 20) * 2 ^ 32 + low
	local result
	if exponent == 0 then
		result = mantissa * 2 ^ -1074
	elseif exponent == 2047 then
		result = mantissa == 0 and math.huge or 0 / 0
	else
		result = (1 + mantissa / 2 ^ 52) * 2 ^ (exponent - 1023)
	end
	if negative then
		return -result
	end
	return result
end

-- One value inside a constant table: nil, false, true, an integer, a double
-- or a string.
local function readTableConstant(reader)
	local kind = readUleb(reader)
	if kind == 0 then
		return nil
	elseif kind == 1 then
		return false
	elseif kind == 2 then
		return true
	elseif kind == 3 then
		return asInt32(readUleb(reader))
	elseif kind == 4 then
		local low = readUleb(reader)
		local high = readUleb(reader)
		return asDouble(low, high)
	end
	return readString(reader, kind - 5)
end

-- The constant table `{ A = 1, B = 2 }` the compiler builds ahead of time.
local function readTableTemplate(reader)
	local arraySize = readUleb(reader)
	local hashSize = readUleb(reader)
	local members = {}
	for index = 0, arraySize - 1 do
		local value = readTableConstant(reader)
		if value ~= nil then
			members[tostring(index)] = value
		end
	end
	for _ = 1, hashSize do
		local key = readTableConstant(reader)
		local value = readTableConstant(reader)
		if key ~= nil then
			members[tostring(key)] = value
		end
	end
	return members
end

local function readGcConstants(reader, count)
	local constants = {}
	for index = 1, count do
		local kind = readUleb(reader)
		if kind == 0 then
			-- A child prototype is written ahead of its parent.
			local protos = reader.protos
			constants[index] = { child = protos[#protos] }
			protos[#protos] = nil
		elseif kind == 1 then
			constants[index] = { template = readTableTemplate(reader) }
		elseif kind == 2 or kind == 3 then
			readUleb(reader)
			readUleb(reader)
			constants[index] = {}
		elseif kind == 4 then
			for _ = 1, 4 do
				readUleb(reader)
			end
			constants[index] = {}
		else
			constants[index] = { text = readString(reader, kind - 5) }
		end
	end
	return constants
end

local function readNumberConstants(reader, count)
	local constants = {}
	for index = 1, count do
		local value, isDouble = readUleb33(reader)
		if isDouble then
			value = asDouble(value, readUleb(reader))
		else
			value = asInt32(value)
		end
		constants[index] = value
	end
	return constants
end

local function readDebugInfo(reader, proto, stop)
	local lineWidth = 4
	if proto.lineCount < 256 then
		lineWidth = 1
	elseif proto.lineCount < 65536 then
		lineWidth = 2
	end
	reader.pos = reader.pos + proto.size * lineWidth

	proto.upvalueNames = {}
	for index = 1, proto.upvalueCount do
		proto.upvalueNames[index] = readCString(reader)
	end

	proto.variables = {}
	local startPc = 0
	while reader.pos < stop do
		local first = byte(reader.bytes, reader.pos)
		if first == 0 then
			break
		end
		local name
		if first < VARNAME_MAX then
			name = "(internal)"
			reader.pos = reader.pos + 1
		else
			name = readCString(reader)
		end
		startPc = startPc + readUleb(reader)
		local endPc = startPc + readUleb(reader)
		proto.variables[#proto.variables + 1] = { name = name, startPc = startPc, endPc = endPc }
	end
end

local function readProto(reader, stripped)
	local length = readUleb(reader)
	if length == 0 then
		return false
	end
	local stop = reader.pos + length

	local proto = {}
	proto.flags = readByte(reader)
	proto.paramCount = readByte(reader)
	readByte(reader)
	proto.upvalueCount = readByte(reader)
	local gcCount = readUleb(reader)
	local numberCount = readUleb(reader)
	proto.size = readUleb(reader)

	local debugSize = 0
	proto.firstLine = 0
	proto.lineCount = 0
	if not stripped then
		debugSize = readUleb(reader)
		if debugSize > 0 then
			proto.firstLine = readUleb(reader)
			proto.lineCount = readUleb(reader)
		end
	end

	proto.code = sub(reader.bytes, reader.pos, reader.pos + proto.size * 4 - 1)
	reader.pos = reader.pos + proto.size * 4
	reader.pos = reader.pos + proto.upvalueCount * 2
	proto.gcConstants = readGcConstants(reader, gcCount)
	proto.numberConstants = readNumberConstants(reader, numberCount)

	proto.upvalueNames = {}
	proto.variables = {}
	if debugSize > 0 then
		readDebugInfo(reader, proto, reader.pos + debugSize)
	end

	reader.pos = stop
	local protos = reader.protos
	protos[#protos + 1] = proto
	return true
end

-- The name of the local variable living in `slot` while instruction `pc`
-- (0-based) runs. Slots are handed out in the order variables are declared.
local function localName(proto, pc, slot)
	for _, variable in ipairs(proto.variables) do
		if variable.startPc > pc then
			break
		end
		if pc < variable.endPc then
			if slot == 0 then
				return variable.name
			end
			slot = slot - 1
		end
	end
	return nil
end

local function gcConstant(proto, operand)
	return proto.gcConstants[#proto.gcConstants - operand]
end

local function stringConstant(proto, operand)
	local constant = gcConstant(proto, operand)
	return constant and constant.text
end

local function signature(name, proto)
	local params = {}
	for _, variable in ipairs(proto.variables) do
		if variable.startPc == 0 and #params < proto.paramCount then
			params[#params + 1] = variable.name
		end
	end
	if floor(proto.flags / PROTO_VARARG) % 2 == 1 then
		params[#params + 1] = "..."
	end
	return name .. "(" .. table.concat(params, ", ") .. ")"
end

-- Values that can't have members assigned to them.
local CONSTANT_KINDS = { ["function"] = true, string = true, number = true, boolean = true, ["nil"] = true }

local function isPublic(name)
	return sub(name, 1, 1) ~= "_"
end

local describe

-- `depth` stops a value that holds itself from recursing forever.
local MAX_DEPTH = 3

local function describeMembers(members, depth)
	local described = {}
	for name, value in pairs(members) do
		if isPublic(name) then
			if type(value) ~= "table" then
				described[name] = value
			elseif value.kind == "string" or value.kind == "number" or value.kind == "boolean" then
				described[name] = value.value
			elseif depth < MAX_DEPTH then
				described[name] = describe(name, value, depth + 1)
			else
				described[name] = "<" .. value.kind .. ">"
			end
		end
	end
	return described
end

function describe(name, value, depth)
	local kind = value.kind
	if kind == "function" then
		return { kind = kind, signature = signature(name, value.proto) }
	end

	local described
	if kind == "table" then
		described = { kind = kind }
	elseif kind == "call" then
		local args = {}
		if depth < MAX_DEPTH then
			for index, arg in ipairs(value.args) do
				args[index] = describe("?", arg, depth + 1)
			end
		end
		described = { kind = kind, call = value.callee, args = args }
	elseif kind == "unknown" then
		described = { kind = kind, from = value.expr }
	else
		return { kind = kind, value = value.value }
	end
	if value.members then
		described.members = describeMembers(value.members, depth)
	end
	return described
end

local function describeAll(values)
	local described = {}
	for name, value in pairs(values) do
		if isPublic(name) then
			described[name] = describe(name, value, 0)
		end
	end
	return described
end

-- The register the module returns, which is where its API table lives.
local function findReturnedRegister(main)
	local returned
	for pc = 0, main.size - 1 do
		local op, a = byte(main.code, pc * 4 + 1, pc * 4 + 2)
		if op == OP_RET1 then
			returned = a
		end
	end
	return returned
end

-- Walks the module's top-level code, guessing what each register holds, and
-- collects what is assigned to the returned table and to globals.
local function analyze(main, argumentOffset)
	local registers = {}
	local exports = {}
	local globals = {}
	local requires = {}
	local exportsRegister = findReturnedRegister(main)

	local function nameOf(register, pc)
		local name = localName(main, pc, register)
		if name and sub(name, 1, 1) ~= "(" then
			return name
		end
		local value = registers[register]
		return value and value.expr
	end

	-- A module with many constants keeps member names in registers instead.
	local function registerString(register)
		local value = registers[register]
		return value and value.kind == "string" and value.value or nil
	end

	for pc = 0, main.size - 1 do
		local op, a, c, b = byte(main.code, pc * 4 + 1, pc * 4 + 4)
		local d = c + b * 256

		if op == OP_KSTR then
			registers[a] = { kind = "string", value = stringConstant(main, d) }
		elseif op == OP_KSHORT then
			registers[a] = { kind = "number", value = d >= 32768 and d - 65536 or d }
		elseif op == OP_KNUM then
			registers[a] = { kind = "number", value = main.numberConstants[d + 1] }
		elseif op == OP_KPRI then
			if d == 0 then
				registers[a] = { kind = "nil" }
			else
				registers[a] = { kind = "boolean", value = d == 2 }
			end
		elseif op == OP_KNIL then
			for register = a, d do
				registers[register] = { kind = "nil" }
			end
		elseif op == OP_MOV then
			registers[a] = registers[d]
		elseif op == OP_UGET then
			registers[a] = { kind = "unknown", expr = main.upvalueNames[d + 1] }
		elseif op == OP_FNEW then
			registers[a] = { kind = "function", proto = gcConstant(main, d).child }
		elseif op == OP_TNEW then
			registers[a] = { kind = "table", members = {} }
		elseif op == OP_TDUP then
			local members = {}
			for key, value in pairs(gcConstant(main, d).template) do
				members[key] = value
			end
			registers[a] = { kind = "table", members = members }
		elseif op == OP_GGET then
			registers[a] = { kind = "unknown", expr = stringConstant(main, d) }
		elseif op == OP_GSET then
			local name = stringConstant(main, d)
			globals[name] = registers[a] or { kind = "unknown" }
		elseif op == OP_TGETS or op == OP_TGETV then
			local key
			if op == OP_TGETS then
				key = stringConstant(main, c)
			else
				key = registerString(c)
			end
			if not key then
				registers[a] = nil
			elseif b == exportsRegister and exports[key] then
				registers[a] = exports[key]
			else
				registers[a] = { kind = "unknown", expr = (nameOf(b, pc) or "?") .. "." .. key }
			end
		elseif op == OP_TSETS or op == OP_TSETV then
			local key
			if op == OP_TSETS then
				key = stringConstant(main, c)
			else
				key = registerString(c)
			end
			local value = registers[a] or { kind = "unknown" }
			-- A computed key leaves nothing to name the member by.
			if key and b == exportsRegister then
				exports[key] = value
			elseif key and registers[b] and not CONSTANT_KINDS[registers[b].kind] then
				local target = registers[b]
				target.members = target.members or {}
				target.members[key] = value
			end
		elseif op >= OP_CALLM and op <= OP_CALLT then
			local callee = nameOf(a, pc)
			local args = {}
			if op == OP_CALL and b >= 1 then
				local first = a + argumentOffset
				for register = first, first + b - 2 do
					args[#args + 1] = registers[register] or { kind = "unknown" }
				end
			end
			if callee == "require" and args[1] and args[1].kind == "string" then
				requires[#requires + 1] = args[1].value
			end
			for register in pairs(registers) do
				if register >= a then
					registers[register] = nil
				end
			end
			if op == OP_CALL and c ~= 1 then
				registers[a] = { kind = "call", callee = callee, args = args }
			end
		elseif writesRegisterA(op) then
			registers[a] = nil
		end
	end

	-- Tables the module fills in but never exposes, such as a registry that an
	-- exported `__index` function reads from.
	local exposed = {}
	if exportsRegister and registers[exportsRegister] then
		exposed[registers[exportsRegister]] = true
	end
	for _, value in pairs(exports) do
		exposed[value] = true
	end
	local privateTables = {}
	for register, value in pairs(registers) do
		if not exposed[value] and value.members and next(value.members) then
			local name = localName(main, main.size - 1, register)
			if name and sub(name, 1, 1) ~= "(" then
				privateTables[name] = value
			end
		end
	end

	return {
		requires = requires,
		exports = describeAll(exports),
		globals = describeAll(globals),
		privateTables = describeAll(privateTables),
	}
end

-- The game has no way to compile Lua text, so scripts shipped as plain source
-- get a heuristic scan instead: only functions declared at the top level of
-- the returned table are found, either as `function Mod.name(...)` or as
-- `Mod.name = function(...)`.
local function parseSource(text)
	local exportsName = text:match("\nreturn%s+([%a_][%w_]*)%s*$")
	if not exportsName then
		return nil, "no returned table"
	end

	local requires = {}
	for moduleName in text:gmatch("require%s*%(?%s*[\"']([^\"']+)[\"']") do
		requires[#requires + 1] = moduleName
	end

	local exports = {}
	local function add(name, parameters)
		if sub(name, 1, 1) ~= "_" then
			parameters = parameters:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
			exports[name] = { kind = "function", signature = name .. "(" .. parameters .. ")" }
		end
	end
	local escaped = exportsName:gsub("%p", "%%%0")
	for separator, name, parameters in text:gmatch("\nfunction%s+" .. escaped .. "([%.:])([%w_]+)%s*%(([^)]*)%)") do
		if separator == ":" then
			parameters = parameters == "" and "self" or "self, " .. parameters
		end
		add(name, parameters)
	end
	for name, parameters in text:gmatch("\n" .. escaped .. "%.([%w_]+)%s*=%s*function%s*%(([^)]*)%)") do
		add(name, parameters)
	end

	return {
		requires = requires,
		exports = exports,
		globals = {},
		privateTables = {},
		source = true,
	}
end

-- Returns the API recovered from one script, or nil and the reason when the
-- script cannot be read. Compiled scripts are parsed exactly; plain source is
-- scanned heuristically and flagged with `source = true`.
function BytecodeApi.parse(bytes)
	if sub(bytes, 1, 3) ~= "\27LJ" then
		return parseSource("\n" .. bytes)
	end

	local reader = { bytes = bytes, pos = 5, protos = {} }
	local flags = readUleb(reader)
	if flags % 2 == FLAG_BIG_ENDIAN then
		return nil, "big-endian bytecode"
	end
	local stripped = floor(flags / FLAG_STRIPPED) % 2 == 1
	local fr2 = floor(flags / FLAG_FR2) % 2 == 1
	if not stripped then
		readString(reader, readUleb(reader))
	end

	while readProto(reader, stripped) do
		-- Each call reads one prototype; the last one is the main chunk.
	end

	local main = reader.protos[#reader.protos]
	if not main then
		return nil, "no prototypes"
	end
	return analyze(main, fr2 and 2 or 1)
end

return BytecodeApi
