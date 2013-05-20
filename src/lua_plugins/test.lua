register_capability("test:plugin")
register_submodel("test-config.yin")
register_stat_generator("test.yin", function ()
	output = "<stats xmlns='http://www.nic.cz/ns/router/stats'>";
	ecode, out, err = run_command('Hello', 'cat');
	output = output .. "<content>" .. out .. "</content>";
	output = output .. "</stats>";
	print(output);
	return output;
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
