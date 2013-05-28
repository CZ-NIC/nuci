local uci_datastore = {}

function uci_datastore:set_config(config, defop, deferr)
	return {
		error='operation not supported',
		msg='Setting UCI data not yet supported. Wait for next version.'
	};
end

function uci_datastore:get_config()

end

register_datastore_provider("uci.yin", uci_datastore)
