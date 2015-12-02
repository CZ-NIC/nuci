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

local datastore = datastore("nuci-tls.yin");
local dir = '/usr/share/nuci/tls/ca/';
local token_dir = '/usr/share/nuci/tls/clients/';
local script_dir = '/usr/share/nuci/tls/';
local index_file = dir .. 'index.txt';
local states = {
	V = 'active',
	E = 'expired',
	R = 'revoked'
};

function datastore:get()
	local xml = xmlwrap.new_xml_doc('ca', self.model_ns);
	local root = xml:root();
	local index, err = io.open(index_file);
	if not index then
		nlog(NLOG_ERROR, "The nuci TLS CA is not ready: " .. err);
		return '';
	end
	local first = true;
	local now = os.date("%y%m%d%H%M%S"); -- It is so ordered that we can compare just as a number. We don't care about the time zone, the error would be small enough to not matter.
	for line in index:lines() do
		if first then -- Skip over the first certificate, which is the server
			first = false;
		else
			local status, date, name = line:match('([VER])%s+(%d+)Z%s+%d+%s+%w+%s+/CN=(.*)');
			if status then
				if now > date then
					-- Handle the case when the expiration passed, but the index haven't been updated yet
					status = 'E';
				end
				local node = root:add_child('client');
				node:add_child('name'):set_text(name);
				node:add_child('status'):set_text(states[status]);
			else
				return nil, "Bad line in " .. index_file .. ": " .. line;
			end
		end
	end
	return xml:strdump();
end

local function check_name(name)
	return name:match('^[a-zA-Z0-9_.-]+$');
end

function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();
	if rpc == 'get-token' then
		local node = find_node_name_ns(root, 'name', self.model_ns);
		if not node then
			return nil, {
				msg = "Missing <name> parameter, which token do you want?",
				app_tag = 'data-missing',
				info_badelem = 'name',
				info_badns = self.model_ns
			};
		end
		local name = node:text();
		if not check_name(name) then
			return nil, {
				msg = "Invalid client name: " .. name,
				app_tag = 'invalid-value',
				info_badelem = 'name',
				info_badns = self.model_ns
			};
		end
		local filename = token_dir .. name .. '.token';
		local file = io.open(filename);
		if not file then
			return nil, {
				msg = "Client doesn't exist: " .. name,
				app_tag = 'invalid-value',
				info_badelem = 'name',
				info_badns = self.model_ns
			};
		end
		local result = xmlwrap.new_xml_doc('token', self.model_ns);
		result:root():set_text(file:read("*a"));
		return result:strdump();
	elseif rpc == 'new-client' then
		local node = find_node_name_ns(root, 'name', self.model_ns);
		if not node then
			return nil, {
				msg = "Missing <name> parameter, which token do you want?",
				app_tag = 'data-missing',
				info_badelem = 'name',
				info_badns = self.model_ns
			};
		end
		local name = node:text();
		if not check_name(name) then
			return nil, {
				msg = "Invalid client name: " .. name,
				app_tag = 'invalid-value',
				info_badelem = 'name',
				info_badns = self.model_ns
			};
		end
		local filename = token_dir .. name .. '.token';
		local file = io.open(filename);
		if file then
			return nil, {
				msg = "Client already exists: " .. name,
				app_tag = 'invalid-value',
				info_badelem = 'name',
				info_badns = self.model_ns
			};
		end

		local command = { script_dir .. 'new_client', '-l'};
		-- add background flag if set
		if find_node_name_ns(root, 'background', self.model_ns) then
			table.insert(command, '-b')
		end
		table.insert(command, name);

		local ecode, stdout, stderr = run_command(nil, unpack(command));
		if ecode ~= 0 then
			return nil, "Failed to create new client: " .. stderr;
		end
		return '<ok/>';
	elseif rpc == 'revoke-client' then
		return nil, {
			msg = "Sorry, you will be able to revoke that client in future release",
			app_tag = 'operation-not-supported',
			info_badelem = rpc,
			info_badns = self.model_ns
		};
	elseif rpc == 'reset-CA' then
		local ecode, stdout, stderr = run_command(nil, script_dir .. 'new_ca', '-f');
		if ecode ~= 0 then
			return "Failed to create new CA: " .. stderr;
		end
		local ecode, stdout, stderr = run_command(nil, '/etc/init.d/nuci-tls', 'restart');
		if ecode ~= 0 then
			return "Failed to restart nuci-tls for new CA: " .. stderr;
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
