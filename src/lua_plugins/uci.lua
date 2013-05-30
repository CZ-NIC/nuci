require("uci")
require("datastore")

local uci_datastore = datastore("uci.yin")

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
	local kind = 'list';
	if type(value) ~= 'table' then
		value = { value };
		kind = 'option';
	end
	local result = '<' .. kind .. '><name>' .. xml_escape(name) .. '</name>';
	for _, v in ipairs(value) do
		result = result .. '<value>' .. xml_escape(v) .. '</value>';
	end
	result = result .. '</' .. kind .. '>';
	return result;
end

local function list_section(section)
	local result = '<section><type>' .. xml_escape(section[".type"]) .. "</type>";
	if not section[".anonymous"] then
		result = result .. "<name>" .. xml_escape(section[".name"]) .. "</name>";
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
	local cursor = uci.cursor()
	local result = [[<uci xmlns='http://www.nic.cz/ns/router/uci-raw'>]];
	for _, config in ipairs(uci_list_configs()) do
		result = result .. list_config(cursor, config);
	end
	result = result .. '</uci>';
	return result;
end

function uci_datastore:set_config(config, defop, deferr)
	return {
		error='operation not supported',
		msg='Setting UCI data not yet supported. Wait for next version.'
	};
end

register_datastore_provider(uci_datastore)
