require("datastore");
require("views_supervisor");

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

