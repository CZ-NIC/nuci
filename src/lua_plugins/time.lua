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

require("datastore");
require("nutils");

local datastore = datastore("time.yin");

function datastore:get()
	local xml = xmlwrap.new_xml_doc(self.model_name, self.model_ns);
	local root = xml:root();

	local timezone;
	get_uci_cursor():foreach("system", "system", function(s)
		timezone = s.timezone;
	end);

	local code, local_time, stderr = run_command(nil, 'date', '-Iseconds');
	if code ~= 0 then
		return nil, "Could not determine local time: " .. stderr;
	end
	local code, utc_time, stderr = run_command(nil, 'date', '-Iseconds', '-u');
	if code ~= 0 then
		return nil, "Could not determine UTC time: " .. stderr;
	end

	root:add_child('timezone'):set_text(timezone);
	root:add_child('local'):set_text(trimr(local_time));
	root:add_child('utc'):set_text(trimr(utc_time));

	return xml:strdump();
end

local function systohc()
	local code, stdout, stderr = run_command(nil, 'sh', '-c', 'if [ -e /dev/rtc0 ] ; then hwclock -u -w -f /dev/rtc0 ; fi');
	if code == 0 then
		return '<ok/>';
	else
		return nil, "Failed to store the time to hardware clock: " .. stderr;
	end
end

function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'set' then
		nlog(NLOG_DEBUG, "Going to set date/time manually");
		local time_node = find_node_name_ns(root, 'time', self.model_ns);
		if not time_node then
			return nil, {
				msg = "Missing the <time> parameter, don't know what to set the time to",
				app_tag = 'data-missing',
				info_badelem = 'time',
				info_badns = self.model_ns
			};
		end
		local year, month, day, hour, minute, second = string.match(time_node:text(), '(....)-(..)-(..)T(..):(..):(..)');
		if not year then
			return nil, {
				msg = "Malformed <time> parameter (tip: it should look something like 1970-01-01T00:00:00+0100)",
				app_tag = 'invalid-value',
				info_badelem = 'time',
				info_badns = self.model_ns
			};
		end
		local utc = find_node_name_ns(root, 'utc', self.model_ns);
		local target_time = year .. '.' .. month .. '.' .. day .. '-' .. hour .. ':' .. minute .. ':' .. second;
		local code, stdout, stderr;
		if utc then
			nlog(NLOG_TRACE, "UTC: ", target_time);
			code, stdout, stderr = run_command(nil, 'date', '-u', '-s', target_time);
		else
			nlog(NLOG_TRACE, "local: ", target_time);
			code, stdout, stderr = run_command(nil, 'date', '-s', target_time);
		end
		if code ~= 0 then
			return nil, "Failed to set time: " .. stderr;
		end
		return systohc();
	elseif rpc == 'ntp' then
		nlog(NLOG_DEBUG, "Going to run NTP");
		local servers = {};
		for node in root:iterate() do
			local name, ns = node:name();
			-- Extract list of servers from parameters
			if name == 'server' and ns == self.model_ns then
				table.insert(servers, node:text());
			end
		end
		-- If none are given, use the ones from config
		if #servers == 0 then
			servers = get_uci_cursor():get("system", "ntp", "server");
		end
		-- Do we have any?
		if not servers or #servers == 0 then
			return nil, {
				msg = "Could not determine any NTP servers",
				app_tag = 'data-missing',
				info_badelem = 'server',
				info_badns = self.model_ns
			};
		end
		-- Construct the param table
		local server_params = {};
		for _, server in ipairs(servers) do
			nlog(NLOG_TRACE, "NTP server: ", server);
			table.extend(server_params, {'-p', server});
		end
		-- Run the ntp
		local code, stdout, stderr = run_command(nil, 'ntpd', '-n', '-q', unpack(server_params));
		if code == 0 then
			return systohc();
		end
	else
		return nil, {
			msg = "Command '" .. rpc .. "' not known",
			app_tag = 'unknown-element',
			info_badelem = rpc,
			info_badns = self.model_ns
		};
	end
end

register_datastore_provider(datastore);
