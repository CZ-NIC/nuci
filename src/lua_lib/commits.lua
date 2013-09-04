require ("nutils");

local hooks_success, hooks_failure, uci_dirty;

function commit_mark_dirty(uci_name)
	uci_dirty[uci_name] = true;
end

function commit_hook_success(action, priority)
	table.insert(hooks_success, {
		action = action,
		priority = priority or 0
	});
end

function commit_hook_failure(action, priority)
	table.insert(hooks_failure, {
		action = action,
		priority = priority or 0
	});
end

local function store_uci()
	local cursor = get_uci_cursor();
	for config in pairs(uci_dirty) do
		cursor:commit(config);
	end
end

-- TODO: Function to set up these from plugins
--[[
Override the default mapping config file name => daemon to restart.
It can contain either nil (disable restart for that config) or name
of the daemon to restart.
]]
local restart_overrides = {};

local function restart_daemons()
	if os.getenv("NUCI_DONT_RESTART") == "1" then
		return; -- Disable restarting stuff in tests and such
	end
	-- Which ones should be restarted?
	local to_restart = {};
	for config in pairs(uci_dirty) do
		local override = restart_overrides[config];
		if override ~= nil then
			if override then
				to_restart[override] = true;
			end
		else
			to_restart[config] = true;
		end
	end
	-- Go through them and restart them one by one, if they exist.
	for daemon in pairs(to_restart) do
		local file = "/etc/init.d/" .. daemon;
		if file_executable(file) then
			local result, stdout, stderr = run_command(nil, file, 'reload');
			if result ~= 0 then
				error("Daemon " .. daemon .. " failed to restart: " .. stderr);
			end
		end
	end
end

local function rollback_uci()
	-- By resetting the UCI cursor, we effectively forget all the changes.
	reset_uci_cursor();
end

local function cleanup()
	hooks_success = {};
	hooks_failure = {};
	uci_dirty = {};
	-- Schedule commiting UCI just after anything without priority specified.
	-- Note: It is possible to schedule something after that as well.
	commit_hook_success(store_uci, -1);
	-- And just after that, restart the relevant daemons.
	commit_hook_success(restart_daemons, -2);
	-- At the end of the success, clean up stuff.
	commit_hook_success(cleanup, -9999);
	-- Similar with failure, but the UCI rollback is done pretty soon (as it is not expected to fail).
	commit_hook_failure(rollback_uci, 9998);
	-- But even before, do a cleanup of stuff.
	commit_hook_failure(cleanup, 9999);
end

function commit_execute(success)
	-- Which hooks are we running
	local chain;
	if success then
		chain = hooks_success;
	else
		chain = hooks_failure;
	end
	-- Solt by priority (higher first)
	table.sort(chain, function (a, b) return a.priority > b.priority end);
	-- Run the hooks
	for _, hook in ipairs(chain) do
		local err = hook.action();
		if err then
			return err;
		end
	end
end

-- Prepare the chains.
cleanup();