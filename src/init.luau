--[[ 
    🌌 Galaxy Framework
    🚀 A fast, lightweight game framework for Roblox
    
    📦 Features:
    • 🔄 Automatic module loading
    • 🎮 Client/Server system management
    • ⚡ Optimized for performance
    • 🛡️ Type-safe with Luau
    
    Version: 1.2.0
    Author: ArtisticVampyre
	Contributor: @32_Bits (https://github.com/git0uttahere)
--]]

-- 🔧 Core Services
local HttpService: HttpService = game:GetService("HttpService")
local RunService: RunService = game:GetService("RunService")

-- ⚙️ Configuration
-- How long (in seconds) a require/onInit may yield before Galaxy warns about it.
local INIT_YIELD_WARNING_TIME = 3

-- 📝 Type Definitions
type LaunchParams = {
	Modules: { Instance },
	Systems: { Instance },
}

-- 🌟 Main Module
local Galaxy = { _VERSION = "1.2.0" }

-- 🎯 Environment Detection
local SystemKey: string = RunService:IsServer() and "service" or "controller"
local CycleMetatable = require(script.CycleMetatable)

-- 📦 Module Management
local ModulesLoading: { [ModuleScript]: boolean } = {}
local LoadedModules: { [ModuleScript]: any } = {}
local Modules: { [string]: ModuleScript } = {}
local Systems: { [ModuleScript]: any?} = {}

-----------------------------------------------------
-- Helper Functions
-----------------------------------------------------

local function _errorHandler(err: any): string
	return tostring(err) .. "\n" .. debug.traceback()
end

--[[
	Requires a module with error isolation + a yield watchdog. require() runs the
	module's top-level body, which can both error AND yield (e.g. a top-level
	WaitForChild / :Wait()). Either would otherwise silently stall the whole boot,
	so we catch errors (returning ok = false) and warn by name if the require
	yields longer than INIT_YIELD_WARNING_TIME.
]]
local function _safeRequire(module: ModuleScript, label: string): (boolean, any)
	local completed = false
	task.delay(INIT_YIELD_WARNING_TIME, function()
		if not completed then
			warn(`⏳[Galaxy][IMPORTANT] requiring {label} {module.Name} has been yielding for {INIT_YIELD_WARNING_TIME}s+. A top-level WaitForChild/:Wait()/yield during require blocks the whole boot, move it into onStart.`)
		end
	end)

	local ok, result = xpcall(require, _errorHandler, module)
	completed = true
	return ok, result
end

-- Count the number of ancestors for a given instance.
local function countAncestors(instance: Instance): number
	local count = 0
	while instance.Parent do
		count += 1
		instance = instance.Parent
	end
	return count
end

-- Adds a metatable to a temporary module table so that operations
local function _switchTemp(moduleName: string, moduleData: any)
	local loadedModule = LoadedModules[Modules[moduleName]]
	loadedModule.IsFakeModule = nil
	if typeof(moduleData) == "table" then
		setmetatable(loadedModule, {
			__index = moduleData,
			__newindex = moduleData,
			__tostring = function()
				local result = "\nModule " .. moduleName .. ":\n"
				for key, value in moduleData do
					result = result .. "\t" .. tostring(key) .. ": " .. tostring(value) .. "\n"
				end
				return result
			end,
		})
	else
		LoadedModules[Modules[moduleName]] = moduleData
	end
end

-- Loads the given ModuleScript with error handling. Returns the loaded data.
local function _load(module: ModuleScript): any?
	CycleMetatable.CurrentModuleLoading = module.Name

	local success, dataOrErr = _safeRequire(module, "module")
	CycleMetatable.CurrentModuleLoading = nil

	if success then
		return dataOrErr
	end

	warn(`❌ [Galaxy][CRITICAL] Failed to require module {module.Name} (skipped — other modules still load):\n{dataOrErr}`)
	return nil
end

-- Adds a ModuleScript to the internal registry, checking for duplicates.
local function _indexNames(child: ModuleScript)
	if not child:IsA("Instance") then
		return
	end

	local name = child.Name

	if Modules[name] then
		local existingCount = countAncestors(Modules[name])
		local newCount = countAncestors(child)
		if newCount < existingCount then
			Modules[name] = child
		else
			-- Optionally warn about duplicate module names:
			-- warn(("⚠️ Duplicate module name '%s' detected. Keeping version with fewer ancestors."):format(name))
		end
	else
		Modules[name] = child
	end
end

-- Indexes any ModuleScript children of the specified Instance
local function _indexModules(location: Instance)
	for _, descendant in location:GetDescendants() do
		if
			descendant:IsA("ModuleScript")
			and not descendant:FindFirstAncestorWhichIsA("ModuleScript")
			and descendant ~= script
		then
			_indexNames(descendant)
		end
	end
end

-----------------------------------------------------
-- System Management
-----------------------------------------------------

-- Loads internal modules for a system from designated directories.
local function _loadInternal(system, rootModule: ModuleScript)
	local internal = system.DirectoriesToLoad
	if not internal then
		return
	end

	local root: Folder | ModuleScript

	if #rootModule:GetChildren() > 0 then
		root = rootModule
	else
		root = rootModule:FindFirstAncestorWhichIsA("Folder")
	end

	for _, dirKey: string in internal do
		local dir: Folder? = root:FindFirstChild(dirKey) :: Folder?
		if not dir then
			warn(`❗️Internal directory {dirKey} not found in system {root.Name}! 🚫`)
			continue
		end

		for _, module: ModuleScript in dir:GetDescendants() do
			if not module:IsA("ModuleScript") then
				continue
			end

			local success, dataOrErr = _safeRequire(module, "internal module")
			if not success then
				warn(`❌ [Galaxy] Failed to load internal module {module.Name} in system {root.Name} (skipped)! 💥\nError: {dataOrErr}`)
				continue
			end

			system[module.Name] = require(module)
		end
	end
end

-- Collects ModuleScripts that match the system key into systemModules and requires the whole batch in parallel afterwards.
local function _indexSystems(location: Instance, systemModules: { ModuleScript })
	for _, descendant: ModuleScript in location:GetDescendants() do
		if descendant:IsA("ModuleScript") and descendant ~= script then
			local childIndex = descendant.Name:lower()
			if childIndex:find(SystemKey) then
				table.insert(systemModules, descendant)
			end
		end
	end
end

local function _loadSystems(systemModules: { ModuleScript })
	local pending = #systemModules

	for _, moduleScript: ModuleScript in systemModules do
		task.spawn(function()
			local activeSystem = _load(moduleScript)
			if activeSystem then
				_loadInternal(activeSystem, moduleScript)
				Systems[moduleScript] = activeSystem
			end
			pending -= 1
		end)
	end

	while pending > 0 do
		task.wait()
	end
end

-----------------------------------------------------
-- 🛡️ Fake Module Protection
-----------------------------------------------------

local FakeModule = { IsFakeModule = true }
setmetatable(FakeModule, CycleMetatable)

-----------------------------------------------------
-- 🚀 Core API
-----------------------------------------------------

function Galaxy.__call(_: {}, module: string | ModuleScript): any?
	if typeof(module) == "Instance" then
		return _load(module)
	end

	local mod = Modules[module]

	if not mod then
		warn(`❗️Module '{module}' not found! 🚫`)
		LoadedModules[mod] = FakeModule
		return
	end

	if LoadedModules[mod] then
		return LoadedModules[mod]
	end

	if not ModulesLoading[mod] then
		ModulesLoading[mod] = true
		local moduleData = _load(mod)
		if LoadedModules[mod] then
			_switchTemp(module, moduleData)
		else
			LoadedModules[mod] = moduleData
		end
		ModulesLoading[mod] = nil
	end

	return LoadedModules[mod]
end

-----------------------------------------------------
-- 🎯 Framework Launch
-----------------------------------------------------

function Galaxy.Launch(launchParams: LaunchParams)
	assert(typeof(launchParams) == "table", `Expected table, got {typeof(launchParams)}`)

	for _, moduleRoot: Instance in launchParams.Modules do
		_indexModules(moduleRoot)
	end

	local systemModules: { ModuleScript } = {}
	for _, systemRoot: Instance in launchParams.Systems do
		_indexSystems(systemRoot, systemModules)
	end

	-- Require every system in parallel and wait for the whole batch before running any lifecycle hooks.
	_loadSystems(systemModules)

	for moduleScript, system in Systems do
		if typeof(system.onInit) ~= "function" then
			continue
		end

		local initThread = task.spawn(function()
			system.onInit(system)
		end)

		if coroutine.status(initThread) == "suspended" then
			warn(
				`⏳ [Galaxy][IMPORTANT] {moduleScript:GetFullName()}.onInit yielded, continuing without waiting for it. Move WaitForChild / :Wait() / network calls into onStart so init order stays deterministic.`
			)
		end
	end

	for _, system in Systems do
		if typeof(system.onStart) ~= "function" then
			continue
		end
		task.spawn(system.onStart, system)
	end
end

-----------------------------------------------------
-- 🛰️ Metatable Setup
-----------------------------------------------------

setmetatable(shared, Galaxy)
setmetatable(Galaxy, Galaxy)

return Galaxy
