local utf8 = require("utf8")

local _sub    = string.sub

local _utf8_offset = utf8.offset
local _utf8_len = utf8.len

local clamp = function(a, min, max)
	if a > max then return max end
	if a < min then return min end
	return a
end

-- returns byte postions a, b around caret and (corrected) caret pos
-- text == text:sub(1, a) .. text:(b)
local function caret_pos(text, pos)
	if pos <= 0 then return 0, 1, 0 end -- prefix
	local len = _utf8_len(text)
	if pos >= len then
		local bytelen = #text
		return bytelen, bytelen + 1, len
	end
	local offset = _utf8_offset(text, pos + 1)
	return offset - 1, offset, pos
end

-- unselected == text:sub(1, a) .. text:(b)
-- selected == text:sub(a + 1, b - 1)
local function caret_selection_pos(text, pos1, pos2)
	local len = _utf8_len(text)
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
	
	local len = _utf8_len(text)
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

local function caret_splitat(text, pos)
	local offset1, offset2, newpos = caret_pos(text, pos)
	return _sub(text, 1, offset1), _sub(text, offset2), newpos
end

local function caret_prefix(text, pos)
	local offset1, offset2, newpos = caret_pos(text, pos)
	return _sub(text, 1, offset1), newpos
end

local function caret_suffix(text, pos)
	local offset1, offset2, newpos = caret_pos(text, pos)
	return _sub(text, offset2), newpos
end

local function caret_typeat(text, pos, input)
	local offset1, offset2, newpos = caret_pos(text, pos)
	return _sub(text, 1, offset1) .. input, _sub(text, offset2), newpos + _utf8_len(input)
end

local function caret_delete_selection(text, pos1, pos2)
	local offset1, offset2, newpos = caret_selection_pos(text, pos1, pos2)
	return _sub(text, 1, offset1), _sub(text, offset2), newpos
end

local function caret_replace_selection(text, pos1, pos2, input)
	local offset1, offset2, newpos = caret_selection_pos(text, pos1, pos2)
	return _sub(text, 1, offset1) .. input, _sub(text, offset2), newpos + _utf8_len(input)
end

local function caret_backspace(text, pos)
	return caret_delete_selection(text, pos - 1, pos)
end

local function caret_delete(text, pos)
	return caret_delete_selection(text, pos, pos + 1)
end

return {
	selection_pos = caret_selection_pos, pos = caret_pos,
	delete = caret_delete, backspace = caret_backspace,
	replace_selection = caret_replace_selection,
	delete_selection = caret_delete_selection,
	typeat = caret_typeat, split = caret_splitat,
	prefix = caret_prefix, suffix = caret_suffix,
}
