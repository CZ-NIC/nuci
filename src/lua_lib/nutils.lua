-- Find the first child node matching a predicate, or nil.
function find_node(node, predicate)
	for child in node:iterate() do
		if predicate(child) then
			return child;
		end
	end
end
