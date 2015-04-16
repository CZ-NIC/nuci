--[[
Copyright 2013-2015, CZ.NIC z.s.p.o. (http://www.nic.cz/)

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

local board;

local networks = {
	Turris = {
		eth0 = 'unused',
		eth1 = 'internal',
		eth2 = 'external'
	},
	['TP-Link TL-WDR4900 v1'] = {
		eth0 = 'internal'
	}
};
networks['rtrs01'] = networks['Turris'];
networks['rtrs02'] = networks['Turris'];
networks['turris'] = networks['Turris'];

local switch_ports = {
	Turris = {
		switch0 = {
			[0] = 'internal',
			[1] = 'external',
			[2] = 'external',
			[3] = 'external',
			[4] = 'external',
			[5] = 'external',
			[6] = 'internal'
		}
	},
	['TP-Link TL-WDR4900 v1'] = {
		switch0 = {
			[0] = 'internal',
			[1] = 'external',
			[2] = 'external',
			[3] = 'external',
			[4] = 'external',
			[5] = 'external',
			[6] = 'unused'
		}
	}
};
switch_ports['rtrs01'] = switch_ports['Turris'];
switch_ports['rtrs02'] = switch_ports['Turris'];
switch_ports['turris'] = switch_ports['Turris'];

-- Implementations of "procedure" command-type
local function cmd_interfaces(node)
	local network_defs = {};
	if board and networks[board] then
		network_defs = networks[board];
	end
	local is_address = function(s)
		local available_types = { "inet", "inet6", "link" };
		for _,t in pairs(available_types) do
			if s:match(t) then
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
			for ifline in lines(stdout) do
				asc_ifaces_node:add_child('interface'):set_text(ifline);
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
		local mode = stdout:match("type%s+(%S+)");
		local channel, frequency = stdout:match("channel%s+(%S+)%s+%((%S+).*%)");

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
		for line in lines(stdout) do
			local station = line:match("Station%s+(%S+)");
			if station then -- new client start
				client_node = clients_node:add_child('client');
				client_node:add_child('mac'):set_text(station);
			else -- client's data
				local data;
				data = line:match("signal:%s+(%S+)");
				if data then client_node:add_child('signal'):set_text(data); end

				data = line:match("tx bitrate:%s+(%S+)");
				if data then client_node:add_child('tx-bitrate'):set_text(data); end

				data = line:match("rx bitrate:%s+(%S+)");
				if data then client_node:add_child('rx-bitrate'):set_text(data); end
			end
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
	for line in lines(stdout) do
		-- Check if it is first line defining new interface
		local num, name = line:match('(%d*):%s+([^:@]*)[:@]');
		if num and name then
			iface_node = node:add_child('interface');
			iface_node:add_child('name'):set_text(name);
			iface_node:add_child('use'):set_text(network_defs[name] or 'unknown');
			if line:find('state UP') then
				iface_node:add_child('up');
			elseif line:find('state DOWN') then
				iface_node:add_child('down');
			end
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
			local addr_type, addr = line:match('%s+(%S+)%s+(%S+)');
				if addr_type and addr then
					if is_address(addr_type) then
						local addr_node = iface_node:add_child('address');
						addr_node:add_child('type'):set_text(addr_type);
						addr_node:add_child('address'):set_text(addr);
					end
				end
				-- else: do nothing, it's some uninteresting garbage
		end
	end

	return true;
end

function switches(node)
	local ecode, stdout, stderr = run_command(nil, 'swconfig', 'list');
	if ecode ~= 0 then
		return nil, 'swconfig failed: ' .. stderr;
	end

	local switch_defs = {};
	if board and switch_ports[board] then
		switch_defs = switch_ports[board];
	end

	for line in lines(stdout) do
		local name = line:match('Found: ([^ ]*) -');
		if not name then
			return nil, 'Malformed output from swconfig: ' .. line;
		end
		local port_defs = switch_defs[name] or {};
		local sw = node:add_child('switch');
		sw:add_child('name'):set_text(name);
		local ecode_switch, stdout_switch, stderr_switch = run_command(nil, 'swconfig', 'dev', name, 'show');
		if ecode_switch ~= 0 then
			return nil, "Can't get info about switch " .. name;
		end
		for line_switch in lines(stdout_switch) do
			if line_switch:find('link: port:') then
				local port, link = line_switch:match('link: port:(%d*) link:([^ ]*)');
				local port_node = sw:add_child('port');
				port_node:add_child('number'):set_text(port);
				port_node:add_child('link'):set_text(link);
				port_node:add_child('use'):set_text(port_defs[port+0] or 'unknown');
				local speed = line_switch:match('speed:(%d*)');
				if speed then
					port_node:add_child('speed'):set_text(speed);
				end
			end
		end
	end
	return true;
end

-- Current timestamp in UTC
timestamp = 0;

-- Define the commands and their mapping to XML elements.
local commands = {
	{
		element = 'ucollect-sending',
		file = '/tmp/ucollect-status',
		postprocess = function (node, out)
			if out ~= '' then
				local data = split(out)
				node:add_child('status'):set_text(data());
				node:add_child('age'):set_text(timestamp - data());
			else
				node:add_child('status'):set_text('offline');
			end
		end,
		nofile_ok = true
	},
	{
		element = 'firewall-sending',
		file = '/tmp/firewall-turris-status.txt',
		postprocess = function (node, out)
			if out ~= '' then
				for line in lines(out) do
					local working = line:match('turris firewall working: (%S*)');
					if working then
						if working == 'yes' then
							working = 'online';
						elseif working == 'no' then
							working = 'broken';
						end
						node:add_child('status'):set_text(working);
					end
					local ts = line:match('last working timestamp: (%d*)');
					if ts then
						node:add_child('age'):set_text(timestamp - ts);
					end
				end
			else
				node:add_child('status'):set_text('offline');
			end
		end,
		nofile_ok = true
	},
	{
		element = 'board-name',
		file = '/tmp/sysinfo/board_name',
		postprocess = function (node, out)
			board = trimr(out);
			node:set_text(board);
		end
	},
	{
		element = 'model',
		file = '/tmp/sysinfo/model',
		postprocess = function (node, out)
			node:set_text(trimr(out));
		end
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
		element = 'turris-os-version',
		file = '/etc/turris-version'
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
		element = "temperature",
		cmd = "thermometer",
		postprocess = function (node, out)
			for where, temp in out:gmatch('(%w+):%s(%d+)') do
				node:add_child(where:lower()):set_text(xml_escape(temp));
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
	},
	--[[
	Disabled due to being very slow and slowing down the whole <get/>. We don't use it just now,
	so we can speed up the foris wizard.
	{
		element = "switches",
		procedure = switches
	},
	]]
	{
		element = "wireless-cards",
		cmd = 'iw',
		params = {'list'},
		postprocess = function (node, out)
			local phy;
			local parse = false;
			for line in lines(out) do
				local name = line:match('^Wiphy (.*)');
				if name then
					phy = node:add_child('phy');
					phy:add_child('name'):set_text(name);
					parse = false;
				elseif line:match('Frequencies:$') then
					parse = true;
				elseif line:match(':$') then
					parse = false;
				elseif parse then
					local freq, channel, power = line:match('^%s*%* (%d+) MHz %[(%d+)%] %((.-)%)');
					local radar = line:match('radar detection');
					if freq then
						local chandef = phy:add_child('channel');
						chandef:add_child('number'):set_text(channel);
						chandef:add_child('frequency'):set_text(freq);
						if radar then
							chandef:add_child('radar')
						end
						local power_value = power:match('([%d%.]+) dBm');
						if power_value then
							chandef:add_child('max-power'):set_text(power_value);
						else
							chandef:add_child('disabled');
						end
					end
				end
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
		elseif command.nofile_ok then
			return '';
		else
			return nil, errstr;
		end
	end
	if command.uci then
		data = uci.cursor().get_all(command.uci)
		for i, selector in ipairs(command.selector or {}) do
			local found = false;
			for name, item in pairs(data or {}) do
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

	local code, utc_time, stderr = run_command(nil, 'date', '-Iseconds', '-u', '+%s');
	if code ~= 0 then
		return nil, "Could not determine UTC time: " .. stderr;
	end
	timestamp = trimr(utc_time);

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
				reset_uci_cursor();
				return nil, err;
			end
		else
			local out, err = get_output(command);
			--test errors
			if not out then
				reset_uci_cursor();
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
	reset_uci_cursor();
	return doc:strdump();
end

register_datastore_provider(datastore)
