register_capability("test:plugin")
register_submodel("test-config.yin")

datastore = { config = "Hello" }
function datastore:get_config ()
	return "<data xmlns:ns='Namespace'>" .. self.config .. "</data>"
end
function datastore:set_config(config)
	self.config = config
	return "The config is " .. config
end
register_datastore_provider("Namespace", datastore)
