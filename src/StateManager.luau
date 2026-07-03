type Disconnect = () -> ()

type OnTransitionListener = (v: Context) -> ()
type Listener = OnTransitionListener

type State<T=unknown> = {
    name: string,
    action: (data: T, cleanupFn: (() -> ()) -> ()) -> (),
	guard: ((data: T) -> boolean)?
}

type Context<D=unknown,C=unknown,P=unknown> = {
	data: {[string]: D},
	currentState: State<C>?,
	previousState: State<P>?
}

type StateManager = {
	Init: (data: unknown, state: State) -> StateManager,
	Transition: (self: StateManager, state: State) -> (),
	Destroy: (self: StateManager) -> (),
	OnTransition: (self: StateManager, callback: (new_state_context: Context) -> ()) -> Disconnect
}

local StateManager = {} :: StateManager
StateManager.__index = StateManager

local function safeCB<T...>(...:T...) warn(`no function specified, resorted to default callback : {table.pack(...)}`) end

local function FireListener(listeners: { Listener }, context: Context): ()
	for i = 1, #listeners do
		listeners[i](context)
	end
end

--[=[
    @function Init
    @within StateManager

    @param data -- the initial data for the state manager.
    @param state -- the initial state for the state manager.
	@return StateManager
]=]
function StateManager.Init<T>(data: T, state: State<T>): StateManager
	local self = setmetatable({}, StateManager)
	self.runningThread = nil
	self.context = { data = data, currentState = state, previousState = nil }
	self.cleanup = nil
	self.active = false
	self.on_trans_ls = {}
	
	return self :: StateManager
end

--[=[
    @function Transition
    @within StateManager

    @param state -- the state to transition, must be of type State.
	@return ()
]=]
function StateManager:Transition(state: State): ()
	if self.active then
		error("cannot transition to new state: concurrency control.")
	end

	if self.cleanup then
		self.cleanup()
		self.cleanup = nil
	end

	if self.runningThread then
		self.active = true
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

	self.context.previousState = self.context.currentState
	self.active = false
	self.runningThread = task.spawn(executeFn, self.context.data, registerCleanup)
	self.context.currentState = state

	FireListener(self.on_trans_ls, self.context)
end

--[=[
    @function Destroy
    @within StateManager

	@return ()
]=]
function StateManager:Destroy(): ()
	if self.cleanup then
        self.cleanup()
        self.cleanup = nil
    end

	if self.runningThread then
		task.cancel(self.runningThread)
	end

	if self.context then
		self.context.currentState = nil
		self.context.previousState = nil
		self.context.data = nil
	end

	self.runningThread = nil
	self.context = nil
end

--[=[
    @function OnTransition
    @within StateManager

	@param callback -- callback function that runs when a transition to a new state happens. takes in the new_state_context as a parameter.

	@return ()
]=]
function StateManager:OnTransition(fn: (new_state_context: Context) -> ()): Disconnect
	local ls: { OnTransitionListener } = self.on_trans_ls
	ls[#ls + 1] = fn
	local running: boolean = true
	return function()
		if not running  then
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
