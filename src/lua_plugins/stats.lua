require("uci");

-- trim whitespace from right end of string
local function trimr(s)
	return s:find'^%s*$' and '' or s:match'^(.*%S)'
end

-- Define the commands and their mapping to XML elements.
local commands = {
	{ cmd = "dmesg | grep -i machine | sed 's/is /|/g' | cut -d '|' -f 2", shell = true, element = "boardName" },
	{ uci = "system", selector = { { tp = "system" }, { name = "hostname" } }, element = "hostname" },
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
	{ cmd = 'ifconfig', params = {'-a'}, element = 'interfaces', postprocess = function (out)
		-- First put everything to a table. There might be multiple interfaces with the same name
		-- (because of sub-interfaces).
		local interfaces = {}
		local position = 1;
		local s, e = out:find('\n\n', position, true);
		while s do
			local interface = out:sub(position, s - 1);
			local name = interface:gmatch('([^:]*):')();
			print(name);
			local addresses = interfaces[name] or ''
			for kind, addr in interface:gmatch('        (%S+)%s+(%S+)') do
				if kind == 'HWaddr' then
					kind = 'ether';
				end
				if kind == 'inet' or kind == 'inet6' or kind == 'ether' then
					addr = addr:gsub('addr:', '');
					addresses = addresses .. '<address type="' .. kind .. '">' .. xml_escape(addr) .. '</address>';
				end
			end
			-- TODO: Check if it is bridge or wireless and get the throughput
			interfaces[name] = addresses
			position = e + 1;
			s, e = out:find('\n\n', position, true);
			print(name .. ': ' .. interfaces[name]);
		end
		print(interfaces);
		print(interfaces['eth0']);
		print(next(interfaces));
		local result = '';
		for name, addresses in pairs(interfaces) do
			result = result .. '<interface><name>' .. xml_escape(name) .. '</name>' .. addresses .. '</interface>';
		end
		return result;
	end},
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
			return nil, "Command to get " .. command.element .. " failed with code " .. ecode .. " and stderr " .. err;
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
	if command.uci then
		data = uci.cursor().get_all(command.uci)
		for i, selector in ipairs(command.selector or {}) do
			local found = false;
			for name, item in pairs(data) do
				local selected = true;
				if selector.name then
					selected = selected and (selector.name == name);
				end
				if selector.tp then
					selected = selected and (selector.tp == item[".type"]);
				end
				if selected then
					data = item;
					found = true;
					break;
				end
			end
			if not found then
				return nil, "UCI info for " .. command.element .. " not found";
			end
		end
		return data;
	end
	return nil, "Confused: no cmd, file nor uci for " .. command.element;
end

register_stat_generator("stats.yin", function ()
	output = "<stats xmlns='http://www.nic.cz/ns/router/stats'>";
	for i, command in ipairs(commands) do
		local out, err = get_output(command);
		if not out then
			return nil, err
		end
		out = trimr(out)
		local postprocess = command.postprocess or xml_escape

		out = postprocess(out)
		output = output .. "<" .. command.element .. ">" .. out .. "</" .. command.element .. ">";
	end;
	output = output .. "</stats>";
	return output;
end)
