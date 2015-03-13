--[[
Copyright 2014, CZ.NIC z.s.p.o. (http://www.nic.cz/)

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
require("nutils"); -- viz src/lua_lib

local datastore = datastore("securris.yin");

function send_to_socket(text)
	a = require("socket.unix");
	s = a();

	server_connection, err = s:connect("/tmp/securris.sock");
	if server_connection == nil then
		io.write("Cannot connect to socket.\n");
		return nil;
	end

	result, err, nsent = s:send(text);
	if result == nil then
		io.write("Cannot send over socket.\n");
		return nil;
	end

	while true do
		result = s:receive("*l");
		if result == nil then
			io.write("Cannot receive over socket.\n");
			break;
		end

		if result == "0000 " then
			break;
		end

		str = string.sub(result, 6);
		io.write(str .. "\n");
	end

	s:close();
end

function zone_arming()
	local node = find_node_name_ns(root, 'zone-name', self.model_ns);
	local zone = nil;
	if node then
		zone = node:text();
	else
		return "<error/>";
	end
	node = find_node_name_ns(root, 'status', self.model_ns);
	local status = "true";
	if node then
		local text = node:text();
		if text == 'true' then
			status = "true";
		elseif text == 'false' then
			status = "false";
		end
	else
		return "<error/>";
	end
	nlog(NLOG_INFO, "Arming zone " .. zone .. " " .. status);
	send_to_socket("zone " .. zone .. " " .. status .. "\n");
end

function siren()
	local node = find_node_name_ns(root, 'sound', self.model_ns);
	local sound = "false";
	if node then
		sound = node:text();
	end
	nlog(NLOG_INFO, "Turning siren " .. sound );
	send_to_socket("siren " .. sound .. "\n");

	node = find_node_name_ns(root, 'sound-type', self.model_ns);
	local sound_type = "off";
	local text = "continuous"
	if node then
		text = node:text();
		if text == 'fast-beeps' then
			sound_type = "fast";
		elseif text == 'slow-beeps' then
			sound_type = "slow";
		end
	end
	nlog(NLOG_INFO, "Setting beeps to" .. text );
	send_to_socket("beep " .. sound_type .. "\n");

	node = find_node_name_ns(root, 'led', self.model_ns);
	local led = "false";
	if node then
		led = node:text();
	end
	nlog(NLOG_INFO, "Setting LED " .. led);
	send_to_socket("led " .. led .. "\n");
end

function pair()
	local node = find_node_name_ns(root, 'transmit', self.model_ns);
	local transmit = "on";
	if node then
		local text = node:text();
		if text == 'false' or text == '0' then
			transmit = "off";
		end
		-- TODO: Ošetření chyb
	end
	nlog(NLOG_INFO, "Setting pairing mode");
	send_to_socket("pair " .. transmit .. "\n");
end

function dump()
	local node = find_node_name_ns(root, 'format', self.model_ns);
	local dump_format = "xml";
	if node then
		local text = node:text();
		if text == 'text' then
			dump_format = "";
		elseif text == 'json' then
			dump_format = "json";
		end
	end
	nlog(NLOG_INFO, "Dumping " .. dump_format);
	send_to_socket("dump " .. dump_format .. "\n");
end

function relay()
	local node = find_node_name_ns(root, 'status', self.model_ns);
	local status = "false";
	if node then
		local text = node:text();
		if text == 'true' then
			status = "true";
		end
	end
	nlog(NLOG_INFO, "Setting relay " .. status);
	send_to_socket("relay " .. status .. "\n");
end

-- RPC je jméno toho rpc, data je ten kus XML jako string.
function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'zone-arming' then
		zone_arming();
		return "<ok/>";
	elseif rpc == 'siren' then
		siren();
		return "<ok/>";
	elseif rpc == 'pair' then
		pair();
		return "<ok/>"; -- String s XML. Mohl bych i sestavit, ale u takto jednoduchého je to jedno.
	elseif rpc == 'dump' then
		dump();
		return "<ok/>";
	elseif rpc == 'relay' then
		relay();
		return "<ok/>";
	else
		-- Vracím strukturu popisující chybu
		return nil, {
			msg = "Command '" .. rpc .. "' not known",
			app_tag = 'unknown-element',
			info_badelem = rpc,
			info_badns = self.model_ns
		};
	end
end

function datastore:get()
	-- Nevím, jak bude vypadat ten status, takže jen nástřel, aby tu něco bylo.
	local xml = xmlwrap.new_xml_doc('status', self.model_ns);
	local root = xml:root();
	root:add_child('alarm'):add_text('666'); -- Alarm na device 666.
	return xml:strdump();
end

-- Přidání do nuci
register_datastore_provider(datastore);
