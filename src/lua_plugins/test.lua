register_capability("test:plugin")
register_submodel("/path/to/submodule")
register_stat_generator(function ()
	return "Hello"
end)
datastore = { config = "Hello" }
function datastore:get_config ()
	return "<data xmlns:ns='Namespace'>" .. self.config .. "</data>"
end
function datastore:set_config(config)
	self.config = config
	return "The config is " .. config
end
register_datastore_provider("Namespace", datastore)
