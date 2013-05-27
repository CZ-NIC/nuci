datastore = { config = "Hello" }
function datastore:get_config ()
	return "<data xmlns:ns='Namespace'>" .. self.config .. "</data>";
end
function datastore:set_config(config, defop, errop)
	self.config = config;
	print("Op: " .. defop .. " errop: " .. errop .. " config: " .. config);
end
register_datastore_provider("test.yin", datastore)

for i, val in ipairs(uci_list_configs()) do
	print(val);
end
