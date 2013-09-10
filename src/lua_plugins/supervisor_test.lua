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
	supervisor:init(xmlwrap.new_xml_doc("supervisor-test", "http://www.nic.cz/ns/router/supervisor-test"));

	local doc, err = supervisor:get();
	if not doc then
		return doc, err;
	end

	return doc:strdump();
end

register_datastore_provider(datastore)

