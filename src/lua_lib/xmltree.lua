local function handle_node(node, desc)
	if desc.children then
		for i, child in ipairs(desc.children) do
			local sub = node:add_child(child.name, child.namespace);
			handle_node(sub, child);
		end
	end
	if desc.text then
		node:set_text(desc.text);
	end
end

function xmltree_dump(tree)
	local doc = xmlwrap.new_xml_doc(tree.name, tree.namespace);
	local node = doc:root();
	handle_node(node, tree);
	return doc;
end
