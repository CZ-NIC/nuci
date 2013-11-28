--[[
Copyright 2013, CZ.NIC

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

local function handle_node(node, desc)
	if desc.children then
		for i, child in ipairs(desc.children) do
			local sub = node:add_child(child.name, child.namespace);
			handle_node(sub, child);
		end
	end
	if desc.text then
		node:set_text(desc.text);
	end
end

function xmltree_dump(tree)
	local doc = xmlwrap.new_xml_doc(tree.name, tree.namespace);
	local node = doc:root();
	handle_node(node, tree);
	return doc;
end
