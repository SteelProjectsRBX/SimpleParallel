-- ServerScriptService.Script

--!strict
local SimpleParallel = require(game.ReplicatedStorage.SimpleParallel)

local funcToUse = game.ReplicatedStorage.FuncToExecute -- (dont require it!)

local newParallelInstance = SimpleParallel.new(funcToUse, 4, 0, "HeavyWork")
task.wait() -- (only necessary in Deferred SignalBehavior. More details in the Precautions section in the devforum post)

while true do
	for i = 1, 4 do -- Best practice is to schedule as many tasks as there are actors, or less.
		newParallelInstance:ScheduleTask(75000)
	end
	local results  = newParallelInstance:ExecuteTasks()
	
	task.wait()
end