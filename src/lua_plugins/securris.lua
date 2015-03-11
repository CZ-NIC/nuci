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
	-- TODO
end

-- RPC je jméno toho rpc, data je ten kus XML jako string.
function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'pair' then
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
		return "<ok/>"; -- String s XML. Mohl bych i sestavit, ale u takto jednoduchého je to jedno.
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
