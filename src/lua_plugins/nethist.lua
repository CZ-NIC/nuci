require("uci");
require("datastore");

local HIST_FILE = "/tmp/nethist";

-- trim whitespace from right end of string
local function trimr(s)
	return s:find'^%s*$' and '' or s:match'^(.*%S)'
end

local function parse_line(line)
	local items = {};
	local i = 1;
	line = line .. ',';
	for item in line:gmatch('([^,]*)[,]') do
		items[i] = item;
		i = i + 1;
	end

	return items;
end

local function parse_file(file, node)
	local prev_time = -1; -- 0 is possible value; not 1. 1. 1970 but unsnapped slot
	local prev_item = nil;

	local snap_node;
	local net_node;
	for line in file:lines() do
		items = parse_line(line);
		if items[1] ~= '0' then
			if prev_time ~= items[1] then
				snap_node = node:add_child('snapshot');
				snap_node:add_child('time'):set_text(items[1]);
			end

			if items[2] == "cpu" then
				prev_item = items[2];
				snap_node:add_child('cpu'):add_child('load'):set_text(items[3]);
			elseif items[2] == "memory" then
				prev_item = items[2];
				local mem_node = snap_node:add_child('memory');
				mem_node:add_child('memtotal'):set_text(items[3]);
				mem_node:add_child('memfree'):set_text(items[4]);
				mem_node:add_child('buffers'):set_text(items[5]);
				mem_node:add_child('cached'):set_text(items[6]);
			elseif items[2] == "network" then
				if prev_item ~= items[2] then
					net_node = snap_node:add_child('network');
				end
				prev_item = items[2];
				local iface_node = net_node:add_child('interface');
				iface_node:add_child('name'):set_text(items[3]);
				iface_node:add_child('rx'):set_text(items[4]);
				iface_node:add_child('tx'):set_text(items[5]);
			end
		end

		prev_time = items[1];
	end
end

local datastore = datastore('nethist.yin')

function datastore:get()
	local doc, root, node;

	--prepare XML subtree
	doc = xmlwrap.new_xml_doc(self.model_name, self.model_ns);
	root = doc:root();

	local file = io.open(HIST_FILE);
	if not file then
		return nil, "Cannot open file with history: " .. HIST_FILE;
	end
	parse_file(file, root:add_child('snapshots'));
	file:close();

	return doc:strdump();
end

register_datastore_provider(datastore)
