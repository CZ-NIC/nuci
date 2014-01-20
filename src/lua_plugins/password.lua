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

local datastore = datastore("password.yin");

function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'set' then
		nlog(NLOG_DEBUG, "Setting password");
		local password_node = find_node_name_ns(root, 'password', self.model_ns);
		if not password_node then
			return nil, {
				msg = "Missing the <password> parameter, don't know what to use as password",
				app_tag = 'data-missing',
				info_badelem = 'password',
				info_badns = self.model_ns
			};
		end
		local user_node = find_node_name_ns(root, 'user', self.model_ns);
		if not user_node then
			return nil, {
				msg = "Missing the <user> parameter, don't know whose password to set",
				app_tag = 'data-missing',
				info_badelem = 'user',
				info_badns = self.model_ns
			};
		end
		local input = password_node:text() .. "\n";
		input = input .. input;
		local ecode, stdout, stderr = run_command(input, 'passwd', user_node:text());
		if ecode ~= 0 then
			return nil, "Failed to set password: " .. stderr;
		end
		return '<ok/>';
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
