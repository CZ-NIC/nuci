require("datastore");
require("views_supervisor");

-- OK, this is very stupid and I know it
-- Our buildsystem is not prepared for this concept.
-- Files in src/lua plugins are autoloaded but they require YIN model.
-- We need some directory with autoloading and without any more checks.
-- This is only temporaly hack
require("ap_testing1");


local datastore = datastore('supervisor_test.yin')

function datastore:get()
	local doc, root, node;

	--prepare XML subtree
	doc = xmlwrap.new_xml_doc("supervisor-test", "http://www.nic.cz/ns/router/supervisor-test");
	root = doc:root();

	local supervisor_output, err = supervisor:get();
	if not supervisor_output then
		root.set_text("FAILED: " .. err);
	end
	root:set_text(supervisor_output);

	return doc:strdump();
end

register_datastore_provider(datastore)

