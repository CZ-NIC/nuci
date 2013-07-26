require ("uci")

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

end

local function restart_daemons()

end

local function rollback_uci()

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
