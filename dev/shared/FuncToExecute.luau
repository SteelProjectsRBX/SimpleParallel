-- ReplicatedStorage.FuncToExecute
local function work(count)
	local a, b = 1, 0
	
	for i = 1, count do
		a, b = b, a
	end
end

return function(count)	
	task.desynchronize() -- Hop into parallel execution mode
	
	debug.profilebegin("Desync work")
	work(count)
	debug.profileend()
	
	task.synchronize() -- ... and back into single-threaded mode
	
	debug.profilebegin("Synced work")
	work(count)
	debug.profileend()
	
	return math.random()
end