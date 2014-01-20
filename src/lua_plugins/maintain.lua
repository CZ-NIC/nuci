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
require("nutils");

local datastore = datastore("maintain.yin");

function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'reboot' then
		local ecode, stdout, stderr = run_command(nil, 'sh', '-c', '(sleep 2; reboot) >/dev/null 2>&1 </dev/null &');
		if ecode ~= 0 then
			return nil, "Failed to reboot: " .. stderr;
		end
		return '<ok/>';
	elseif rpc == 'config-backup' then
		local ecode, stdout, stderr = run_command(nil, 'nuci-helper-config-backup');
		if ecode ~= 0 then
			return nil, "Failed to create backup: " .. stderr;
		end
		return '<data xmlns="' .. self.model_ns .. '">' .. stdout .. '</data>';
	elseif rpc == 'config-restore' then
		nlog(NLOG_INFO, "Restoring config");
		local data_node = find_node_name_ns(root, 'data', self.model_ns);
		local data = data_node:text();
		local ecode, stdout, stderr = run_command(data, 'nuci-helper-config-restore');
		if ecode ~= 0 then
			return nil, "Failed to restore backup: " .. stderr;
		end
		local addr = trimr(stdout);
		nlog(NLOG_DEBUG, "New ip is ", addr);
		if addr ~= '' then
			return '<new-ip xmlns="' .. self.model_ns .. '">' .. xml_escape(addr) .. '</new-ip>';
		else
			return '<ok/>';
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
