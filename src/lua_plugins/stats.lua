
-- trim whitespace from right end of string
local function trimr(s)
	return s:find'^%s*$' and '' or s:match'^(.*%S)'
end

-- Define the commands and their mapping to XML elements.
local commands = {
	{ cmd = "dmesg | grep -i machine | sed 's/is /|/g' | cut -d '|' -f 2", shell = true, element = "boardName" },
	-- TODO: Use UCI directly
	--{ cmd = "uci get system.@system[0].hostname", shell = true, element = "hostname" },
	{ cmd = "uname", params = {'-r'}, element = "kernelVersion" },
	--{ cmd = "cat /etc/openwrt_release  | grep DISTRIB_DESCRIPTION | cut -d '\"' -f 2", shell = true, element = "firmwareVersion" },
	{ cmd = "date", params = {'+%s'}, element = "localTime" },
	{ file = "/proc/loadavg", element = "loadAverage", postprocess = function (out)
		local times = { 1, 5, 15 };
		local index, time = next(times);
		local result = '';
		for l in out:gmatch('([^ ]+)') do
			result = result .. '<avg' .. time .. '>' .. xml_escape(l) .. '</avg' .. time .. '>';
			index, time = next(times, index);
			if not index then
				break;
			end
		end
		return result
	end},
	-- TODO The ifconfig stuff
	{ file = "/proc/uptime", element = "uptime", postprocess = function (out)
		return out:gsub(' .*', '')
	end},
	{ file = "/proc/meminfo", element = "memInfo", postprocess = function (out)
		local result = '';
		for name, value in out:gmatch('(%w+):%s+(%d+)[^\n]*\n') do
			result = result .. "<" .. name .. ">" .. xml_escape(value) .. "</" .. name .. ">"
		end
		return result
	end}
	-- TODO: Other commands too
};

local function get_output(command)
	if command.cmd then
		local ecode, out, err;
		local params = command.params or {};
		-- Run it as a command
		if command.shell then
			ecode, out, err = run_command(nil, 'sh', '-c', command.cmd, unpack(params));
		else
			ecode, out, err = run_command(nil, command.cmd, unpack(params));
		end
		if ecode ~= 0 then
			return nil, "Command to get " .. command.element .. "failed with: " .. err;
		end
		return out;
	end
	if command.file then
		local file, errstr = io.open(command.file);
		if file then
			local out = '';
			for l in file:lines() do
				out = out .. l .. "\n";
			end
			file:close();
			return out;
		else
			return nil, errstr;
		end
	end
	return nil, "Confused: no cmd nor file for " .. command.element;
end

register_stat_generator("stats.yin", function ()
	output = "<stats xmlns='http://www.nic.cz/ns/router/stats'>";
	for i, command in ipairs(commands) do
		local out, err = get_output(command);
		if not out then
			return err
		end
		out = trimr(out)
		local postprocess = command.postprocess or xml_escape
		print(command.element .. ":" .. out)

		out = postprocess(out)
		output = output .. "<" .. command.element .. ">" .. out .. "</" .. command.element .. ">";
	end;
	output = output .. "</stats>";
	print(output);
	return output;
end)
