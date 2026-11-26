-- The rules that let install-mods put mods in a bundle (ADR-0004), checked and
-- applied from one place so they cannot drift apart.
--
-- A module's name is "<mod name>.<path>", so inside the bundle a mod's modules
-- gain the bundle's name as a prefix. A string literal that starts with
-- "<mod>." is only rewritable when it is the whole, static argument of a
-- require: `require "A.b"`, `require("A.b")` or `pcall(require, "A.b")`, in any
-- quote style. Comments are ignored. Any other such string, including one
-- built by concatenation, is a violation, because rewriting it could change
-- something that isn't a module name.
--
-- Usage (needs lua-cjson):
--   luajit bundle-layout.lua check MODS_DIR
--   luajit bundle-layout.lua check-install MODS_DIR MOD...
--   luajit bundle-layout.lua rewrite STAGE_DIR BUNDLE MOD...
local cjson = require "cjson"

local M = {}

-- Splits Lua source into tokens, skipping whitespace and comments. A string
-- token's `from`/`to` bound its contents, without the quotes or brackets.
local function tokenize(source)
	local tokens = {}
	local pos = 1
	local line = 1

	local function countLines(from, to)
		for _ in source:sub(from, to):gmatch("\n") do
			line = line + 1
		end
	end

	local function longBracket(at)
		local equals = source:match("^%[(=*)%[", at)
		if not equals then
			return nil
		end
		local open = at + #equals + 2
		local closeFrom, closeTo = source:find("]" .. equals .. "]", open, true)
		return open, (closeFrom or #source + 1) - 1, (closeTo or #source)
	end

	while pos <= #source do
		local char = source:sub(pos, pos)
		if char == "\n" then
			line = line + 1
			pos = pos + 1
		elseif char:match("%s") then
			pos = pos + 1
		elseif source:sub(pos, pos + 1) == "--" then
			local _, _, closeTo = longBracket(pos + 2)
			local stop = closeTo or ((source:find("\n", pos, true) or #source + 1) - 1)
			countLines(pos, stop)
			pos = stop + 1
		elseif char == '"' or char == "'" then
			local scan = pos + 1
			while scan <= #source and source:sub(scan, scan) ~= char do
				scan = scan + (source:sub(scan, scan) == "\\" and 2 or 1)
			end
			tokens[#tokens + 1] = { kind = "string", from = pos + 1, to = scan - 1, line = line }
			countLines(pos, scan)
			pos = scan + 1
		elseif char == "[" and longBracket(pos) then
			local from, to, closeTo = longBracket(pos)
			tokens[#tokens + 1] = { kind = "string", from = from, to = to, line = line }
			countLines(pos, closeTo)
			pos = closeTo + 1
		elseif char:match("[%a_]") then
			local name = source:match("^[%w_]+", pos)
			tokens[#tokens + 1] = { kind = "name", text = name, line = line }
			pos = pos + #name
		elseif source:sub(pos, pos + 1) == ".." then
			tokens[#tokens + 1] = { kind = "symbol", text = "..", line = line }
			pos = pos + 2
		else
			tokens[#tokens + 1] = { kind = "symbol", text = char, line = line }
			pos = pos + 1
		end
	end
	return tokens
end

-- Finds the module-name strings in `source` that start with any of `mods` (a
-- list of mod names). Returns `rewritable`, the byte offsets where a bundle
-- prefix goes (ascending), and `violations`, each `{line, text}`.
function M.scan(source, mods)
	local rewritable, violations = {}, {}
	local tokens = tokenize(source)
	for index, token in ipairs(tokens) do
		if token.kind == "string" then
			local text = source:sub(token.from, token.to)
			for _, mod in ipairs(mods) do
				if text:sub(1, #mod + 1) == mod .. "." then
					local before, beforeThat, after = tokens[index - 1], tokens[index - 2], tokens[index + 1]
					local isRequireArgument = before
						and (
							(before.kind == "name" and before.text == "require")
							or (
								before.kind == "symbol"
								and (before.text == "(" or before.text == ",")
								and beforeThat
								and beforeThat.kind == "name"
								and beforeThat.text == "require"
							)
						)
					if isRequireArgument and not (after and after.text == "..") then
						rewritable[#rewritable + 1] = token.from
					else
						violations[#violations + 1] = { line = token.line, text = text }
					end
					break
				end
			end
		end
	end
	return rewritable, violations
end

-- Returns `source` with `prefix` inserted at each of `offsets` (ascending).
function M.insertAt(source, offsets, prefix)
	local parts, last = {}, 1
	for _, offset in ipairs(offsets) do
		parts[#parts + 1] = source:sub(last, offset - 1)
		parts[#parts + 1] = prefix
		last = offset
	end
	parts[#parts + 1] = source:sub(last)
	return table.concat(parts)
end

-- Returns `source` with every module name of `mods` prefixed with `bundle .. "."`,
-- or nil and the violations if some string can't be rewritten safely.
function M.rewrite(source, mods, bundle)
	local offsets, violations = M.scan(source, mods)
	if #violations > 0 then
		return nil, violations
	end
	return M.insertAt(source, offsets, bundle .. ".")
end

-- Everything below touches the filesystem.

local function readFile(path)
	local handle = assert(io.open(path, "rb"))
	local content = handle:read("*a")
	handle:close()
	return content
end

local function writeFile(path, content)
	local handle = assert(io.open(path, "wb"))
	handle:write(content)
	handle:close()
end

local function shellLines(command)
	local lines = {}
	local handle = assert(io.popen(command))
	for line in handle:lines() do
		lines[#lines + 1] = line
	end
	handle:close()
	return lines
end

local function quote(text)
	return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function luaFilesUnder(dir)
	return shellLines("find " .. quote(dir) .. " -name '*.lua' | sort")
end

local function manifest(modsDir, mod)
	return cjson.decode(readFile(modsDir .. "/" .. mod .. "/mod.json"))
end

local function modsUnder(modsDir)
	local mods = {}
	for _, path in ipairs(shellLines("ls -d " .. quote(modsDir) .. "/*/mod.json")) do
		mods[#mods + 1] = path:match("([^/]+)/mod%.json$")
	end
	return mods
end

local function reportViolations(path, violations, errors)
	for _, violation in ipairs(violations) do
		errors[#errors + 1] = string.format(
			'%s:%d: "%s" names a mod\'s modules outside the argument of a require, so install-mods cannot rewrite it',
			path,
			violation.line,
			violation.text
		)
	end
end

-- install-mods gives the bundle the `synchronyVersion` of the mods it holds,
-- so each of `mods` must declare one, and all the same. Appends to `errors`.
local function checkSynchronyVersion(modsDir, mods, errors)
	local first = mods[1]
	local expected = first and manifest(modsDir, first).synchronyVersion
	for index, mod in ipairs(mods) do
		local actual = manifest(modsDir, mod).synchronyVersion
		if type(actual) ~= "string" then
			errors[#errors + 1] = string.format('%s/mod.json: "synchronyVersion" must be a string', mod)
		elseif index > 1 and type(expected) == "string" and actual ~= expected then
			errors[#errors + 1] = string.format(
				'%s/mod.json: "synchronyVersion" is "%s", expected "%s" to match %s/mod.json',
				mod,
				actual,
				expected,
				first
			)
		end
	end
end

-- Checks every mod directly under `modsDir`; returns a list of error messages.
function M.check(modsDir)
	local errors = {}
	local mods = modsUnder(modsDir)
	checkSynchronyVersion(modsDir, mods, errors)
	for _, mod in ipairs(mods) do
		local mod_json = manifest(modsDir, mod)
		for _, field in ipairs({ "namespace", "name" }) do
			if mod_json[field] ~= mod then
				errors[#errors + 1] = string.format(
					'%s/mod.json: "%s" is "%s", expected "%s" to match its directory',
					mod,
					field,
					tostring(mod_json[field]),
					mod
				)
			end
		end
		for _, path in ipairs(luaFilesUnder(modsDir .. "/" .. mod)) do
			local _, violations = M.scan(readFile(path), mods)
			reportViolations(path, violations, errors)
		end
	end
	return errors
end

-- A bundled mod can only find mods bundled with it, so each of `installing`
-- must not depend on a mod of `modsDir` that isn't also being installed. The
-- installed mods must also agree on `synchronyVersion`: the source tree can
-- hold edits the `mods-layout` check has not seen.
function M.checkInstall(modsDir, installing)
	local errors = {}
	checkSynchronyVersion(modsDir, installing, errors)
	local installed, available = {}, {}
	for _, mod in ipairs(installing) do
		installed[mod] = true
	end
	for _, mod in ipairs(modsUnder(modsDir)) do
		available[mod] = true
	end
	for _, mod in ipairs(installing) do
		for dependency in pairs(manifest(modsDir, mod).dependencies or {}) do
			if available[dependency] and not installed[dependency] then
				errors[#errors + 1] =
					string.format("%s depends on %s, which is not being installed", mod, dependency)
			end
		end
	end
	return errors
end

-- Rewrites, in place, every Lua file under `stageDir`.
function M.rewriteTree(stageDir, bundle, mods)
	local errors = {}
	local rewritten = {}
	for _, path in ipairs(luaFilesUnder(stageDir)) do
		local result, violations = M.rewrite(readFile(path), mods, bundle)
		if result then
			rewritten[path] = result
		else
			reportViolations(path, violations, errors)
		end
	end
	if #errors == 0 then
		for path, content in pairs(rewritten) do
			writeFile(path, content)
		end
	end
	return errors
end

local function main(args)
	local command = args[1]
	local errors
	if command == "check" and #args == 2 then
		errors = M.check(args[2])
	elseif command == "check-install" and #args >= 2 then
		errors = M.checkInstall(args[2], { unpack(args, 3) })
	elseif command == "rewrite" and #args >= 3 then
		errors = M.rewriteTree(args[2], args[3], { unpack(args, 4) })
	else
		io.stderr:write(
			"usage: bundle-layout.lua check MODS_DIR | check-install MODS_DIR MOD... | rewrite STAGE_DIR BUNDLE MOD...\n"
		)
		os.exit(2)
	end
	for _, message in ipairs(errors) do
		io.stderr:write("bundle-layout: ", message, "\n")
	end
	os.exit(#errors == 0 and 0 or 1)
end

-- `...` is this module's name when required, and the command line when run.
if (...) ~= "bundle-layout" then
	main({ ... })
end

return M
