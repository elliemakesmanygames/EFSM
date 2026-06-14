-- CALLBACK-ASSOCIATED TYPES
type Disconnect = () -> ()
type OnTransitionListener = (v: Context<unknown>) -> ()

-- FUNCTION TYPES
type State<T = unknown> = {
	name: string,
	fn: (data: T, cleanup: (cleanupFn: () -> ()) -> ()) -> ()
}

-- TABLE TYPES
type Context<T> = {
	data: T,
	_active: boolean,
}

type StateManagerConfig<T> = {
	_currentData: T,
	_currentState: State<T>,
}

type StateManagerInfo<T> = StateManagerConfig<T> & {
	_runningThread: thread?,
	_context: Context<T>?,
	_cleanup: () -> ()?,
	_on_trans_ls: { OnTransitionListener },
}

type StateManager<T> = StateManagerInfo<T> & {
	__index: StateManager<T>,

	init: (StateManagerConfig: StateManagerConfig<T>) -> StateManager<T>,

	transition: (self: StateManager<T>, state_name: string) -> (),
	destroy: (self: StateManager<T>) -> (),

	onTransition: (self: StateManager<T>, callback: (new_state_context: Context<T>) -> ()) -> Disconnect,
}

local StateManager = {}
StateManager.__index = StateManager

-- LISTENER FUNCS
local function FireListener(listeners: { OnTransitionListener }, context: Context<unknown>): ()
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
function StateManager.init(StateConfig: StateManagerConfig<unknown>): StateManager<unknown>
	local self = setmetatable({}, StateManager) :: StateManagerInfo<unknown>
	self._runningThread = nil
	self._currentState = StateConfig._currentState
	self._context = { _data = StateConfig._currentData, _active = false }
	self._cleanup = nil

	self._on_trans_ls = {}
	return self
end

--[=[
    @function transition
    @within StateManager

    @param state_name -- target state_name to change to
	@param target_data? -- main data to modify (Position, Rotation, etc.), could be nil.
	@return ()
]=]
function StateManager:transition(state: State<unknown>): ()
	if not self._context._active then
		error("cannot transition to new state: concurrency control.")
	end

	if self._cleanup then
		self._cleanup()
		self._cleanup = nil
	end

	if self._runningThread then
		self._context._active = true
		task.cancel(self._runningThread)
		self._runningThread = nil
	end

	local function cleanup(fn: () -> ()): ()
		self._cleanup = fn
	end

	self._currentState = state
	self._context._active = false
	self._runningThread = task.spawn(state.fn, self._context._data, cleanup)

	FireListener(self._on_trans_ls, self._context)
end

--[=[
    @function destroy
    @within StateManager

	@return ()
]=]
function StateManager:destroy(): ()
	if self._cleanup then
        self._cleanup()
        self._cleanup = nil
    end

	if self._runningThread then
		task.cancel(self._runningThread)
	end

	self._runningThread = nil
	self._currentState = nil
	self._context = nil
end

--[=[
    @function onTransition
    @within StateManager

	@param callback -- callback function that runs when a transition to a new state happens. takes in the new_state_context as a parameter.

	@return ()
]=]
function StateManager:onTransition(fn: (new_state_context: Context<unknown>) -> ()): Disconnect
	local ls: { OnTransitionListener } = self._on_trans_ls
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

return StateManager :: StateManager<unknown>
