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

local datastore = datastore("network.yin");
local empty_node = {
	text = function() return nil ; end
};

function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'ping' then
		nlog(NLOG_DEBUG, "Going to ping");
		local hostname = (find_node_name_ns(root, 'host', self.model_ns) or empty_node):text();
		if not hostname then
			return nil, {
				msg = 'Need to know what host to ping',
				app_tag = 'data-missing',
				info_badelem = 'hostname',
				info_badns = self.model_ns
			};
		end
		local params = {};
		local timeout = find_node_name_ns(root, 'timeout', self.model_ns);
		if timeout then
			table.extend(params, {'-w', timeout:text()});
		end
		local count = find_node_name_ns(root, 'count', self.model_ns);
		if count then
			nlog(LOG_DEBUG, count:text());
			table.extend(params, {'-c', count:text()});
		end
		local isv6 = false;
		if find_node_name_ns(root, 'IPv6', self.model_ns) then
			table.extend(params, {'-6'});
			isv6 = true;
		end
		if find_node_name_ns(root, 'IPv4', self.model_ns) then
			if isv6 then
				return nil, {
					msg = "Can't prefer both IPv4 and IPv6 at the same time",
					app_tag = 'bad-element',
					info_badelem = 'IPv4',
					info_badns = self.model_ns
				};
			end
			table.extend(params, {'-4'});
		end
		table.extend(params, {hostname});
		local ecode, stdout, stderr = run_command(nil, 'ping', unpack(params));
		nlog(NLOG_DEBUG, "Ping terminated with " .. ecode);
		local result = xmlwrap.new_xml_doc('data', self.model_ns);
		local data = result:root();
		if ecode == 0 then
			data:add_child('success');
		else
			-- It terminated with error. So look to stderr and try to guess what is wrong.
			if stderr:len() ~= 0 then
				if stderr:find('bad address') then
					-- We have no data to report, nothing got resolved.
					return result:strdump();
				else
					return nil, 'Ping failed: ' .. stderr;
				end
			end -- Otherwise, we just got no answer for any of the pings, but no actual error happened.
		end
		data:add_child('address'):set_text(stdout:gmatch('PING .+ %(([^%s]+)%): %d+ data bytes')());
		local sent, received = stdout:gmatch('(%d*) packets transmitted, (%d*) packets received')();
		if sent then
			data:add_child('sent'):set_text(sent);
			data:add_child('received'):set_text(received);
		end
		local min, avg, max = stdout:gmatch('round%-trip min/avg/max = (.+)/(.+)/(.+) ms')();
		if min then
			local rtt = data:add_child('rtt');
			rtt:add_child('min'):set_text(min);
			rtt:add_child('avg'):set_text(avg);
			rtt:add_child('max'):set_text(max);
		end
		for seq, ttl, time in stdout:gmatch('%d+ bytes from .*: seq=(%d+) ttl=(%d+) time=([%d%.]+)') do
			local packet = data:add_child('packet');
			packet:add_child('seq'):set_text(seq);
			packet:add_child('ttl'):set_text(ttl);
			packet:add_child('time'):set_text(time);
		end
		return result:strdump();
	elseif rpc == 'check' then
		local ecode, stdout, stderr = run_command(nil, 'nuci-helper-checkconn');
	--[[	Don't check for ecode ‒ it may kill itself sometimes, which is bad, but we
		still want the results it got so far
		if ecode ~= 0 then
			return nil, "Couldn't check network: " .. stderr;
		end
	]]
		function feature_present(name)
			return stdout:match(name);
		end
		local result = xmlwrap.new_xml_doc('connection', self.model_ns);
		local connection = result:root();
		function check_feature(name, tag)
			local text = 'false';
			if feature_present(name) then
				text = 'true';
			end
			connection:add_child(tag):set_text(text);
		end
		check_feature('V4', 'IPv4-connectivity');
		check_feature('V6', 'IPv6-connectivity');
		check_feature('GATE4', 'IPv4-gateway');
		check_feature('GATE6', 'IPv6-gateway');
		check_feature('DNS', 'DNS');
		local dnssec = 'false';
		if not feature_present('BADSEC') then
			dnssec = 'true';
		end
		connection:add_child('DNSSEC'):set_text(dnssec);
		return result:strdump();
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
