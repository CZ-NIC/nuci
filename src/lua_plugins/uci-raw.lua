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
	cdata = cursor:get_all(config);
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
	local cursor = get_uci_cursor();
	local result = [[<uci xmlns='http://www.nic.cz/ns/router/uci-raw'>]];
	for _, config in ipairs(uci_list_configs()) do
		result = result .. list_config(cursor, config);
	end
	result = result .. '</uci>';
	return result;
end

function uci_datastore:subnode_value(node, name)
	local node = find_node_name_ns(node, name, self.model_ns);
	if node then
		return node:text();
	end
end

function uci_datastore:node_path(node)
	local result = {};
	local name = node:name();
	while node do
		local name, ns = node:name();
		-- In case of the root node, the name is empty
		if not name or name == 'uci' then break end;
		result[name] = node;
		result[name .. '_name'] = uci_datastore:subnode_value(node, 'name');
		node = node:parent();
		name = node:name();
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

function uci_datastore:set_config(config, defop, deferr)
	local ops, err = self:edit_config_ops(config, defop, deferr);
	if err then
		return err;
	else
		local cursor = get_uci_cursor();
		-- Prepare data structures.
		self.changed = {};
		self.delayed_lists = {}
		-- The description of operations.
		local function mandatory_node(name)
			return {
				replace = {
					msg="Can't replace " .. name .. ", replace the whole owner",
					tag="operation-not-supported",
					bad_elemname=name,
					bad_elemns=self.model_ns
				},
				remove = {
					msg="Can't delete mandatory node " .. name,
					tag="data-missing",
					bad_elemname=name,
					bad_elemns=self.model_ns
				},
				create = {
					msg="Can't (directly) node " .. name,
					tag="data-exists",
					bad_elemname=name,
					bad_elemns=self.model_ns
				}
			}
		end
		local name_desc = mandatory_node('name');
		local function content_set(node)
			local _, path = self:node_path(node);
			-- Get the delayed list. It'll be put into UCI at the end of the processing.
			local list = self:get_delayed_list(cursor, path);
			-- Get the index and value
			local parent = path.list;
			local index = self:subnode_value(parent, 'index');
			local value = node:text();
			-- And store it there.
			list[tonumber(index)] = value;
		end
		local value_desc = {
			create = function() end, -- Just recurse to the content
			create_recurse_after = 'create',
			create_recurse_skip = {'index'},
			replace = function() end,
			replace_recurse_after = 'create',
			remove = function(node)
				local _, path = self:node_path(node);
				-- Get the delayed list. It'll be put into UCI at the end of the processing.
				local list = self:get_delayed_list(cursor, path);
				-- Get the index and delete the value from the list.
				local index = self:subnode_value(node, 'index');
				list[tonumber(index)] = nil;
			end,
			children = {
				index = mandatory_node('index'),
				content = {
					create = content_set,
					replace = content_set,
					remove = {
						msg="Can't delete mandatory node content",
						tag="data-missing",
						bad_elemname=name,
						bad_elemns=self.model_ns
					}
				}
			}
		}
		local function empty_list(node)
			local _, path = self:node_path(node);
			self:set_empty_delayed_list(cursor, path);
		end
		local list_desc = {
			create = empty_list, -- prepare fresh empty list (create or replace)
			create_recurse_after = 'create',
			create_recurse_skip = 'name',
			remove = empty_list,
			children = {
				name = name_desc,
				value = value_desc
			}
		}
		local function option_set(node)
			local _, path = self:node_path(node);
			cursor:set(path.config_name, path.section_name, path.option_name, node:text());
		end
		local option_desc = {
			create = function() end, -- Just recurse to the value
			create_recurse_after = 'create',
			create_recurse_skip = {'name'},
			replace = function() end, -- The same, with replace
			replace_recurse_after = 'create',
			remove = function(node)
				local _, path = self:node_path(node);
				cursor:delete(path.config_name, path.section_name, path.option_name);
			end,
			children = {
				name = name_desc,
				value = {
					create = option_set,
					replace = option_set,
					remove = {
						msg="Can't delete mandatory node value",
						tag="data-missing",
						bad_elemname=name,
						bad_elemns=self.model_ns
					}
				}
			}
		}
		local section_desc = {
			-- Create the section (either anonymous or not)
			create = function(node)
				local _, path = self:node_path(node);
				local sectype = self:subnode_value(node, 'type');
				local anonymous = find_node_name_ns(node, 'anonymous', self.model_ns);
				local name = cursor:add(path.config_name, sectype);
				if anonymous then
					local name_node = find_node_name_ns(node, 'name', self.model_ns);
					name_node:set_text(name);
				else
					cursor:rename(path.config_name, name, path.section_name);
				end
			end,
			-- After we created the section, recurse to create the content
			create_recurse_after='create',
			create_recurse_skip={'name', 'type', 'anonymous'},
			-- There's direct function for section removal
			remove = function(node)
				local _, path = self:node_path(node);
				cursor:delete(path.config_name, path.section_name);
			end,
			-- We don't need to recurse there.
			children = {
				name = name_desc,
				type = mandatory_node('type'),
				anonymous = {
					remove = {
						msg="Can't un-anonymise a section. That is possible, but makes little sense and it is hard to do.",
						tag="operation-not-supported",
						bad_elemname="anonymous",
						bad_elemns=self.model_ns
					},
					create = {
						msg="Can't anonymise a section, remove and readd",
						tag="operation-not-supported",
						info_badelem=name,
						info_badns=self.model_ns
					}
				},
				value = value_desc,
				option = option_desc
			}
		}
		local config_desc = {
			-- Configs can't be added or removed.
			remove = function()
				return {
					msg="Deleting (or replacing) whole configs is not possible",
					tag="operation-not-supported",
					info_badelem=name,
					info_badns=self.model_ns
				};
			end,
			create = function()
				return {
					msg="Creating whole configs is not possible, you have to live with what there is already",
					tag="operation-not-supported",
					info_badelem=name,
					info_badns=self.model_ns
				};
			end,
			replace = function() end, -- We don't do anything when replacing the config except recurse onto sections
			-- Recurse on sections, but not names (delete before, create after)
			replace_recurse_before='remove',
			replace_recurse_after='create',
			create_recurse_skip={'name'},
			remove_recurse_skip={'name'},
			-- When we enter a config, we're going to change stuff inside, so schedule it for commit.
			enter = function(operation)
				local _, path = self:node_path(operation.command_node);
				self.changed[path.config_name] = true;
			end,
			children = {
				name = name_desc,
				section = section_desc
			}
		}
		local description = {
			namespace = self.model_ns,
			children = {
				uci = {
					children = {
						config = config_desc
					}
				}
			}
		}
		local err = applyops(ops, description);
		if err then
			return err;
		end
		-- Push in all the delayed lists we have.
		for config_name, config in pairs(self.delayed_lists) do
			for section_name, section in pairs(config) do
				for name, list in pairs(section) do
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
						for _, val in pairs(tuples) do
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
		local changed = self.changed;
		self.changed = nil;
		self.delayed_lists = nil;
		self:schedule_commit(function ()
			-- TODO: Restart the daemons there
			for config in pairs(changed) do
				cursor:commit(config)
			end
		end);
	end
end

register_datastore_provider(uci_datastore)
