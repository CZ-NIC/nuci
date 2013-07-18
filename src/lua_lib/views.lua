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
	local node = where[id] or { subnodes = {} };
	for _, level in ipairs(path) do
		io.stderr:write("Descend to " .. level .. "\n");
		node = node.subnodes[level] or { subnodes = {} };
	end
	return node.callbacks or {};
end

-- What should and should not be checked
local check = {
	text = true,
	name = false,
	namespace = false,
	generate = false
};

--[[
Merge one node into another. It overwrites basic values, like name and
namespace. It checks the text is the same if there was one before.

With the children, it is more complex. If the children are for name
not yet known, they are just added. If it is for known children, they
are tried to match and check they are equal. If not, error is raised.

TODO: We need to run hooks there, however, if they differ.
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
				error("TODO: Handle differing value on " .. name .. ": " .. original[name] .. " vs. " .. value );
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
	local ok, mk = genknown(original), genknown(more);
	for _, child in ipairs(more.children or {}) do
		local name = child.name;
		if not mk[name] then
			error('Found a child of name ' .. name .. ' but the name is not claimed to be known');
		end
		if ok[name] then
			error('Comparing children not implemented yet');
		end
		table.insert(original.children, child);
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
	register(hooks_get, id, path, callback);
end
