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

function read_modules(stdout, root, dir_path)
	local finished_modules = {};
	for line in lines(stdout) do
		if not line:match("\.preparing$") then
			local file = io.open(dir_path .. '/' .. line);
			if file then
				local node = root:add_child("module");
				-- module.out -> module
				node:add_child("name"):set_text(line:match("(.*)\.out"));
				node:add_child("output"):set_text(file:read("*all"));
				file:close();
				table.insert(finished_modules, line);
			end
		end
	end
	return finished_modules;
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
		local diag_id = string.format("%08x", math.random(1, 0x7fffffff));
		local diag_dir_path = '/tmp/diagnostics-' .. diag_id;
		local ecode, stdout, stderr = run_command(nil, binary_path, '-b', '-O', diag_dir_path, unpack(modules));
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
		local diag_id_node = find_node_name_ns(root, 'diag-id', self.model_ns);
		local diag_id = diag_id_node:text();
		-- trim id
		diag_id = diag_id:match("^%s*(.*[^%s])%s*$") or ""

		local diag_dir_path = '/tmp/diagnostics-' .. diag_id;

		-- response xml
		local new_xml = xmlwrap.new_xml_doc(self.model_name, self.model_ns);
		local new_root = new_xml:root();
		local status_node = new_root:add_child("status");

		-- first try to read directory.preparing
		local ecode, stdout, stderr = run_command(nil, 'ls', '-1', diag_dir_path .. '.preparing/');
		if ecode ~= 0 then
			-- try to read the final directory
			local ecode, stdout, stderr = run_command(nil, 'ls', '-1', diag_dir_path .. '/');
			if ecode ~= 0 then
				status_node:set_text('missing');
			else
				status_node:set_text('ready');
				read_modules(stdout, new_root, diag_dir_path);
				-- remove the entire directory after complete read
				run_command(nil, 'rm', '-rf', diag_dir_path);
			end
		else
			-- read the preparing directory
			status_node:set_text('preparing');
			local finished = read_modules(stdout, new_root, diag_dir_path .. '.preparing/');
			-- remove the output of processed modules from both dicrectory and directory.preparing
			for _, module_path in pairs(finished) do
				run_command(nil, 'rm', '-rf',
					diag_dir_path .. '/' .. module_path,
					diag_dir_path .. '.preparing/' .. module_path
				);
			end
		end

		return new_xml:strdump();

	elseif rpc == 'list-modules' then

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
	end

end


register_datastore_provider(datastore);
