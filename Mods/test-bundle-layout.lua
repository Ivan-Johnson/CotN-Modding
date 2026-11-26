-- Offline test for bundle-layout.lua, covering the Lua syntax its rewrite and
-- its check must agree on. Run from this directory: luajit test-bundle-layout.lua
-- Needs `bundle-layout` (the flake's wrapper) on `PATH`; the `bundle-layout`
-- flake check provides it.
package.path = "./?.lua;" .. package.path
local BundleLayout = require "bundle-layout"

local failures = 0

local function expect(name, actual, expected)
	if actual ~= expected then
		failures = failures + 1
		print(("FAIL %s\n  expected: %s\n  actual:   %s"):format(name, tostring(expected), tostring(actual)))
	end
end

local function rewrite(source)
	local result, violations = BundleLayout.rewrite(source, { "Alpha", "Beta" }, "Bundle")
	return result or ("violations: " .. #violations)
end

local rewritten = {
	['require "Alpha.x"'] = 'require "Bundle.Alpha.x"',
	["require 'Alpha.single'"] = "require 'Bundle.Alpha.single'",
	['require("Alpha.x")'] = 'require("Bundle.Alpha.x")',
	['pcall(require, "Beta.y")'] = 'pcall(require, "Bundle.Beta.y")',
	["require [[Alpha.long]]"] = "require [[Bundle.Alpha.long]]",
	['-- require "Alpha.in_comment"'] = '-- require "Alpha.in_comment"',
	["--[[ require 'Alpha.x' ]]"] = "--[[ require 'Alpha.x' ]]",
	['require "other.module"'] = 'require "other.module"',
	['require "Alphabet.x"'] = 'require "Alphabet.x"',
	['require "Bundle.Alpha.x"'] = 'require "Bundle.Alpha.x"',
	['local s = "it\\"s"; require "Alpha.x"'] = 'local s = "it\\"s"; require "Bundle.Alpha.x"',
	['require "Alpha.a" require "Alpha.b"'] = 'require "Bundle.Alpha.a" require "Bundle.Alpha.b"',
}
for source, expected in pairs(rewritten) do
	expect("rewrite " .. source, rewrite(source), expected)
end

local rejected = {
	'require("Alpha." .. x)',
	'x = "Alpha.x"',
	'x = [[Alpha.long]]',
	'string.format("Alpha.%s", x)',
	"x = 'Alpha.x'",
}
for _, source in ipairs(rejected) do
	expect("reject " .. source, rewrite(source), "violations: 1")
end

local _, violations = BundleLayout.scan('-- a\n--[[ b\nc ]]\nlocal x = 1\ny = "Alpha.z"', { "Alpha" })
expect("violation line", violations[1] and violations[1].line, 5)

-- The filesystem side, on a throwaway mods directory.
local tmp = io.popen("mktemp -d"):read("*l")
local function write(path, content)
	os.execute("mkdir -p " .. tmp .. "/" .. path:match("^(.*)/[^/]*$"))
	local handle = assert(io.open(tmp .. "/" .. path, "w"))
	handle:write(content)
	handle:close()
end
write(
	"Alpha/mod.json",
	'{"namespace":"Alpha","name":"Alpha","synchronyVersion":"1.0","dependencies":{"Beta":"1","Outside":"1"}}'
)
write("Alpha/a.lua", 'require "Beta.x"')
write("Beta/mod.json", '{"namespace":"Wrong","name":"Beta","synchronyVersion":"1.0"}')
write("Gamma/mod.json", '{"namespace":"Gamma","name":"Gamma","synchronyVersion":"2.0"}')
write("Delta/mod.json", '{"namespace":"Delta","name":"Delta"}')
write("Beta/x.lua", 'x = "Beta.x"')

local errors = BundleLayout.check(tmp)
expect("check finds the namespace, the stray string, Gamma's version and Delta's missing one", #errors, 4)
expect("checkInstall refuses a missing Mods/ dependency", #BundleLayout.checkInstall(tmp, { "Alpha" }), 1)
expect("checkInstall ignores dependencies outside Mods/", #BundleLayout.checkInstall(tmp, { "Alpha", "Beta" }), 0)
expect(
	"checkInstall refuses mods whose synchronyVersion differs",
	#BundleLayout.checkInstall(tmp, { "Alpha", "Beta", "Gamma" }),
	1
)
expect(
	"checkInstall refuses a mod without a synchronyVersion",
	#BundleLayout.checkInstall(tmp, { "Alpha", "Beta", "Delta" }),
	1
)
expect("rewriteTree refuses unsafe trees", #BundleLayout.rewriteTree(tmp, "Bundle", { "Alpha", "Beta" }), 1)
-- The command line, through the real wrapper. The module-level cases above
-- cannot see a broken entry guard, which makes every command a silent no-op.
local function succeeds(command)
	local status = os.execute(command .. " 2>/dev/null")
	return status == 0 or status == true
end

local function read(path)
	local handle = assert(io.open(tmp .. "/" .. path, "r"))
	local content = handle:read("*a")
	handle:close()
	return content
end

expect("cli check fails on a violating tree", succeeds("bundle-layout check " .. tmp), false)
expect(
	"cli check-install fails on a missing dependency",
	succeeds("bundle-layout check-install " .. tmp .. " Alpha"),
	false
)
expect(
	"cli check-install passes when dependencies are installed",
	succeeds("bundle-layout check-install " .. tmp .. " Alpha Beta"),
	true
)
expect("cli rewrite fails on an unsafe tree", succeeds("bundle-layout rewrite " .. tmp .. " Bundle Alpha Beta"), false)
expect("cli rewrite leaves an unsafe tree untouched", read("Alpha/a.lua"), 'require "Beta.x"')
expect("cli rejects bad usage", succeeds("bundle-layout bogus"), false)

write("Beta/x.lua", 'require "Alpha.y"')
expect("cli rewrite succeeds on a safe tree", succeeds("bundle-layout rewrite " .. tmp .. " Bundle Alpha Beta"), true)
expect("cli rewrite prefixes the require", read("Beta/x.lua"), 'require "Bundle.Alpha.y"')
expect("cli rewrite prefixes every mod", read("Alpha/a.lua"), 'require "Bundle.Beta.x"')

os.execute("rm -rf " .. tmp)

if failures > 0 then
	os.exit(1)
end
print("bundle-layout tests passed")
