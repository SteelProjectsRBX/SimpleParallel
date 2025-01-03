--!native
--!strict
local Actor = script:GetActor():: typeof(script.Parent)
local transferResults = Actor.Parent:FindFirstChild("_VMTaskFinished"):: BindableEvent
local funcToExecute = require(Actor.Parent.LoadedModule.Value):: (...any) -> any -- The ModuleScript that the user loaded. (the first parameter of .new())

local workSignal: BindableEvent = script.Parent.SendWorkSignal:: BindableEvent

workSignal.Event:Connect(function(funcParameterTable: {{any}}, startingTaskIndex: number, endingTaskIndex: number)
	local Results = {}
	local taskProcessing = 1
	
	for taskIndex = startingTaskIndex, endingTaskIndex do
		Results[taskIndex] = funcToExecute(unpack(funcParameterTable[taskProcessing]))
		taskProcessing += 1
	end
	
	transferResults:Fire(Results, startingTaskIndex, endingTaskIndex)
end)

return true
