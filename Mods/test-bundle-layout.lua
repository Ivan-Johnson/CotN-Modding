-- Offline test for bundle-layout.lua, covering the Lua syntax its rewrite and
-- its check must agree on. Run from this directory: luajit test-bundle-layout.lua
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
write("Alpha/mod.json", '{"namespace":"Alpha","name":"Alpha","dependencies":{"Beta":"1","Outside":"1"}}')
write("Alpha/a.lua", 'require "Beta.x"')
write("Beta/mod.json", '{"namespace":"Wrong","name":"Beta"}')
write("Beta/x.lua", 'x = "Beta.x"')

local errors = BundleLayout.check(tmp)
expect("check finds the namespace and the stray string", #errors, 2)
expect("checkInstall refuses a missing Mods/ dependency", #BundleLayout.checkInstall(tmp, { "Alpha" }), 1)
expect("checkInstall ignores dependencies outside Mods/", #BundleLayout.checkInstall(tmp, { "Alpha", "Beta" }), 0)
expect("rewriteTree refuses unsafe trees", #BundleLayout.rewriteTree(tmp, "Bundle", { "Alpha", "Beta" }), 1)
os.execute("rm -rf " .. tmp)

if failures > 0 then
	os.exit(1)
end
print("bundle-layout tests passed")
