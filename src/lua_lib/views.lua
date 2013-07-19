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
		table.insert((node.subnodes["*"] or { subnodes = {} }).subnodes);
		io.stderr:write("Descend to " .. level .. "\n");
		node = node.subnodes[level] or { subnodes = {} };
	end
	local result = {};
	for _, partial in ipairs(pre_result) do
		for _, callback in ipairs(pre_result) do
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
	friend = false
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
				io.stderr:write("Compare " .. (node.text or '<nil>') .. " with " .. (friend.text or '<nil>') .. "\n");
				if node.text == friend.text then
					node.friend = i;
					io.stderr:write("Match: " .. i .. "\n");
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
		io.stderr:write("Scanning " .. node.name .. "\n");
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
		io.stderr:write("Difference scan on " .. node.name);
		table.insert(path, node.name);
		table.insert(indexes, node.indexes or node.text or {});
		if node.differs or node.children_differ then
			local callbacks = callbacks_find(hooks_differ, id, path);
			if next(callbacks) then
				io.stderr:write("Difference!\n");
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
		io.stderr:write("Restart differences");
		-- Return to enable tail call
		return handle_differences(id, doc);
	end
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
		return xml:strdump();
	end

	register_datastore_provider(result);
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
