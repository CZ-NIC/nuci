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

local dir = "/var/log/turris-pcap/";
local description = "/tmp/rule-description.txt";

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
					description = ""
				};
			elseif desc_match then
				if current_rule then
					rules[current_rule].description = rules[current_rule].description .. desc_match .. ' ';
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
	--[[
	local ok, dirs = pcall(function() return dir_content(dir) end);
	if not ok then
		nlog(NLOG_WARN, "Directory " .. dir .. " can't be read, it probably doesn't exist: " .. dirs);
	end
	]]
	local names = {};
	local i = 1;
	for name in pairs(rules) do
		names[i] = name;
		i = i + 1;
	end
	table.sort(names);
	local xml = xmlwrap.new_xml_doc('firewall', self.model_ns);
	local root = xml:root();
	for i, name in ipairs(names) do
		local rule = root:add_child('rule');
		rule:add_child('id'):set_text(name);
		if rules[name].description then
			rule:add_child('description'):set_text(trimr(rules[name].description));
		end
		-- TODO: The files
	end
	return xml:strdump();
end

register_datastore_provider(datastore);
