require("datastore");
require("views_supervisor");

local datastore = datastore('supervisor_test.yin')

function datastore:get()
	local doc, root, node;

	--prepare XML subtree
	doc = xmlwrap.new_xml_doc("supervisor-test", "http://www.nic.cz/ns/router/supervisor-test");
	root = doc:root();

	local supervisor_output = supervisor:get();
	root:set_text(supervisor_output);

	return doc:strdump();
end

register_datastore_provider(datastore)

