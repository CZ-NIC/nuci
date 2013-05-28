require("uci")

local uci_datastore = {}

function uci_datastore:set_config(config, defop, deferr)
	return {
		error='operation not supported',
		msg='Setting UCI data not yet supported. Wait for next version.'
	};
end

local function list_config(cursor, config)
	local result = '<config><name>' .. xml_escape(config) .. '</name>';

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

register_datastore_provider("uci.yin", uci_datastore)
