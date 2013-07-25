require("datastore");
require("xmltree");

local hooks_set = {};
local hooks_get = {};
local hooks_differ = {};

--[[
Find the list of callbacks at given set of callbacks, for the given
view ID and path. If not found, returns empty list.
]]
local function callbacks_find(where, id, path)
	local pre_result = {};
	local node = where[id] or { subnodes = {} };
	for _, level in ipairs(path) do
		table.insert(pre_result, (node.subnodes["*"] or {}).callbacks or {});
		node = node.subnodes[level] or { subnodes = {} };
	end
	table.insert(pre_result, node.callbacks or {});
	local result = {};
	for _, partial in ipairs(pre_result) do
		for _, callback in ipairs(partial) do
			table.insert(result, callback);
		end
	end
	return result;
end

-- What should and should not be checked
local check = {
	text = true,
	name = false,
	namespace = false,
	generate = false,
	friend = false,
	parent = false
};

-- Just go through the list and pick every one that has the given name.
local function filter_children(list, name)
	local result = {};
	for _, child in ipairs(list) do
		if child.name == name then
			table.insert(result, child);
		end
	end
	return result;
end

-- For each node, try to store an index of the friend in the other side
-- where indexes correspond
local function mark_friends(nodes, friends)
	for _, node in pairs(nodes) do
		node.friend = nil; -- Erase any possible previous mark
		if node.indexes then
			-- Do it by indexes
			for i, friend in pairs(friends) do
				local equals = true; -- Nothing differs yet
				for _, index in pairs(node.indexes) do
					local function extract(node)
						local children = node.children or {};
						local child = children[index] or {};
						return child.text or '';
					end
					if extract(node) ~= extract(friend) then
						found = false;
						break;
					end
				end
				if equals then -- We found a friend
					node.friend = i;
					break;
				end
			end
		else
			-- Do it by the text
			for i, friend in pairs(friends) do
				if node.text == friend.text then
					node.friend = i;
					break;
				end
			end
		end
	end
end

--[[
Merge one node into another. It overwrites basic values, like name and
namespace. It checks the text is the same if there was one before.

With the children, it is more complex. If the children are for name
not yet known, they are just added. If it is for known children, they
are tried to match and check they are equal. If not, they are marked
is raised.
]]
local function merge(original, more)
	-- Make sure the original has anything needed
	if not original.children then
		original.children = {};
	end
	if not original.known then
		original.known = {};
	end
	for name, value in pairs(more) do
		if name ~= 'children' and name ~= 'known' then
			local check_this = check[name];
			if check_this == nil then
				error("Found unknown item " .. name .. " when merging results");
			end
			if check_this and original[name] ~= nil and original[name] ~= value then
				original.differs = true;
			end
			original[name] = value;
		end
	end
	-- Handle childrend and known.
	local function genknown(node)
		local result = {};
		for _, name in pairs(node.known or {}) do
			result[name] = true;
		end
		return result;
	end
	local ok, mk, handled = genknown(original), genknown(more), {};
	for _, child in ipairs(more.children or {}) do
		local name = child.name;
		if not handled[name] then -- Skip the ones already merged.
			if not mk[name] then
				error('Found a child of name ' .. name .. ' but the name is not claimed to be known');
			end
			if ok[name] then
				handled[name] = true;
				-- Get the children of both original and the new node
				local original_children = filter_children(original.children, name);
				local more_children = filter_children(more.children, name);
				-- Try matching them together.
				mark_friends(original_children, more_children);
				mark_friends(more_children, original_children);
				--[[
				Go through them and find the matching pairs. Merge the
				matching ones and add the non-matching ones. Also mark if it differs.
				]]
				for _, child in pairs(original_children) do
					if not child.friend then
						original.children_differ = true;
						break;
					end
				end
				for _, child in ipairs(more_children) do
					if child.friend then
						merge(original_children[child.friend], child);
					else
						table.insert(original.children, child);
						original.children_differ = true;
					end
				end
			else
				table.insert(original.children, child);
			end
		end
	end
	-- Merge known
	for k in pairs(mk) do
		if not ok[k] then
			table.insert(original.known, k);
		end
	end
end;

--[[
Copy (and return) a table.
]]
local function tcopy(table)
	local result = {};
	for i, v in pairs(table) do
		result[i] = v;
	end
	return result;
end;

--[[
Go through the given subtree and return an iterator for all the nodes
that contain a `generate = true` item.

The indexes and path identify the position and are included in the
result (augmented to match the sub-nodes).
]]
local function find_generated_positions(subtree, indexes, path)
	local result = {};
	if not path then
		path = {subtree.name};
		indexes = {subtree.indexes or subtree.text or {}};
	end
	local function walk(node)
		-- Should this one be generated?
		if node.generate then
			table.insert(result, {
				path = tcopy(path),
				indexes = tcopy(indexes),
				node = node
			});
			node.generate = nil; -- Don't generate the next time
		end
		for _, child in pairs(node.children or {}) do
			table.insert(path, child.name);
			table.insert(indexes, child.indexes or child.text or {});
			walk(child);
			table.remove(indexes);
			table.remove(path);
		end
	end;
	walk(subtree);
	return pairs(result);
end;

--[[
Find the nodes marked for differences and call hooks on them.

Each hook may arbitrarily modify the document structure. For that reason,
we restart the differences handling each time a node is found and the
differences handled.
]]
local function handle_differences(id, doc)
	local restart = false;
	local exception;

	local path = {};
	local indexes = {};
	local function walk(node)
		table.insert(path, node.name);
		table.insert(indexes, node.indexes or node.text or {});
		if node.differs or node.children_differ then
			local callbacks = callbacks_find(hooks_differ, id, path);
			if next(callbacks) then
				-- This difference will get handled now.
				node.differs = nil;
				node.children_differ = nil;
				for _, callback in ipairs(callbacks) do
					local err = callback(doc, node, indexes, path);
					if err then
						exception = err;
						-- Exit the walk recursion
						return true;
					end
				end
				-- Do a restart, as we handled a change
				restart = true;
				return true;
			else
				error("Difference at node " .. node.name .. " not handled");
			end
		end
		for _, child in pairs(node.children or {}) do
			child.parent = node; -- For the convenience of called functions
			if walk(child) then
				return true; -- Propagate exit of recursion
			end
		end
		table.remove(path);
		table.remove(indexes);
	end;
	walk(doc);
	if exception then
		return exception;
	end
	if restart then
		-- Return to enable tail call
		return handle_differences(id, doc);
	end
end

-- TODO: Unify place for these namespaces and similar
local yang_ns = 'urn:ietf:params:xml:ns:yang:yin:1'

--[[
Convert the XML model to a description for the applyops function.
Directly calls the callbacks registered for the given ID.
]]
local function model2desc(model, id)
	local handlers = {
		container = {
			children = true
		},
		list = {
			children = true,
			indexes = true
		},
		['leaf-list'] = {},
		leaf = {}
	};
	local result = {
		children = {},
		enter = function()
			path = {};
			index_path = {};
		end
	};
	--[[
	Variables used during the traversal to keep the path and list
	of indexes passed to the callbacks.
	]]
	local path, index_path = {}, {};
	-- Function to call the callbacks on some node, provided path and index_path is correctly set.
	-- TODO: We probably want to have a complete applied tree of configuration now, for examination of the callbacks.
	local function update(node, mode)
		local text = node:text();
		io.stderr:write("Apply " .. mode .. " with " .. (text or '<nil>') .. "\n");
		for _, callback in ipairs(callbacks_find(hooks_set, id, path)) do
			local err = callback(mode, text, index_path, path);
			if err then return err; end
		end
	end
	local function process_node(node, handler)
		local node_name = node:attribute("name");
		local result = {
			dbg=node_name
		};
		-- If we have indexes, extract the list of them.
		local indexes, indexes_map = {}, {};
		if handler.indexes then
			indexes = iter2list(list_keys(node));
			indexes_map = list2map(indexes);
		end
		-- If children are allowed, go through them and handle.
		if handler.children then
			for child in node:iterate() do
				local name, ns = child:name();
				local handler = handlers[name];
				if handler and ns == yang_ns then
					local desc = process_node(child, handler);
					local child_name = child:attribute("name");
					if not result.children then
						result.children = {};
					end
					result.children[child_name] = desc;
				end
			end
			result.replace_recurse_before='remove';
			result.replace_recurse_after='create';
			result.create_recurse_after='create';
			result.remove_recurse_before='remove';
		end
		-- Keep track of the path and indexes to the local node
		result.leave = function()
			table.remove(path);
			table.remove(index_path);
		end
		result.enter = function(operation)
			table.insert(path, node_name);
			local entered_node = operation.command_node;
			local _, ns = entered_node:name();
			local index_values = {};
			for index in pairs(indexes_map) do
				local index_node = find_node_name_ns(entered_node, index, ns);
				-- TODO: Check if the node exists?
				index_values[index] = index_node:text();
			end
			if not next(index_values) then
				local has_children;
				for child in entered_node:iterate() do
					local name, ns = child:name();
					-- We take only children with namespace. The ones without are usually the special ones (comments, text, etc).
					if ns then
						has_children = true;
						break;
					end
				end
				if has_children then
					index_values = {};
				else
					-- Take the text if there are no subitems. Otherwise, we would take the text recursively. We don't allow text AND children in the same element.
					index_values = entered_node:text() or {};
				end
			end
			table.insert(index_path, index_values);
		end
		-- Run callbacks in the nodes that are created or removed
		for _, name in ipairs({'create', 'remove', 'replace'}) do
			result[name] = function(node) return update(node, name); end
		end
		return result;
	end
	for node in model:root():iterate() do
		local name, ns = node:name();
		local handler = handlers[name];
		if handler and ns == yang_ns then
			local cname = node:attribute('name');
			result.children[cname] = process_node(node, handler);
		end
	end
	assert(result);
	return result;
end

function register_view(model, id)
	local result = datastore(model);

	result.get_config = nil;
	function result:get_config()
		local doc = {
			name = ''
		};
		local pending = { { node = doc } };

		-- Process all the places that need to be generated.
		while next(pending) do
			while next(pending) do
				-- Extract one (arbitrary) position
				local index, position = next(pending);
				pending[index] = nil;

				-- get the callbacks
				local callbacks = callbacks_find(hooks_get, id, position.path or {});
				--[[
				Call each of the callbacks. Store the results, don't merge them yet.
				That could confuse the next callbacks, because it would modify the
				parameter passed to the following callbacks.
				]]
				local results = {};
				for index, callback in ipairs(callbacks) do
					local err;
					results[index], err = callback(position.node, position.indexes, position.path);
					if err then
						return nil, err;
					end
				end
				-- Merge the things together, one by one
				for _, data in ipairs(results) do
					local err = merge(position.node, data);
					if err then
						return err;
					end
				end
				-- Push the new ones into the table of pending, into the first empty position
				for _, g in find_generated_positions(position.node, position.indexes, position.path) do
					table.insert(pending, g);
				end
			end

			-- Go through the whole document and call hooks on each place marked as it differs.
			local err = handle_differences(id, doc);
			if err then
				return nil, err;
			end
			-- Check if it generated more places to process
			for _, g in find_generated_positions(doc) do
				table.insert(pending, g);
			end
		end

		local xml = xmltree_dump(doc);
		io.stderr:write(xml:strdump() .. "\n");
		return xml:strdump();
	end

	register_datastore_provider(result);

	-- We need to register first, to have the model.
	local description = model2desc(result.model, id);
	description.namespace = result.model_ns;
	function result:set_config(config, defop, deferr)
		local ops, err, current, operation = self:edit_config_ops(config, defop, deferr);
		if err then
			return err;
		end
		err = applyops(ops, description);
		if err then
			return err;
		end
	end
	return result;
end

local function register(where, id, path, callback)
	local node = where[id] or { callbacks = {}, subnodes = {} };
	where[id] = node;
	for _, level in ipairs(path) do
		local sub = node.subnodes[level] or { callbacks = {}, subnodes = {} };
		node.subnodes[level] = sub;
		node = sub;
	end
	table.insert(node.callbacks, callback);
end

function hook_set(id, path, callback)
	register(hooks_set, id, path, callback);
end

function hook_get(id, path, callback)
	register(hooks_get, id, path, callback);
end

function hook_differ(id, path, callback)
	register(hooks_differ, id, path, callback);
end
