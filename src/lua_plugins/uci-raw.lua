require("uci")
require("datastore")
require("nutils")

local uci_datastore = datastore("uci-raw.yin")

local function sort_by_index(input)
	-- Sort by the value in ".index"
	local result = {}
	for _, value in pairs(input) do
		table.insert(result, value);
	end
	table.sort(result, function (a, b)
		if a[".type"] == b[".type"] then
			return a[".index"] < b[".index"];
		else
			return a[".type"] < b[".type"];
		end
	end);
	return result;
end

local function list_item(name, value)
	local result;
	if type(value) == 'table' then
		result = '<list><name>' .. xml_escape(name) .. '</name>';
		for index, value in ipairs(value) do
			result = result .. '<value><index>' .. xml_escape(index) .. '</index><content>' .. xml_escape(value) .. '</content></value>';
		end
		result = result .. '</list>';
	else
		result = '<option><name>' .. xml_escape(name) .. '</name><value>' .. xml_escape(value) .. '</value></option>';
	end
	return result;
end

local function list_section(section)
	local result = "<section><name>" .. xml_escape(section[".name"]) .. "</name><type>" .. xml_escape(section[".type"]) .. "</type>";
	if section[".anonymous"] then
		result = result .. "<anonymous/>";
	end
	for name, value in pairs(section) do
		if not name:find("^%.") then -- Stuff starting with dot is special info, not values
			result = result .. list_item(name, value);
		end
	end
	result = result .. '</section>';
	return result;
end

local function list_config(cursor, config)
	local result = '<config><name>' .. xml_escape(config) .. '</name>';
	cdata = cursor.get_all(config);
	-- Sort the data according to their index
	-- (this might not preserve the order between types, but at least
	-- preserves the relative order inside one type).
	cdata = sort_by_index(cdata);
	for _, section in ipairs(cdata) do
		result = result .. list_section(section);
	end
	result = result .. '</config>';
	return result;
end

function uci_datastore:get_config()
	local cursor = uci.cursor();
	local result = [[<uci xmlns='http://www.nic.cz/ns/router/uci-raw'>]];
	for _, config in ipairs(uci_list_configs()) do
		result = result .. list_config(cursor, config);
	end
	result = result .. '</uci>';
	return result;
end

function uci_datastore:subnode_value(node, name)
	local node = find_node_name_ns(node, name, self.ns);
	if node then
		return node:text();
	end
end

function uci_datastore:node_path(node)
	local result = {};
	local name = node:name();
	while node do
		local name = node:name();
		result[name] = node;
		result[name .. '_name'] = subnode_value(node, 'name');
		node = node:parent();
	end
	return name, result;
end

function uci_datastore:get_delayed_list(cursor, path)
	-- Create the hierarchy
	local config, section, name = path.config_name, path.section_name, path.list_name;
	if not self.delayed_lists[config] then
		self.delayed_lists[config] = {};
	end
	if not self.delayed_lists[config][section] then
		self.delayed_lists[config][section] = {};
	end
	local list = self.delayed_lists[config][section][name] or cursor:get(config, section, name) or {};
	self.delayed_lists[config][section][name] = list;
	return list;
end

function uci_datastore:set_empty_delayed_list(cursor, path)
	-- Just to make the whole hierarchy
	self:get_delayed_list(cursor, path)
	local config, section, name = path.config_name, path.section_name, path.list_name;
	self.delayed_lists[config][section][name] = {};
end

function uci_datastore:perform_create(cursor, op)
	local node = op.command_node;
	local name, path = self:node_path(node);
	if name == 'config' then
		return {
			msg="Creating whole configs is not possible, you have to live with what there is already",
			tag="operation not supported",
			info_badelem=name,
			info_badns=self.ns
		};
	elseif name == 'section' then
		-- TODO: Create the section and iterate through the rest of XML to fill it up.
	elseif name == 'option' then
		local value = self:subnode_value(node, 'value');
		cursor:set(path.config_name, path.section_name, path.option_name, value);
	elseif name == 'list' then
		-- Create an empty list here (or overwrite one)
		self:set_empty_delayed_list(cursor, path);
		for child in node:iterate() do
			local name, ns = child:name();
			if name == 'value' and ns == self.ns then
				local result = uci_datastore:perform_create(cursor, {command_node=child});
				if result then
					return result;
				end
			elseif ns then
				if ns == self.ns then
					return {
						msg="Unknown or misplaced element " .. name .. " in list",
						tag="unknown element",
						info_badelem=name,
						info_badns=ns
					};
				else
					return {
						msg="Foreign namespace " .. ns .. " with element " .. name .. " in list",
						tag="unknown namespace",
						info_badelem=name,
						info_badns=ns
					};
				end
				-- Else these are stuff like empty text nodes and comments
			end
		end
	elseif name == 'value' then
		if path.option then
			-- Handle the whole option at once.
			return uci_datastore:perform_create(cursor, {command_node=node});
		else -- One value inside the list
			-- Get the delayed list. It'll be put into UCI at the end of the processing.
			local list = self:get_delayed_list(cursor, path.config_name, path.section_name, path.list_name);
			-- Get the index and value
			local index = self:subnode_value(node, 'index');
			local value = self:subnode_value(node, 'value');
			-- And store it there.
			list[index] = value;
		end
	elseif name == 'content' or name == 'type' or name == 'index' or name == 'name' then
		error("Trying to create " .. name .. ", but it should have already existed and such thing should not pass the conversion");
	elseif name == 'anonymous' then
		return {
			msg="Can't anonymise a section, remove and readd",
			tag="operation not supported",
			info_badelem=name,
			info_badns=self.ns
		};
	else
		-- This can get here in case there's a create on a section and strange stuff inside.
		return {
			msg="Unknow element to create: " .. name,
			tag="unknown element",
			info_badelem=name,
			info_badns=self.ns
		};
	end
	-- This config was changed, needs to be commited afterwards
	self.changed[path.config_name] = true;
end

function uci_datastore:perform_remove(cursor, op)
	local node = op.config_node;
	local name, path = self:node_path(node);
	if name == 'config' then
		return {
			msg="Deleting (or replacing) whole configs is not possible",
			tag="operation not supported",
			info_badelem=name,
			info_badns=self.ns
		};
	elseif name == 'section' then
		cursor:delete(path.config_name, path.section_name);
	elseif name == 'option' then
		if op.note == 'replace' then
			-- If we replace it, the create part will just overwrite it.
			return;
		end
		cursor:delete(path.config_name, path.section_name, path.option_name);
	elseif name == 'list' then
		-- Delete the list by making an empty one there. The thing at the bottom will remove it.
		self.set_empty_delayed_list(cursor, path);
	elseif name == 'value' then
		if path.option then
			if op.note ~= 'replace' then
				return {
					msg="The value element is mandatory",
					tag="missing element",
					info_badelem='value',
					info_badns=self.ns
				};
			end
			-- If it is replace, that's OK, it'll just be rewritten in next op.
		else
			-- Get the delayed list. It'll be put into UCI at the end of the processing.
			local list = self:get_delayed_list(cursor, path.config_name, path.section_name, path.list_name);
			-- Get the index and delete the value from the list.
			local index = self:subnode_value(node, 'index');
			list[index] = nil;
		end
	elseif name == 'content' or name == 'type' or name == 'index' or name == 'name' then
		if op.note == 'replace' then
			if name == 'content' then
				return; -- That's OK, we'll replace it in the next op.
			end
			-- TODO: implement?
			return {
				msg="Can't replace " .. name .. ", replace the whole owner",
				tag="operation not supported",
				bad_elemname=name,
				bad_elemns=self.ns
			};
		else
			return {
				msg="Can't delete mandatory node " .. name,
				tag="data missing",
				bad_elemname=name,
				bad_elemns=self.ns
			};
		end
	elseif name == 'anonymous' then
		-- TODO: Implement?
		return {
			msg="Can't un-anonymise a section. That is possible, but makes little sense and it is hard to do.",
			tag="operation not supported",
			bad_elemname="anonymous",
			bad_elemns=self.ns
		};
	else
		-- Can Not Happen: we're deleting stuff from our config, we must know anything there might be.
		error("Unknown element to delete: " .. name);
	end
	-- This config was changed, needs to be commited afterwards
	self.changed[path.config_name] = true;
end

function uci_datastore:set_config(config, defop, deferr)
	local ops, err = self:edit_config_ops(config, defop, deferr);
	if err then
		return err;
	else
		local cursor = uci.cursor();
		-- Prepare data structures.
		self.changed = {};
		self.delayed_lists = {}
		-- Perform all the operations.
		for _, op in ipairs(ops) do
			local err;
			if op.op == 'add-tree' then
				err = self:perform_create(cursor, op);
			elseif op.op == 'remove-tree' then
				err = self:perform_remove(cursor, op);
			end
			-- Ignore all enter and leave operations.
			if err then
				return err;
			end;
		end
		-- Push in all the delayed lists we have.
		for config_name, config in pairs(self.delayed_lists) do
			for section_name, section in pairs(config) do
				for name, list in pairs(config) do
					if next(list) then
						--[[
						Sort the table according to the numeric value of index, but using
						integral keys without gaps only.

						Create an auxiliary table with tuples first. Sort that one and
						extract the values only afterwards.
						]]
						local tuples = {};
						for index, val in pairs(list) do
							table.insert(tuples, {index=index, val=val});
						end
						list = {}
						table.sort(tuples, function (a, b) return a.index < b.index end);
						for _, val in pairs(list) do
							table.insert(list, val.val);
						end
						-- Push the sorted one in.
						cursor:set(config_name, section_name, name, list);
					else
						-- Empty list just doesn't exist.
						cursor:delete(config_name, section_name, name);
					end
				end
			end
		end
		-- FIXME: Support some kind of callback that happens after everything is successfully prepared, to commit
		for config in pairs(self.changed) do
			cursor:commit(config)
		end
		self.changed = nil;
		self.delayed_lists = nil;
	end
end

register_datastore_provider(uci_datastore)
