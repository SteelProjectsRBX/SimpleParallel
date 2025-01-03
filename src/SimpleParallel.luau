--!strict
--!native

local RunService = game:GetService("RunService")

local SimpleParallelConstructor = {}

local isClient = RunService:IsClient()

local VMHolder = Instance.new("Folder")
local VMScriptName = "SimpleParallel" .. (isClient and "Client" or "Server")

local NextFrame = isClient and RunService.RenderStepped or RunService.PreAnimation

VMHolder.Name = "ParallelSchedulerContainer"
VMHolder.Parent = isClient and game.Players.LocalPlayer.PlayerScripts or game.ServerScriptService

export type ParallelInstance = {
	Container: typeof(script.ParallelInstanceTemplate),
	_VMs: {typeof(script.ActorTemplate)},
	PerformingWork: boolean,
	Tasks: {[number]: {any}},
}

local function checkForExceptions(performingWork: boolean, areScriptsSetUp: boolean, functionName: string)
	if performingWork then
		error(`The current ParallelInstance is already performing work!`)
		return
	elseif not areScriptsSetUp then
		error(`Due to Roblox's deferred signal behavior, newly-enabled scripts don't run until the next frame. Don't call {functionName}() in the same frame as the one you called the .new() constructor.`)
	end
end

local function ExecuteTasks(ParallelInstance: ParallelInstance, timeout: number)
	debug.profilebegin("ExecuteTasks")
	local tasksFinished = 0

	local totalTasks = #ParallelInstance.Tasks
	local totalVMS = #ParallelInstance._VMs

	local tasksPerVM = math.floor(totalTasks / totalVMS)
	local leftoverTasks = totalTasks % totalVMS -- Distribute this across the rest of the VMs to ensure the fastest possible execution times

	local mainThread = coroutine.running()
	local result = table.create(totalTasks)

	local ParallelManagementThread = task.spawn(function()
		local taskFinishedCon
		local currentThread = coroutine.running()
		
		taskFinishedCon = ParallelInstance.Container._VMTaskFinished.Event:Connect(function(res: {any}, startingTaskIndex: number, endingTaskIndex: number)
			for taskIndex: number, actorResult in res do
				result[tonumber(taskIndex):: number] = actorResult -- when i was fixing bugs, taskIndex suddenly turned into a string💀 i have no idea how, but using tonumber() fixes it
			end
			tasksFinished += (endingTaskIndex - startingTaskIndex) + 1
			
			if tasksFinished >= totalTasks then
				taskFinishedCon:Disconnect()
				
				task.cancel(currentThread)
				task.spawn(mainThread) -- All actors finished their work: Resume the script and return all results
			end
		end)

		local taskIndex = 1

		for VMID, VM in ipairs(ParallelInstance._VMs) do
			if taskIndex > totalTasks then break end  -- No more tasks left to assign (only gets reached when if actors > tasks assigned)
			local tasksToExecute = tasksPerVM + (VMID <= leftoverTasks and 1 or 0) -- evenly distribute the tasks across all actors
			local nextTaskIndex = taskIndex + tasksToExecute - 1
			
			task.defer(VM.SendWorkSignal.Fire, VM.SendWorkSignal, table.move(ParallelInstance.Tasks, taskIndex, nextTaskIndex, 1, {}), taskIndex, nextTaskIndex)
			
			taskIndex += tasksToExecute
		end
		
		coroutine.yield() -- Suspend this subthread until work is finished. (its killed in line 60)
	end)

	task.spawn(function()
		task.wait(timeout or 0)
		NextFrame:Wait()
		
		if coroutine.status(ParallelManagementThread) ~= "dead" then 
			error(`ParallelInstance: The Luau VM(s) yielded, took too long to complete, or errored (causing the main thread to yield infinitely). Make sure to fix any bugs, or remove any yielding code. Alternatively, specify a [timeout] argument in the constructor.`, 2)
		end
	end)

	coroutine.yield()

	table.clear(ParallelInstance.Tasks)

	return result
end

function SimpleParallelConstructor.new(module: ModuleScript, workers: number, timeout: number?, name: string?)
	local require = require -- i love roblox typechecking so much (this removes a warning for an "unsupported path" (ty roblox))
	if typeof(require(module)) ~= "function" then
		error("The given ModuleScript didn't return a function!")
	end
	
	local newTemplate = script.ParallelInstanceTemplate:Clone()
	local areScriptsSetUp = false -- If you're reading this and using Immediate SignalBehavior, you can turn this to true without any issues.

	local ParallelInstance = {
		Container = newTemplate,
		_VMs = {}:: {Actor & {SendWorkSignal: BindableEvent}},
		Tasks = {},
		PerformingWork = false,
	}
	
	newTemplate.LoadedModule.Value = module -- short access to the path of the module

	for i = 1, workers do
		local newActor = newTemplate.ActorTemplate:Clone()
		local workerScript = newActor[VMScriptName]:: BaseScript
		local microProfilerName = name or ""
		
		-- Unfortunately, due to amazing roblox deferred signal behavior, the script will only finish executing (and set up signals) ONLY at the end of the frame
		newActor.SetupWorker.Name = `VM#{i}({microProfilerName})`
		
		workerScript.Enabled = true

		newActor.Name = "Actor" .. i
		newActor.Parent = newTemplate

		ParallelInstance._VMs[i] = newActor
	end
	newTemplate.Parent = VMHolder
	
	function ParallelInstance:ScheduleTask<funcParams...>(...: funcParams...)
		checkForExceptions(ParallelInstance.PerformingWork, areScriptsSetUp, "ScheduleTask")
		
		table.insert(ParallelInstance.Tasks, table.pack(...):: {any})
	end
	
	function ParallelInstance:IsRunning() -- You should use this if you're not sure if the scheduler is performing a task or not
		return ParallelInstance.PerformingWork;
	end

	function ParallelInstance:ExecuteTasks()
		checkForExceptions(ParallelInstance.PerformingWork, areScriptsSetUp, "ExecuteTasks")
		ParallelInstance.PerformingWork = true
		local Result = ExecuteTasks(ParallelInstance, timeout or 0)
		ParallelInstance.PerformingWork = false

		return Result
	end
		
	function ParallelInstance:Destroy()
		ParallelInstance.Container:Destroy()
		
		table.clear(ParallelInstance)
	end

	task.defer(function()
		areScriptsSetUp = true
	end)
	
	return ParallelInstance
end

return SimpleParallelConstructor
