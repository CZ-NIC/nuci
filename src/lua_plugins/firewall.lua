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

local datastore = datastore("firewall.yin");

local dir = "/var/log/turris-pcap";
local description = "/tmp/rule-description.txt";

function is_pcap(fileinfo)
	local name = fileinfo.filename:match("^.*/(.-)%.pcap$");
	local primary;
	if name then
		primary = true
	else
		name = fileinfo.filename:match("^.*/(.-)%.pcap%.%d+$");
		primary = false;
	end
	if name and fileinfo.type == 'f' then
		return true, name, primary;
	else
		return nil;
	end
end

function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'pcap-delete' then
		local all = false;
		local files = {};
		local rules = {};
		for selector in root:iterate() do
			local name, ns = selector:name();
			if ns == self.model_ns then
				local text = selector:text();
				if name == 'all' then
					all = true;
				elseif name == 'rule' then
					if not text then
						return nil, {
							msg = "Missing rule name",
							app_tag = 'data-missing',
							info_badelem = 'rule',
							info_badns = self.model_ns
						};
					end
					rules[text] = true;
				elseif name == 'file' then
					if not text then
						return nil, {
							msg = "Missing file name",
							app_tag = 'data-missing',
							info_badelem = 'file',
							info_badns = self.model_ns
						};
					end
					files[text] = true;
				else
					return nil, {
						msg = "Unknown selector " .. name,
						app_tag = 'unknown-element',
						info_badelem = name,
						info_badns = self.model_ns
					};
				end
			end
		end
		local ok, pcaps = pcall(function() return dir_content(dir) end);
		local selected = {};
		if ok then
			local result_xml = xmlwrap.new_xml_doc('deleted', self.model_ns);
			local result = result_xml:root();
			local reload = false;
			for _, f in pairs(pcaps) do
				local use, name, primary = is_pcap(f);
				if use and (all or files[f.filename] or rules[name]) then
					local fxml = result:add_child('file');
					fxml:add_child('filename'):set_text(f.filename);
					fxml:add_child('rule'):set_text(name);
					fxml:add_child('size'):set_text(f.size);
					os.remove(f.filename);
					reload = reload or primary;
				end
			end
			if reload then
				local ecode, stdout, stderr = run_command(nil, '/etc/init.d/ulogd', 'reload');
				if ecode ~= 0 then
					nlog(NLOG_ERROR, "Failed to reload ulogd to update after pcap deletion: " .. ecode .. "/" .. stderr);
				end
			end
			return result_xml:strdump();
		else
			nlog(NLOG_DEBUG, "No directory, nothing to delete");
			return '<deleted xmlns="' .. self.model_ns .. '"/>';
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

function datastore:get()
	local rules = {};
	local current_rule;
	local desc, err = io.open(description);
	if desc then
		for line in desc:lines() do
			local empty_match = line:match("^%s*");
			local name_match = line:match("^(%w+)%s*");
			local desc_match = line:match("^%s+(.-)%s*$");
			if name_match then
				current_rule = name_match;
				rules[current_rule] = {
					description = {},
					files = {}
				};
			elseif desc_match then
				if current_rule then
					table.insert(rules[current_rule].description, desc_match);
				else
					nlog(NLOG_ERROR, "Description line before first name: " .. line);
				end
			elseif not empty_match then
				nlog(NLOG_ERROR, "Unmatched line " .. line);
			end
		end
	else
		nlog(NLOG_WARN, "Description file " .. description .. " couldn't be read: " .. err);
	end
	local ok, pcaps = pcall(function() return dir_content(dir) end);
	if ok then
		for _, pcap in pairs(pcaps) do
			local use, name = is_pcap(pcap);
			if use then
				if not rules[name] then
					rules[name] = {
						files = {}
					};
				end
				table.insert(rules[name].files, pcap);
			end
		end
	else
		nlog(NLOG_WARN, "Directory " .. dir .. " can't be read, it probably doesn't exist: " .. pcaps);
	end
	local names = {};
	local i = 1;
	for name in pairs(rules) do
		names[i] = name;
		i = i + 1;
	end
	table.sort(names);
	local xml = xmlwrap.new_xml_doc('firewall', self.model_ns);
	local root = xml:root();
	for _, name in ipairs(names) do
		local rule = root:add_child('rule');
		rule:add_child('id'):set_text(name);
		if rules[name].description then
			if rules[name].description[1] then
				local en = rule:add_child('description');
				en:set_attribute('xml:lang', 'en');
				en:set_text(trimr(rules[name].description[1]));
			end
			if rules[name].description[2] then
				local en = rule:add_child('description');
				en:set_attribute('xml:lang', 'cz');
				en:set_text(trimr(rules[name].description[2]));
			end
		end
		table.sort(rules[name].files, function (a, b) return a.filename < b.filename end);
		for _, file in ipairs(rules[name].files) do
			local f = rule:add_child('file');
			f:add_child('filename'):set_text(file.filename);
			f:add_child('size'):set_text(file.size);
		end
	end
	return xml:strdump();
end

register_datastore_provider(datastore);
