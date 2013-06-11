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
		-- TODO: Create part of the list (delayed create)
	else
		-- This can get here in case there's a create on a section and strange stuff inside.
		return {
			msg="Unknow element to create: " .. name,
			tag="unknown element",
			info_badelem=name,
			info_badns=self.ns
		};
	end
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
		cursor:delete(path.config_name, path.section_name, path.option_name);
	elseif name == 'list' then
		-- TODO: Delete part of the list (delayed delete, or something)
	else
		-- Can Not Happen: we're deleting stuff from our config, we must know anything there.
		error("Unknown element to delete: " .. name);
	end
end

function uci_datastore:set_config(config, defop, deferr)
	local ops, err = self:edit_config_ops(config, defop, deferr);
	if err then
		return err;
	else
		local cursor = uci.cursor();
		self.changed = {};
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
		for config in pairs(self.changed) do
			cursor:commit(config)
		end
		self.changed = nil;
	end
end

function uci_datastore:user_rpc(procedure, data)
	print("A shoud call procedure: ", procedure, " with this data: ", data);
	return "User rpc is done!";
end

register_datastore_provider(uci_datastore)
