--[[
Copyright 2015, CZ.NIC z.s.p.o. (http://www.nic.cz/)

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

local datastore = datastore("neighbours.yin");

local function parse_dhcp_lease_line(line)
	-- put items into a table
	local items = {};
	for i in split(line) do
		table.insert(items, i);
	end

	-- check whether the table is not too small
	if #items < 4 then
		return nil
	end

	return {
		lease = items[1],
		mac = items[2],
		ip = items[3],
		hostname = items[4],
	};
end

local function parse_nf_contrack_line(line)
	local ips = {};
	for element in split(line) do
		if string.find(element, 'dst=') or string.find(element, 'src=') then
			ips[string.sub(element, string.find(element, '=') + 1)] = true;
		end
	end
	return ips;
end

local function parse_ip_neighbours_line(line)
	local items = {};

	-- put items into a table
	for i in split(line) do
		table.insert(items, i);
	end

	-- failed to parse
	if #items < 2 then
		return nil
	end

	-- get ip and nud
	local res = {};
	res.ip = items[1];
	res.nud = items[#items];

	-- remove first and last
	table.remove(items, 1);
	table.remove(items);

	-- iterate
	local last = nil;
	for i, text in pairs(items) do
		if last == "lladdr" then
			res.mac = text;
			last = nil;
		elseif last == "dev" then
			res.dev = text;
			last = nil;
		elseif text == "router" then
			res.router = true;
			last = nil;
		else
			last = text;
		end
	end

	return res;
end

function read_dhcp_lease_path()
	local cursor = get_uci_cursor();
	local leasefile = nil;
	cursor:foreach("dhcp", 'dnsmasq', function(section)
		leasefile = section.leasefile;
	end);
	reset_uci_cursor();

	if leasefile then
		return leasefile;
	else
		nlog(NLOG_ERROR, "Failed to read uci config: dhcp.dnsmasq.leasefile");
		return nil, {
			msg = "Failed to read uci!",
			tag = "operation-failed",
			type = "application",
			severity = "error",
		};
	end
end

function datastore:get()

	--prepare XML subtree
	local doc = xmlwrap.new_xml_doc(self.model_name, self.model_ns);
	local root = doc:root();


	-- Parse ip neighbour command
	local ret, out, err = run_command(nil, 'ip', 'neighbour');
	if ret ~= 0 then
		return nil, {
			msg = "Failed to trigger 'ip neighbour' command!",
			tag = "operation-failed",
			type = "application",
			severity = "error"
		};
	end
	local res = {};
	if not pcall(function ()
			for line in lines(out) do
				local data = parse_ip_neighbours_line(line);
				-- insert only if the record has a mac address
				if data.mac then
					local ip_record = {nud = data.nud, router = data.router, dev = data.dev};
					if res[data.mac] then
						res[data.mac][data.dev] = {[data.ip] = ip_record};
					else
						res[data.mac] = {};
						res[data.mac][data.dev] = {[data.ip] = ip_record};
					end
				end
			end
		end) then
		return nil, {
			msg = "Failed to parse 'ip neighbour' command!",
			tag = "operation-failed",
			type = "application",
			severity = "error"
		};
	end

	-- read lease file from uci
	local dhcp_lease_path, err = read_dhcp_lease_path();
	if not dhcp_lease_path then
		return nil, err;
	end
	-- Parse dhcp leases
	local dhcp_file = io.open(dhcp_lease_path);
	if dhcp_file then
		for line in dhcp_file:lines() do
			local data = parse_dhcp_lease_line(line);
			if not data then
				return nil, {
					msg = "Failed to parse dhcp lease file!",
					tag = "operation-failed",
					type = "application",
					severity = "error"
				};
			end
			local ip_record = {hostname = data.hostname, lease = data.lease};
			if res[data.mac] then
				-- record with this mac was found
				-- try to find a device for this combination of mac and ip
				local used_dev = nil;
				for dev, _ in pairs(res[data.mac]) do
					for k,v in pairs(res[data.mac][dev]) do
						print(k,v);
					end
					if res[data.mac][dev][data.ip] then
						used_dev = dev;
						break
					end
				end
				if used_dev then
					-- device was found -> extend existing record
					res[data.mac][used_dev][data.ip].lease = data.lease;
					res[data.mac][used_dev][data.ip].hostname = data.hostname;
				else
					-- device was not found -> add record to 'false' device
					if not res[data.mac][false] then
						res[data.mac][false] = {};
					end
					if not res[data.mac][false][data.ip] then
						res[data.mac][false][data.ip] = {};
					end
					res[data.mac][false][data.ip].lease = data.lease;
					res[data.mac][false][data.ip].hostname = data.hostname;
				end
			else
				-- mac address was not found add a whole record
				res[data.mac] = {};
				res[data.mac][false] = {[data.ip] = ip_record};
			end
		end
		dhcp_file:close();
	else
		--error dhcp might be turned off
		return nil, {
			msg = "Failed to read dhcp lease file!",
			tag = "operation-failed",
			type = "application",
			severity = "error"
		};
	end

	-- Parse connections
	local conntrack_file = io.open('/proc/net/nf_conntrack');
	local ip_counts = {};
	if conntrack_file then
		for line in conntrack_file:lines() do
			local parsed_ips = parse_nf_contrack_line(line);
			for ip, _ in pairs(parsed_ips) do
				if ip_counts[ip] then
					ip_counts[ip] = ip_counts[ip] + 1;
				else
					ip_counts[ip] = 1;
				end
			end
		end
		conntrack_file:close();
	else
		return nil, {
			msg = "Failed to read conntrack file!",
			tag = "operation-failed",
			type = "application",
			severity = "error"
		};
	end

	-- Create xml
	for mac, data in pairs(res) do
		for dev, record in pairs(data) do
			local neighbour = root:add_child('neighbour');
			neighbour:add_child('mac-address'):set_text(mac);
			if dev then
				neighbour:add_child('interface'):set_text(dev);
			end
			for ip, ip_record in pairs(record) do
				local ip_dom = neighbour:add_child('ip-address');
				ip_dom:add_child('ip'):set_text(ip);
				if ip_counts[ip] then
					ip_dom:add_child('connection-count'):set_text(ip_counts[ip]);
				else
					ip_dom:add_child('connection-count'):set_text("0");
				end
				if ip_record.nud then
					ip_dom:add_child('nud'):set_text(ip_record.nud);
				end
				if ip_record.router then
					ip_dom:add_child('router');
				end
				if ip_record.hostname and ip_record.hostname ~= "*" then
					ip_dom:add_child('hostname'):set_text(ip_record.hostname);
				end
				if ip_record.lease then
					ip_dom:add_child('dhcp-lease'):set_text(ip_record.lease);
				end
			end
		end
	end

	return doc:strdump();
end


register_datastore_provider(datastore);
