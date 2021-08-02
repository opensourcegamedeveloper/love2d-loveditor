local utf8 = require("utf8")

local _sub    = string.sub

local _utf8_offset = utf8.offset
local _utf8_len = utf8.len

local clamp = function(a, min, max)
	if a > max then return max end
	if a < min then return min end
	return a
end

-- returns byte offsets o on the left of caret and (clamped) caret pos
-- so that text == text:sub(1, o) .. text:sub(o + 1)
-- len is optional utf8.len of text
local function offsetof(text, pos, len)
	if pos <= 0 then return 0, 0 end -- prefix
	
	len = len or _utf8_len(text)
	if pos >= len then return #text, len end
	
	return _utf8_offset(text, pos + 1) - 1, pos
end

-- returns byte offsets o1, o2 on the left of carets and the left most (clamped) caret pos
-- unselected text is  text:sub(1, o1) .. text:(o2)
-- selected text is text:sub(o1 + 1, o2 - 1)
local function selection_pos(text, pos1, pos2, len)
	len = len or _utf8_len(text)
	pos1, pos2 = clamp(pos1, 0, len), clamp(pos2, 0, len)
	
	if pos1 == pos2 then
		if pos1 == 0 then return 0, 1, 0 end
		if pos1 == len then
			local bytelen = #text
			return bytelen, bytelen + 1, len
		end
		local offset = _utf8_offset(text, pos1 + 1)
		return offset - 1, offset, pos1
	end
	
	if pos1 > pos2 then pos1, pos2 = pos2, pos1 end
	
	if pos1 == 0 then
		if pos2 == len then return 0, #text + 1, 0 end
		local offset = _utf8_offset(text, pos2 + 1)
		return 0, offset, 0
	end
	if pos2 == len then
		local offset = _utf8_offset(text, pos1 + 1)
		return offset - 1, #text + 1, pos1
	end
	
	local offset1 = _utf8_offset(text, pos1 + 1)
	local offset2 = _utf8_offset(text, pos2 + 1)
	return offset1 - 1, offset2, pos1
end

local function splitat(text, pos, len)
	local o, newpos = offsetof(text, pos, len)
	return _sub(text, 1, o), _sub(text, o + 1), newpos
end

local function prefix(text, pos, len)
	local o, newpos = offsetof(text, pos, len)
	return _sub(text, 1, o), newpos
end

local function suffix(text, pos, len)
	local o, newpos = offsetof(text, pos, len)
	return _sub(text, o + 1), newpos
end

local function typeat(text, pos, input, len)
	local o, newpos = offsetof(text, pos, len)
	return _sub(text, 1, o) .. input, _sub(text, o + 1), newpos + _utf8_len(input)
end

local function delete_selection(text, pos1, pos2, len)
	local offset1, offset2, newpos = selection_pos(text, pos1, pos2, len)
	return _sub(text, 1, offset1), _sub(text, offset2), newpos
end

local function replace_selection(text, pos1, pos2, input, len)
	local offset1, offset2, newpos = selection_pos(text, pos1, pos2, len)
	return _sub(text, 1, offset1) .. input, _sub(text, offset2), newpos + _utf8_len(input)
end

local function backspace(text, pos, len)
	return delete_selection(text, pos - 1, pos, len)
end

local function delete(text, pos, len)
	return delete_selection(text, pos, pos + 1, len)
end

return {
	selection_pos = selection_pos, pos = offsetof,
	delete = delete, backspace = backspace,
	replace_selection = replace_selection,
	delete_selection = delete_selection,
	typeat = typeat, split = splitat,
	prefix = prefix, suffix = suffix,
}
