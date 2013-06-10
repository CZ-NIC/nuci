-- Find the first child node matching a predicate, or nil.
function find_node(node, predicate)
	for child in node:iterate() do
		if predicate(child) then
			return child;
		end
	end
end

-- split the string into words
function split(str)
	return str:gmatch('%S+');
end
