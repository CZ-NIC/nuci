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
		return nil, "Cannot connect to socket: " .. err;
	end

	result, err, nsent = s:send(text);
	if result == nil then
		nlog(NLOG_ERROR, "Cannot send over socket: " .. err);
		return nil, "Cannot send over socket: " .. err;
	end

	result = s:receive("*l");
	if string.sub(result, 0, 13) ~= "0001 SECURRIS" then
		nlog(NLOG_ERROR, "Securris not ready.");
		return nil, "Securris not ready.";
	end

	local output = ""
	while true do
		result = s:receive("*l");
		if result == nil then
			nlog(NLOG_ERROR, "Cannot receive over socket.");
			s:close();
			return nil, "Cannot receive over socket.";
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
	end
	if zone == nil or zone == '' then
		nlog(NLOG_ERROR, "Missing 'zone-name' parameter");
		return nil, {
			msg = "Missing <zone-name> parameter.",
			app_tag = "data-missing",
			info_badelem = "zone-name",
			info_badns = self.model_ns
		};
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
			nlog(NLOG_ERROR, "Invalid 'status' parameter");
			return nil, {
				msg = "Invalid <status> parameter.",
				app_tag = "data-invalid",
				info_badelem = "status",
				info_badns = self.model_ns
			};
		end
	end
	nlog(NLOG_INFO, "Arming zone " .. zone .. " " .. status);
	local response = send_to_socket(cmd .. " " .. zone .. "\n");
	
	if string.sub(response, 0, 2) == "OK" then
		return "<ok/>";
	else
		nlog(NLOG_ERROR, "RPC \"" .. cmd .. " " .. zone .. "\" failed: " .. response);
		return nil, {
			msg = "RPC \"" .. cmd .. " " .. zone .. "\" failed: " .. response,
			app_tag = "securris-error",
		};
	end
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
			nlog(NLOG_ERROR, "Invalid 'sound' parameter");
			return nil, {
				msg = "Invalid <sound> parameter.",
				app_tag = "data-invalid",
				info_badelem = "sound",
				info_badns = self.model_ns
			};
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
				nlog(NLOG_ERROR, "Invalid 'sound-type' parameter");
				return nil, {
					msg = "Invalid <sound-type> parameter.",
					app_tag = "data-invalid",
					info_badelem = "sound-type",
					info_badns = self.model_ns
				};
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
			nlog(NLOG_ERROR, "Invalid 'led' parameter");
			return nil, {
				msg = "Invalid <led> parameter.",
				app_tag = "data-invalid",
				info_badelem = "led",
				info_badns = self.model_ns
			};
		end
	end
	nlog(NLOG_INFO, "Setting LED " .. led);
	local response3 = send_to_socket("led " .. led .. "\n");
	
	if string.sub(response1, 0, 2) == "OK" then
		if string.sub(response2, 0, 2) == "OK" then
			if string.sub(response3, 0, 2) == "OK" then
				return "<ok/>";
			else
				nlog(NLOG_ERROR, "RPC \"led " .. led .. "\" failed: " .. response3);
				return nil, {
					msg = "RPC \"led " .. led .. "\" failed: " .. response3,
					app_tag = "securris-error",
				};
			end
		else
			nlog(NLOG_ERROR, "RPC \"beep <some param>\" failed: " .. response2);
			return nil, {
				msg = "RPC \"beep <some param>\" failed: " .. response2,
				app_tag = "securris-error",
			};
		end
	else
		nlog(NLOG_ERROR, "RPC \"siren <some param>\" failed: " .. response1);
		return nil, {
			msg = "RPC \"siren <some param>\" failed: " .. response1,
			app_tag = "securris-error",
		};
	end
end

function datastore:pair(root)
	local node = find_node_name_ns(root, 'transmit', self.model_ns);
	local transmit = "on";
	if node then
		local text = node:text();
		if text == 'false' then
			transmit = "off";
		elseif text == 'true' then
			transmit = "on";
		else
			nlog(NLOG_ERROR, "Invalid 'transmit' parameter");
			return nil, {
				msg = "Invalid <transmit> parameter.",
				app_tag = "data-invalid",
				info_badelem = "transmit",
				info_badns = self.model_ns
			};
		end
	end
	nlog(NLOG_INFO, "Setting pairing mode");
	local response = send_to_socket("pair " .. transmit .. "\n");

	if string.sub(response, 0, 2) == "OK" then
		return "<ok/>";
	else
		nlog(NLOG_ERROR, "RPC \"pair " .. transmit .. "\" failed: " .. response);
		return nil, {
			msg = "RPC \"pair " .. transmit .. "\" failed: " .. response,
			app_tag = "data-invalid",
			info_badelem = "status",
			info_badns = self.model_ns
		};
	end
end

function datastore:dump(root)
	local node = find_node_name_ns(root, 'format', self.model_ns);
	local dump_format = "";
	if node then
		local text = node:text();
		if text == 'text' then
			dump_format = "";
		elseif text == 'json' then
			dump_format = "json";
		elseif text == 'xml' then
			dump_format = "xml";
		else
			nlog(NLOG_ERROR, "Invalid 'format' parameter");
			return nil, {
				msg = "Invalid <format> parameter.",
				app_tag = "data-invalid",
				info_badelem = "format",
				info_badns = self.model_ns
			};
		end
	end
	nlog(NLOG_INFO, "Dumping " .. dump_format);
	
	if dump_format == "xml" then
		return send_to_socket("dump " .. dump_format .. "\n");
	else
		local str = send_to_socket("dump " .. dump_format .. "\n");
		str = string.gsub(str, "'", "&apos;");
		str = string.gsub(str, "<", "&lt;");
		str = string.gsub(str, ">", "&gt;");
		str = string.gsub(str, "&", "&amp;");
		str = string.gsub(str, '"', "&quot;");
		return "<content xmlns='http://www.nic.cz/ns/router/securris'>" .. str .. "</content>";
	end
end

function datastore:relay(root)
	local node = find_node_name_ns(root, 'status', self.model_ns);
	local status = "off";
	if node then
		local text = node:text();
		if text == 'true' then
			status = "on";
		elseif text == 'false' then
			status = "off";
		else
			nlog(NLOG_ERROR, "Invalid 'status' parameter");
			return nil, {
				msg = "Invalid <status> parameter.",
				app_tag = "data-invalid",
				info_badelem = "status",
				info_badns = self.model_ns
			};
		end
	end
	nlog(NLOG_INFO, "Setting relay " .. status);
	local response = send_to_socket("relay " .. status .. "\n");
	
	if string.sub(response, 0, 2) == "OK" then
		return "<ok/>";
	else
		nlog(NLOG_ERROR, "RPC \"relay " .. status .. "\" failed: " .. response);
		return nil, {
			msg = "RPC \"relay " .. status .. "\" failed: " .. response,
			app_tag = "data-invalid",
			info_badelem = "status",
			info_badns = self.model_ns
		};
	end
end

function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'zone-arming' then
		return datastore:zone_arming(root);
	elseif rpc == 'siren' then
		return datastore:siren(root);
	elseif rpc == 'pair' then
		return datastore:pair(root);
	elseif rpc == 'dump' then
		return datastore:dump(root);
	elseif rpc == 'relay' then
		return datastore:relay(root);
	else
		return nil, {
			msg = "Command '" .. rpc .. "' not known",
			app_tag = 'unknown-element',
			info_badelem = rpc,
			info_badns = self.model_ns
		};
	end
end

function datastore:get()
	return send_to_socket("dump xml");
end

register_datastore_provider(datastore);
