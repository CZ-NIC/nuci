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
	if result ~= "0001 SECURRIS 0.1 Ready" then
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
	else
		nlog(NLOG_ERROR, "Missing parameter");
		--[[
		FIXME:
		This is wrong.
		• You just invented an <error> element that should exist in the netconf
		  namespace. However, there's none such in this context (however, there's
		  <rpc-error>).
		• This would let the rest of nuci think the operation was successful.
		  It would continue processing as usual instead of using error handling.
		  In case of custom RPC, the difference is not large (maybe just logging), but
		  it would give the wrong example and there's a difference with <get>,
		  where it would continue running gets of other plugins.
		• Having „Missing parameter“ in log is nice, but the client of nuci
	          needs to see the actual error.

		Please provide full error description as an object, as described in
		../plugins.txt. Eg:
		return nil, {
			msg = "Missing <zone-name> parameter.",
			app_tag = "data-missing",
			info_badelem = "zone-name",
			info_badns = self.model_ns
		};
		]]
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
			-- FIXME: See above.
			return "<error/>";
		end
	end
	nlog(NLOG_INFO, "Arming zone " .. zone .. " " .. status);
	local response = send_to_socket(cmd .. " " .. zone .. " " .. status .. "\n");
	--[[
	FIXME:
	I don't think the netconf's <ok> element has a „response“ attribute.
	The proper way would be to define some other element for the response
	in our own namespace (eg. in self.model_ns, and update it in the yin file).
	]]
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
			-- FIXME: See above.
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
				-- FIXME: See above.
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
			-- FIXME: See above.
			return "<error/>";
		end
	end
	nlog(NLOG_INFO, "Setting LED " .. led);
	local response3 = send_to_socket("led " .. led .. "\n");
	-- FIXME: See above.
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
		-- TODO: Error handling
	end
	nlog(NLOG_INFO, "Setting pairing mode");
	local response = send_to_socket("pair " .. transmit .. "\n");
	-- FIXME: See above
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
	-- FIXME: See above
	return "<ok response=\"" .. response .. "\"/>";
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
