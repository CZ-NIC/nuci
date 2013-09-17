require("tableutils");
require("nutils");
require("datastore");

-- Global state varables
supervisor = {
	plugins = {},
	tree = {},
	cached = false,
	doc = nil
};

dbg = "";
local function dbg_add(str)
	dbg = dbg .. str .. "\n";
end

local function tree_try_add_key(keys, keyset)
	local function exists_keyset(keys, keyset)
		for _, keys_internal in pairs(keys) do
			if match_keysets(keys_internal, keyset) then
				-- Found one that matches
				return true;
			end
		end
		return false;
	end

	if keyset ~= nil then
		if not exists_keyset(keys, keyset) then
			table.insert(keys, keyset);
		end
	end
end

local function tree_rec_add(node, level, plugin, path, key)
	-- Test path variable
	if path[level] == nil then
		return nil, "Empty path";
	end

	-- Create if node is empty
	if table.is_empty(node) then
		node.name = path[level];
		node.keys = {};
		node.children = {};
	end

	-- Add keys
	tree_try_add_key(node.keys, key[level]);

	-- Recurse or create node
	if path[level+1] == nil then
		-- I'm leaf
		if node.plugins == nil then
			node.plugins = {}; -- Table of plugin doesn't exists yet - create it
		end
		-- Leaf needs infromation about registered plugins
		table.insert(node.plugins, plugin);

	else
		-- I'm inner node
		if node.children[path[level+1]] == nil then
			node.children[path[level+1]] = {}; -- Table of child doesn't exists yet - create it
		end

		tree_rec_add(node.children[path[level+1]], level+1, plugin, path, key);
	end
end

function supervisor:register_ap(plugin)
	supervisor.plugins[plugin.id] = plugin;
end

function supervisor:register_value(plugin, path, key)
	tree_rec_add(supervisor.tree, 1, plugin, path, key);
end

function supervisor:register_all_values()
	local ret, err;
	for _, plugin in pairs(supervisor.plugins) do
		ret, err = plugin:register_values();
		if not ret then
			return ret, err;
		end
	end

	return true;
end

-- FIXME: This probably doesn't work with multiple datastore providers. Or does it?
function supervisor:init(init_doc)
	if supervisor.doc == nil then
		supervisor.doc = init_doc;
	end
end

function supervisor:invalidate_cache()
	supervisor.cached = false;
end

local function build_get_value(plugins, path, level, keyset)
	-- FIXME: Returning first valid answer is temporaly solution
	for _, plugin in pairs(plugins) do
		local res = plugin:get(path, level, keyset);
		if res ~= nil then
			return res;
		end
	end

	return nil;
end

local function build_rec(node, onode, keyset, path, level)
	if node == nil then
		return
	end

	path[level] = node.name;

	local new_node;
	if table.is_empty(node.keys) then
		if table.is_empty(node.children) then
			-- Generate leaf's value
			local res = build_get_value(node.plugins, path, level, keyset);
			if res ~= nil then
				for _, val in ipairs(res) do
					new_node = onode:add_child(node.name);
					new_node:set_text(val);
				end
			end
		else
			-- Recurse to children
			new_node = onode:add_child(node.name);
			for _, child in pairs(node.children) do
				build_rec(child, new_node, keyset, path, level+1);
			end
		end
	else
		for _, key in pairs(node.keys) do
			-- Create copy of this node with this keyset in XML
			new_node = onode:add_child(node.name);
			-- Add keyset record into XML node
			for key_name, key_val in pairs(key) do
				new_node:add_child(key_name):set_text(key_val);
			end
			-- Recurse to children of this copy
			for _, child in pairs(node.children) do
				--table.insert(key, keyset);
				build_rec(child, new_node, key, path, level+1);
			end
		end
	end
end

function supervisor:build_tree(onode)
	build_rec(supervisor.tree, onode, nil, {}, 1);
end

function supervisor:get()
	-- Does some data exist?
	if supervisor.cached == true then
		return supervisor.doc;
	end
	-- Data doesn't exists

	-- First of all - let plugins to register all values of tree
	ret, err = supervisor:register_all_values();
	if not ret then
		return ret, err;
	end

	-- Build new tree
	supervisor.cached = true;
	supervisor:build_tree(supervisor.doc:root());

	-- Development and debug
	--dbg_add(table.tostring(supervisor.tree)); -- This output is very long - uncomment it if you need it
	supervisor.doc:root():add_child("dbg"):set_text(dbg);


	return supervisor.doc;
end

local function get_plugins_rec(node, path, level)
	if node == nil then
		return nil;
	end

	if node.name == path[level] then
		if path[level+1] == nil then
			return node.plugins;
		end
		if not table.is_empty(node.children) then
			return get_plugins_rec(node.children[path[level+1]], path, level+1);
		end
	end

	return nil;
end

function supervisor:get_plugins(path)
	return get_plugins_rec(supervisor.tree, path, 1);
end

-- Get value calculated by more plugins
function supervisor:get_value(path, keyset)
	local plugins = supervisor:get_plugins(path);
	if plugins == nil then
		return nil;
	end

	return build_get_value(plugins, path, #path, keyset);
end

-- Get value from single plugin
function supervisor:get_raw_value(id, path, keyset)
	local plugin = supervisor.plugins[id];
	if plugin == nil then
		return nil;
	end

	return plugin:get(path, #path, keyset);
end

--[[
Generate a usual datasource provider based on the supervisor and views.
Pass the yin file, the rest is extracted from it.
]]

function supervisor:generate_datasource_provider(yin_name)
	local datastore = datastore(yin_name);

	function datastore:get()
		supervisor:init(xmlwrap.new_xml_doc(self.model_name, self.model_ns));

		local doc, err = supervisor:get();

		if doc then
			return doc:strdump();
		else
			return nil, err;
		end
	end

	return datastore;
end
