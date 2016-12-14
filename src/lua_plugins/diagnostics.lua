--[[
Copyright 2016, CZ.NIC z.s.p.o. (http://www.nic.cz/)

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

local datastore = datastore("diagnostics.yin");

local binary_path = "/usr/share/diagnostics/diagnostics.sh";

function get_diag_id(root, ns)
		-- get the generated diagnostics
		local diag_id_node = find_node_name_ns(root, 'diag-id', ns);
		if diag_id_node then
			return diag_id_node:text();
		else
			return nil, {
				msg = "Missing the mandatory <diag-id> parameter.",
				app_tag = 'data-missing',
				info_badelem = 'diag-id',
				info_badns = self.model_ns
			};
		end
end

function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'prepare' then
		-- generate the diagnostics

		local modules = {};
		for mid in root:iterate() do
			local name, ns = mid:name();
			if name == 'module' and ns == self.model_ns then
				local module = mid:text();
				table.insert(modules, module);
			end
		end

		-- get random id
		math.randomseed(os.time());
		local diag_id = os.date("%Y-%m-%d") .. '_' .. string.format("%08x", math.random(1, 0x7fffffff));
		local diag_path = '/tmp/diagnostics-' .. diag_id .. '.out';
		local ecode, stdout, stderr = run_command(nil, binary_path, '-b', '-o', diag_path, unpack(modules));
		if ecode ~= 0 then
			return nil, "Error performing diagnostics: " .. stderr;
		end

		local new_xml = xmlwrap.new_xml_doc(self.model_name, self.model_ns);
		local new_root = new_xml:root();
		local node = new_root:add_child("diag-id");
		node:set_text(diag_id);
		return new_xml:strdump();

	elseif rpc == 'get-prepared' then
		-- get the generated diagnostics

		local diag_id, err = get_diag_id(root, self.model_ns);
		if not diag_id then
			return nil, err;
		end
		local diag_path = '/tmp/diagnostics-' .. diag_id .. '.out';

		-- response xml
		local new_xml = xmlwrap.new_xml_doc(self.model_name, self.model_ns);
		local new_root = new_xml:root();
		local status_node = new_root:add_child("status");

		-- first try to read directory.preparing
		local file = io.open(diag_path);
		if file then
			local data = file:read("*all");
			local ecode, stdout, stderr = run_command(data, 'gzip')
			if ecode ~= 0 then
				return nil, "Error diagnostics packing diagnostics: " .. stderr;
			end
			ecode, stdout, stderr = run_command(stdout, 'base64')
			if ecode ~= 0 then
				return nil, "Error diagnostics base64 encoding failed: " .. stderr;
			end
			new_root:add_child("output"):set_text(stdout);
			status_node:set_text('ready');
		else
			if io.open(diag_path .. '.preparing') then
				status_node:set_text('preparing');
			else
				status_node:set_text('missing');
			end
		end

		return new_xml:strdump();

	elseif rpc == 'list-modules' then
		-- list all modules

		-- response xml
		local new_xml = xmlwrap.new_xml_doc(self.model_name, self.model_ns);
		local new_root = new_xml:root();

		local ecode, stdout, stderr = run_command(nil, "sh", "-c", "ls -1 /usr/share/diagnostics/modules/*.module");
		if ecode ~= 0 then
			return nil, "Error getting diagnostics modules: " .. stderr;
		end
		for line in lines(stdout) do
			new_root:add_child("module"):set_text(line:match("\/([^\/]+).module$"));
		end

		return new_xml:strdump();

	elseif rpc == 'list-diagnostics' then
		-- list generated diagnostics

		-- response xml
		local new_xml = xmlwrap.new_xml_doc(self.model_name, self.model_ns);
		local new_root = new_xml:root();

		local ecode, stdout, stderr = run_command(nil, "sh", "-c", "ls -1 /tmp/diagnostics-*");
		if ecode == 0 then
			-- some diagnostics found
			for line in lines(stdout) do
				local status = nil;
				local match = line:match("diagnostics%-(.*)%.out%.preparing$");
				if match then
					status = 'preparing';
				else
					match = line:match("diagnostics%-(.*)%.out$");
					if match then
						status = 'ready';
					end
				end
				if match then
					-- insert node
					local node = new_root:add_child("diagnostic");
					node:add_child("diag-id"):set_text(match);
					node:add_child("status"):set_text(status);
				end
			end
		end

		return new_xml:strdump();

	elseif rpc == 'remove-diagnostic' then
		-- remove store diagnostic
		local diag_id, err = get_diag_id(root, self.model_ns);
		if not diag_id then
			return nil, err;
		end

		local ecode, _, stderr = run_command(nil, "rm", "/tmp/diagnostics-" .. diag_id .. ".out");
		if ecode ~= 0 then
			return nil, "Error deleting diagnostics: " .. stderr;
		end
		return '<ok/>';
	end

end


register_datastore_provider(datastore);
