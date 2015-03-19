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

require("datastore");
require("nutils");

local datastore = datastore("securris.yin");

function send_to_socket(text)
	a = require("socket.unix");
	s = a();

	server_connection, err = s:connect("/tmp/securris.sock");
	if server_connection == nil then
		nlog(NLOG_ERROR, "Cannot connect to socket: " .. err);
		return nil, { msg = "Cannot connect to socket: " .. err};
	end

	result, err, nsent = s:send(text);
	if result == nil then
		nlog(NLOG_ERROR, "Cannot send over socket: " .. err);
		return nil, { msg = "Cannot send over socket: " .. err };
	end

	result = s:receive("*l");
	if result ~= "0001 SECURRIS 0.1 Ready" then
		nlog(NLOG_ERROR, "Securris not ready.");
		return nil, { msg = "Securris not ready." };
	end

	local output = ""
	while true do
		result = s:receive("*l");
		if result == nil then
			nlog(NLOG_ERROR, "Cannot receive over socket.");
			s:close();
			return nil, { msg = "Cannot receive over socket." };
		end

		if result == "0000 " then
			break;
		end

		str = string.sub(result, 6);
		output = output .. str .. "\n";
	end

	s:close();
	return output;
end

function datastore:zone_arming(root)
	local node = find_node_name_ns(root, 'zone-name', self.model_ns);
	local zone = nil;
	if node then
		zone = node:text();
	else
		nlog(NLOG_ERROR, "Missing parameter");
		return "<error/>";
	end
	node = find_node_name_ns(root, 'status', self.model_ns);
	local cmd = "arm";
	local status = "true";
	if node then
		local text = node:text();
		if text == 'true' then
			cmd = "arm";
			status = "true";
		elseif text == 'false' then
			cmd = "disarm";
			status = "false";
		else
			nlog(NLOG_ERROR, "Invalid parameter");
			return "<error/>";
		end
	end
	nlog(NLOG_INFO, "Arming zone " .. zone .. " " .. status);
	local response = send_to_socket(cmd .. " " .. zone .. " " .. status .. "\n");
	return "<ok response=\"" .. response .. "\"/>";
end

function datastore:siren(root)
	local node = find_node_name_ns(root, 'sound', self.model_ns);
	local sound = "off";
	if node then
		text = node:text();
		if text == 'true' then
			sound = "on";
		elseif text == 'false' then
			sound = "off";
		else
			nlog(NLOG_ERROR, "Invalid parameter");
			return "<error/>";
		end
	end
	local response1 = "";
	local response2 = "";
	if sound == "off" then
		nlog(NLOG_INFO, "Turning sound off");
		response1 = send_to_socket("siren off\n");
		response2 = send_to_socket("beep off\n");
	else
		node = find_node_name_ns(root, 'sound-type', self.model_ns);
		if node then
			text = node:text();
			if text == 'fast-beeps' then
				response1 = send_to_socket("siren off\n");
				nlog(NLOG_INFO, "Setting beeps to fast");
				response2 = send_to_socket("beep fast\n");
			elseif text == 'slow-beeps' then
				response1 = send_to_socket("siren off\n");
				nlog(NLOG_INFO, "Setting beeps to slow");
				response2 = send_to_socket("beep slow\n");
			elseif text == 'continuous' then
			else
				nlog(NLOG_ERROR, "Invalid parameter");
				return "<error/>";
			end
		else
			nlog(NLOG_INFO, "Turning sound on");
			response1 = send_to_socket("siren on\n");
		end
	end
	
	node = find_node_name_ns(root, 'led', self.model_ns);
	local led = "off";
	if node then
		text = node:text();
		if text == 'true' then
			led = "on";
		elseif text == 'false' then
			led = "off";
		else
			nlog(NLOG_ERROR, "Invalid parameter");
			return "<error/>";
		end
	end
	nlog(NLOG_INFO, "Setting LED " .. led);
	local response3 = send_to_socket("led " .. led .. "\n");
	return "<ok response=\"" .. response1 .. ", " .. response2 .. ", " .. response3 .. "\"/>";
end

function datastore:pair(root)
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
	local response = send_to_socket("pair " .. transmit .. "\n");
	return "<ok response=\"" .. response .. "\"/>";
end

function datastore:dump(root)
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
	return send_to_socket("dump " .. dump_format .. "\n");
end

function datastore:relay(root)
	local node = find_node_name_ns(root, 'status', self.model_ns);
	local status = "false";
	if node then
		local text = node:text();
		if text == 'true' then
			status = "true";
		end
	end
	nlog(NLOG_INFO, "Setting relay " .. status);
	local response = send_to_socket("relay " .. status .. "\n");
	return "<ok response=\"" .. response .. "\"/>";
end

-- RPC je jméno toho rpc, data je ten kus XML jako string.
function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'zone-arming' then
		return datastore:zone_arming(root);
		--return "<ok/>";
	elseif rpc == 'siren' then
		return datastore:siren(root);
		--return "<ok/>";
	elseif rpc == 'pair' then
		return datastore:pair(root);
		--return "<ok/>"; -- String s XML. Mohl bych i sestavit, ale u takto jednoduchého je to jedno.
	elseif rpc == 'dump' then
		return datastore:dump(root);
		--return "<ok/>";
	elseif rpc == 'relay' then
		return datastore:relay(root);
		--return "<ok/>";
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
	--local xml = xmlwrap.new_xml_doc('status', self.model_ns);
	--local root = xml:root();
	--root:add_child('alarm'):add_text('666'); -- Alarm na device 666.
	--return xml:strdump();
	return send_to_socket("dump xml");
end

-- Přidání do nuci
register_datastore_provider(datastore);
