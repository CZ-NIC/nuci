require("uci");
require("datastore");

-- trim whitespace from right end of string
local function trimr(s)
	return s:find'^%s*$' and '' or s:match'^(.*%S)'
end

-- Define the commands and their mapping to XML elements.
local commands = {
	{
		element = "board-name",
		shell = "dmesg | grep -i machine | sed 's/is /|/g' | cut -d '|' -f 2"
	},
	{
		element = "hostname",
		uci = "system",
		selector = { { tp = "system" }, { name = "hostname" } }
	},
	{
		element = "kernel-version",
		cmd = "uname",
		params = {'-r'}
	},
	--[[{
		element = "firmware-version",
		shell = "cat /etc/openwrt_release  | grep DISTRIB_DESCRIPTION | cut -d '\"' -f 2"
	},]]
	{
		element = "local-time",
		cmd = "date",
		params = {'+%s'}
	},
	{
		element = "load-average",
		file = "/proc/loadavg",
		postprocess = function (node, out)
			local times = { 1, 5, 15 };
			local index, time = next(times);
			for l in out:gmatch('([^ ]+)') do
				node:add_child('avg-'..time):set_text(xml_escape(l));
				index, time = next(times, index);
				if not index then
					break;
				end
			end
		end
	},
	{
		element = 'interfaces',
		cmd = 'ifconfig',
		params = {'-a'},
		postprocess = function (node, out)
			-- First put everything to a table. There might be multiple interfaces with the same name
			-- (because of sub-interfaces).
			local interfaces = {}
			local position = 1;
			local interface_node;
			local x = 1;
			local mac = nil; --temporaly solution
			local s, e = out:find('\n\n', position, true);
			while s do
				local interface = out:sub(position, s - 1);
				--local name, mac = interface:gmatch('(%S+)%s+[^:]*:%S+%s+%S+%s+(%S+)')();
				local name = interface:gmatch('([^:]*):')();
				local addresses = interfaces[name] or {}
				--for kind, addr in interface:gmatch('%s+(%S+)%s+[^:]*:(%S+)') do
				for kind, addr in interface:gmatch('        (%S+)%s+(%S+)') do
					if kind == 'HWaddr' then
						kind = 'ether';
					end
					if kind == 'inet' or kind == 'inet6' or kind == 'ether' then
						addr = addr:gsub('addr:', '');
						addresses[x] = { kind, addr, mac };
						x = x + 1;
					end
				end
				-- TODO: Check if it is bridge or wireless and get the throughput
				interfaces[name] = addresses;
				position = e + 1;
				s, e = out:find('\n\n', position, true);
			end
			for name, addresses in pairs(interfaces) do
				interface_node = node:add_child('interface');
				interface_node:add_child('name'):set_text(name);
				for _,addr in pairs(addresses) do
					interface_node:add_child('address'):set_attribute('type', addr[1]):set_text(addr[2]);
					if addr[3] and #addr[3] == 17 then
						interface_node:add_child('mac-address'):set_text(addr[3]);
					end
				end
			end
		end
	},
	{
		element = "uptime",
		file = "/proc/uptime",
		postprocess = function (node, out)
			node:set_text(xml_escape((string.gsub(out, ' .*', ''))));
		end
	},
	{
		element = "meminfo",
		file = "/proc/meminfo",
		postprocess = function (node, out)
			for name, value in out:gmatch('(%w+):%s+(%d+)[^\n]*\n') do
				node:add_child(name):set_text(xml_escape(value));
			end
		end
	},
	{
		element = "bridges",
		shell = "brctl show | tail -n +2",
		postprocess = function (node, out)
			for line in split(out, "\n") do
				node:add_child('bridge'):set_text(line);
			end
		end
	}
	-- TODO: Other commands too
};

local function get_output(command)
	if command.shell then
		local ecode, out, err;
		-- Run it as a command in shell
		ecode, out, err = run_command(nil, 'sh', '-c', command.shell);

		if ecode ~= 0 then
			return nil, "Command to get " .. command.element .. " failed with code " .. ecode .. " and stderr " .. err;
		end
		return out;
	end
	if command.cmd then
		local ecode, out, err;
		local params = command.params or {};
		-- Run it as a command
		ecode, out, err = run_command(nil, command.cmd, unpack(params));

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

local datastore = datastore('stats.yin')

function datastore:get()
	local doc, root, node;

	--prepare XML subtree
	doc = xmlwrap.new_xml_doc("stats", "http://www.nic.cz/ns/router/stats");
	root = doc:root();

	--run single commands
	for i, command in ipairs(commands) do
		node = root:add_child(command.element);
		--run
		local out, err = get_output(command);
		--test errors
		if not out then
			return nil, err
		end
		--run postproccess function
		if command.postprocess then
			command.postprocess(node, out);
		else
			--clean output
			out = trimr(out);
			node:set_text(xml_escape(out));
		end
	end

	return doc:strdump();
end

register_datastore_provider(datastore)
