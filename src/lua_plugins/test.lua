datastore = { config = "Hello" }
function datastore:get_config ()
	return "<data xmlns:ns='Namespace'>" .. self.config .. "</data>";
end
function datastore:set_config(config, defop, errop)
	self.config = config;
	print("Op: " .. defop .. " errop: " .. errop .. " config: " .. config);
	return "The config is " .. config;
end
register_datastore_provider("test.yin", datastore)
