require("datastore");

local datastore = datastore('registration.yin');

function datastore:get()
	local serial = "xyz";

	-- Encode it as XML
	local doc, root, node;
	doc = xmlwrap.new_xml_doc("registration", self.model_ns);
	root = doc:root();
	root:add_child("serial"):set_text(serial);
	return doc:strdump();
end

register_datastore_provider(datastore)
