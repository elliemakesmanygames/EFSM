type Disconnect = () -> ()
type OnTransitionListener<T = unknown> = (v: Context<T>) -> ()

type State<T = unknown> = {
    name: string,
    action: (data: T, cleanupFn: (() -> ()) -> (), fsm: StateManager<T>) -> (),
	guard: ((data: T) -> boolean)?
}

type Context<T = unknown> = {
	data: T,
	currentState: State<T>?,
	previousState: State<T>?
}

type StateManagerConfig<T> = {
	currentData: T,
	currentState: State<T>
}

type StateManagerInfo<T> = {
	runningThread: thread?,
	context: Context<T>?,
	cleanup: (() -> ())?,
	active: boolean,
	on_trans_ls: { OnTransitionListener<T> }
}

type StateManager<T> = StateManagerInfo<T> & {
	__index: StateManager<T>,
	init: (StateManagerConfig: StateManagerConfig<T>) -> StateManager<T>,
	transition: (self: StateManager<T>, state_name: string) -> (),
	destroy: (self: StateManager<T>) -> (),
	onTransition: (self: StateManager<T>, callback: (new_state_context: Context<T>) -> ()) -> Disconnect
}

local StateManager = {} :: StateManager<unknown>
StateManager.__index = StateManager

local function safeCB(...) warn(`no function specified, resorted to default callback : {...}`) end

local function FireListener(listeners: { OnTransitionListener<unknown> }, context: Context<unknown>): ()
	for i = 1, #listeners do
		listeners[i](context)
	end
end

--[=[
    @function init
    @within StateManager

    @param StateManagerConfig -- a dictionary that contains the necessary information to initialize the StateManager, including states, initialState, and initialData.
	@return StateManager
]=]
function StateManager.init(StateConfig: StateManagerConfig<unknown>): StateManagerInfo<unknown>
	local self = setmetatable({}, StateManager)
	self.runningThread = nil
	self.context = { data = StateConfig.currentData, currentState = StateConfig.currentState, previousState = nil }
	self.cleanup = nil
	self.active = false

	self.on_trans_ls = {}
	return self :: StateManagerInfo<unknown>
end

--[=[
    @function transition
    @within StateManager

    @param state -- the state to transition to. must be of type State.
	@return ()
]=]
function StateManager:transition(state: State<unknown>): ()
	if self.active then
		error("cannot transition to new state: concurrency control.")
	end

	if self.cleanup then
		self.cleanup()
		self.cleanup = nil
	end

	if self.runningThread then
		self.context.active = true
		task.cancel(self.runningThread)
		self.runningThread = nil
	end

	if state.guard and not state.guard(self.context.data) then
		error(`guard condition failed for state: {state.name}`)
	end

	local executeFn = state.action or safeCB
	local function registerCleanup(fn: () -> ()): ()
		self.cleanup = fn
	end

	self.context.active = false
	self.runningThread = task.spawn(executeFn, self.context.data, registerCleanup, self)
	self.currentState = state

	FireListener(self.on_trans_ls, self.context)
end

--[=[
    @function destroy
    @within StateManager

	@return ()
]=]
function StateManager:destroy(): ()
	if self.cleanup then
        self.cleanup()
        self.cleanup = nil
    end

	if self.runningThread then
		task.cancel(self.runningThread)
	end

	self.runningThread = nil
	self.currentState = nil
	self.context = nil
end

--[=[
    @function onTransition
    @within StateManager

	@param callback -- callback function that runs when a transition to a new state happens. takes in the new_state_context as a parameter.

	@return ()
]=]
function StateManager:onTransition(fn: (new_state_context: Context<unknown>) -> ()): Disconnect
	local ls: { OnTransitionListener<unknown> } = self.on_trans_ls
	ls[#ls + 1] = fn
	local running: boolean = true
	return function()
		if not running then
			return
		end
		running = false
		for i = #ls, 1, -1 do
			if ls[i] == fn then
				ls[i] = ls[#ls]
				ls[#ls] = nil
				break
			end
		end
	end
end

return StateManager
