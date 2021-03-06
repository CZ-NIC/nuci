--[[
Copyright 2013, CZ.NIC z.s.p.o. (http://www.nic.cz/)

This file is part of NUCI configuration server.

NUCI is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

NUCI is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with NUCI.  If not, see <http://www.gnu.org/licenses/>.
]]

require ("nutils");

local hooks_success, hooks_failure, uci_dirty;

function commit_mark_dirty(uci_name)
	uci_dirty[uci_name] = true;
end

--[[
Schedule a function to be called as part of the success
commit chain. Higher priority sooner. The commit chain
is called after each successful operation. Returning error
from the hook may abort the chain and cause returning an
error to the client. In such case, the failure hook is started.
]]
function commit_hook_success(action, priority)
	table.insert(hooks_success, {
		action = action,
		priority = priority or 0
	});
end

--[[
Schedule a function to be called as part of the rollback
chain. Higher priority sooner. Note that the chain may be
called even after part of the success commit chain was called.

Returning error from within a failure hook will likely abort the
program.
]]
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
It can contain either false (disable restart for that config) or name
of the daemon to restart, or a table, in which case it is custom command
to use.
]]
local restart_overrides = {
	system = 'sysntpd',
	dhcp = 'dnsmasq',
	wireless = {'wifi'},
	-- Some things in the network config need full restart instead of reload
	-- Reload dnsmasq after network change, as it may be sitting on the old network setup
	network = {'sh', '-c', '/etc/init.d/network restart && /etc/init.d/dnsmasq reload'},
	-- Clean cache of resolver by explicit restart instead of reload.
	-- The resolving might change and the old values could be wrong.
	resolver = {'/etc/init.d/resolver', 'restart'}
};

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
				to_restart[override] = override;
			end
		else
			to_restart[config] = true;
		end
	end
	-- Go through them and restart them one by one, if they exist.
	for daemon in pairs(to_restart) do
		if type(daemon) == 'table' then
			nlog(NLOG_DEBUG, "Post-commit action: ", daemon[1]);
			local result, stdout, stderr = run_command(nil, unpack(daemon));
			if result ~= 0 then
				error("Failed a post-commit action: " .. daemon[1]);
			end
		else
			local file = "/etc/init.d/" .. daemon;
			nlog(NLOG_DEBUG, "Restarting ", daemon);
			if file_executable(file) then
				local result, stdout, stderr = run_command(nil, file, 'reload');
				if result ~= 0 then
					error("Daemon " .. daemon .. " failed to restart: " .. stderr);
				end
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
