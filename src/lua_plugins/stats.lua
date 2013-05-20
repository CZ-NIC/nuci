-- Define the commands and their mapping to XML elements.
local commands = {
	{ cmd = "dmesg | grep -i machine | sed 's/is /|/g' | cut -d '|' -f 2", shell = true, element = "boardName" },
	-- TODO: Use UCI directly
	--{ cmd = "uci get system.@system[0].hostname", shell = true, element = "hostname" },
	{ cmd = "uname -r", shell = true, element = "kernelVersion" },
	--{ cmd = "cat /etc/openwrt_release  | grep DISTRIB_DESCRIPTION | cut -d '\"' -f 2", shell = true, element = "firmwareVersion" },
	{ cmd = "date", shell = false, element = "localTime" },
	{ cmd = "uptime | cut -d ':' -f 5", shell = true, element = "loadAverage" },
	{ cmd = "uptime | cut -d ':' -f 5 | cut -d ',' -f 1", shell = true, element = "currentLoad" },
	-- TODO The ifconfig stuff
	-- TODO: Read /proc/uptime directly
	{ cmd = "cat /proc/uptime | cut -d ' ' -f 1", shell = true, element = "uptime" },
	-- TODO: Read /proc/meminfo directly, and parse it somehow to XML
	{ cmd = "cat /proc/meminfo", shell = true, element = "memInfo" }
	-- TODO: Other commands too
};

register_stat_generator("stats.yin", function ()
	output = "<stats xmlns='http://www.nic.cz/ns/router/stats'>";
	for i, command in ipairs(commands) do
		local ecode, out, err;
		if command.shell then
			ecode, out, err = run_command(nil, 'sh', '-c', command.cmd);
		else
			ecode, out, err = run_command(nil, command.cmd);
		end
		if ecode ~= 0 then
			return nil, "Command to get " .. command.element .. "failed with: " .. err;
		end
		-- TODO: Trim output
		-- TODO: Escape the output
		output = output .. "<" .. command.element .. ">" .. out .. "</" .. command.element .. ">";
	end;
	output = output .. "</stats>";
	print(output);
	return output;
end)
