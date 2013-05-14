register_capability("test:plugin")
register_submodel("/path/to/submodule")
register_stat_generator(function ()
	return "Hello"
end)
datastore = {}
function datastore:get_config ()
	return "Hello", "Error"
end
register_datastore_provider("Namespace", datastore)
