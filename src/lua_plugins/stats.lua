--[[
Copyright 2013, CZ.NIC

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

require("uci");
require("datastore");
require("nutils");

-- Implementations of "procedure" command-type
local function cmd_interfaces(node)
	local get_next_line = function(content, position)
		local s, e = content:find('\n', position, true);
		if not s then
			return nil, nil;
		end
		local line, position_out;
		line = content:sub(position, s - 1);
		position_out = e + 1;

		return line, position_out;
	end
	local is_address = function(s)
		local available_types = { "inet", "inet6", "link" };
		for _,t in pairs(available_types) do
			if s:gmatch(t)() then
				return true;
			end
		end
		return false;
	end
	-- Return? True = is bridge; False = is not bridge; nil = error
	local process_bridge = function (node, iface)
		local file, errstr = io.open("/sys/devices/virtual/net/" .. iface .. "/bridge/bridge_id");
		local bridge_id = nil;
		if file then
			for line in file:lines() do
				bridge_id = line;
				break; --get only one line
			end
			file:close();
		end

		if bridge_id then
			local stp_state;
			-- OK, this device id bridge, get more info
			file, errstr = io.open("/sys/devices/virtual/net/" .. iface .. "/bridge/stp_state");
			if file then
				for line in file:lines() do
					stp_state = line;
					break; --get only one line
				end
				file:close();
			else
				return nil, "Cannot open file stp_state."
			end

			ecode, stdout, stderr = run_command(nil, "ls", "/sys/devices/virtual/net/" .. iface .. "/brif");
			if ecode ~= 0 then
				return nil, "Cannot list interfaces";
			end

			node:add_child('id'):set_text(bridge_id);
			node:add_child('stp-state'):set_text(stp_state);
			local asc_ifaces_node = node:add_child('associated-interfaces');
			local ifline;
			local ifposition = 1;
			ifline, ifposition = get_next_line(stdout, ifposition);
			while ifline do
				asc_ifaces_node:add_child('interface'):set_text(ifline);
				ifline, ifposition = get_next_line(stdout, ifposition);
			end


		else
			node:delete();
			return false;
		end

		return true;
	end

	-- Return? True = is wireless; False = is not wireless; nil = error
	local process_wireless = function (node, iface)
		local ecode, stdout, stderr = run_command(nil, "iw", "dev", iface, "info");
		if ecode ~= 0 then
			node:delete();
			return false;
		end

		-- For debug purposes
		--stdout =
				--[[Interface wan0
					ifindex 7
					wdev 0x2
					addr d4:ca:6d:92:bd:d7
					type AP
					wiphy 0
					channel 11 (2462 MHz) HT20]];
		local mode = stdout:gmatch("type%s+(%S+)")();
		local channel, frequency = stdout:gmatch("channel%s+(%S+)%s+%((%S+).*%)")();

		if mode then node:add_child('mode'):set_text(mode); end
		if channel then node:add_child('channel'):set_text(channel); end
		if frequency then node:add_child('frequency'):set_text(frequency); end

		ecode, stdout, stderr = run_command(nil, "iw", "dev", iface, "station", "dump");
		if ecode ~= 0 then
			return nil, "Cannot get clients info";
		end

		-- For debug purposes
		--stdout =
			--[[Station 40:b0:fa:82:f5:ed (on wlan0)
				inactive time:	2900 ms
				rx bytes:	27907
				rx packets:	247
				tx bytes:	12323
				tx packets:	77
				tx retries:	1
				tx failed:	0
				signal:  	-23 [-29, -24] dBm
				signal avg:	-24 [-32, -25] dBm
				tx bitrate:	58.5 MBit/s MCS 6
				rx bitrate:	6.0 MBit/s
				authorized:	yes
				authenticated:	yes
				preamble:	short
				WMM/WME:	yes
				MFP:		no
				TDLS peer:	no
		Station 00:27:10:e8:22:3c (on wlan0)
				inactive time:	23890 ms
				rx bytes:	82219
				rx packets:	2680
				tx bytes:	36339
				tx packets:	217
				tx retries:	9
				tx failed:	0
				signal:  	-27 [-27, -35] dBm
				signal avg:	-30 [-30, -39] dBm
				tx bitrate:	6.5 MBit/s MCS 0
				rx bitrate:	19.5 MBit/s MCS 2
				authorized:	yes
				authenticated:	yes
				preamble:	short
				WMM/WME:	yes
				MFP:		no
				TDLS peer:	no]];

		local clients_node = node:add_child('clients'); -- node for new clients
		local client_node; -- node for current client
		local line;
		local position = 1;
		line, position = get_next_line(stdout, position);
		while line do
			local station = line:gmatch("Station%s+(%S+)")();
			if station then -- new client start
				client_node = clients_node:add_child('client');
				client_node:add_child('mac'):set_text(station);
			else -- client's data
				local data;
				data = line:gmatch("signal:%s+(%S+)")();
				if data then client_node:add_child('signal'):set_text(data); end

				data = line:gmatch("tx bitrate:%s+(%S+)")();
				if data then client_node:add_child('tx-bitrate'):set_text(data); end

				data = line:gmatch("rx bitrate:%s+(%S+)")();
				if data then client_node:add_child('rx-bitrate'):set_text(data); end
			end

			line, position = get_next_line(stdout, position);
		end

		return true;
	end

	-- Run first command
	local ecode, stdout, stderr = run_command(nil, 'ip', 'addr', 'show');
	if ecode ~= 0 then
		return nil, "Command to get interfaces failed with code " .. ecode .. " and stderr " .. stderr;
	end

	--Parse ip output
	local iface_node; --node for new interface and its address list
	local line;
	local position = 1;
	line, position = get_next_line(stdout, position);
	while line do
		-- Check if it is first line defining new interface
		local num, name = line:gmatch('(%d*):%s+([^:@]*)[:@]')();
		if num and name then
			iface_node = node:add_child('interface');
			iface_node:add_child('name'):set_text(name);
			-- Try bridge
			local brstatus, err = process_bridge(iface_node:add_child('bridge'), name);
			if brstatus == nil then
				return nil, err;
			end
			-- Try wireless
			local wrstatus, err = process_wireless(iface_node:add_child('wireless'), name);
			if wrstatus == nil then
				return nil, err;
			end
		else
			-- OK, it isn't first line of new interface
			-- Try to get address
			local addr_type, addr = line:gmatch('%s+(%S+)%s+(%S+)')();
				if addr_type and addr then
					if is_address(addr_type) then
						local addr_node = iface_node:add_child('address');
						addr_node:add_child('type'):set_text(addr_type);
						addr_node:add_child('address'):set_text(addr);
					end
				end
				-- else: do nothing, it's some uninteresting garbage
		end
		-------------------------------------------------------
		line, position = get_next_line(stdout, position);
	end

	return true;
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
	{
		element = "firmware-version",
		shell = "cat /etc/openwrt_release  | grep DISTRIB_DESCRIPTION | cut -d '\"' -f 2"
	},
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
		procedure = cmd_interfaces
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
	}
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
	doc = xmlwrap.new_xml_doc(self.model_name, self.model_ns);
	root = doc:root();

	--run single commands
	for i, command in ipairs(commands) do
		node = root:add_child(command.element);
		--run
		if command.procedure then
			local out, err = command.procedure(node);
			if not out then
				return nil, err;
			end
		else
			local out, err = get_output(command);
			--test errors
			if not out then
				return nil, err;
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
	end

	return doc:strdump();
end

register_datastore_provider(datastore)
