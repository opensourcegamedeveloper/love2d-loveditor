local utf8 = require "utf8"

local Caret = require "caret"

local editor = {}

-- MODULE START
local M = {}
M.meta = {__index = editor}

M.font = love.graphics.newFont("font/Inconsolata-LGC.otf", 13)

local split = function(s, sep)
	local _sub    = string.sub
	local _find   = string.find
	local _insert = table.insert
	
	local t = {}; local init = 1; local m, n
	sep = sep or '\n'
	while true do
		m, n = _find(s, sep, init, true)
		if m == nil then
			_insert(t, _sub(s, init))
			break
		end
		_insert(t, _sub(s, init, m - 1))
		init = n + 1
	end
	return t, #t
end

M.new = function(data)
	local font = M.font
	local datatype = type(data)
	local buffer
	if datatype == "string" then
		buffer = split(data)
	elseif datatype == "table" and data[1] then
		buffer = data
	else
		buffer = {""}
	end
	local e = {
		buffer = buffer,
		caret  = {line = 1, col = 0, x = 0},
		endpos = {line = 1, col = 0, x = 0},
		x = 5, y = 5,
		font = font, fh = font:getHeight(),
		margin = font:getWidth("88888"),
	}
	return setmetatable(e, M.meta)
end

-- MODULE END

local caret_zero = {line = 1, col = 0, x = 0}

local function setcaret(dst, src)
	dst.line, dst.col, dst.x = src.line, src.col, src.x
end

function editor:resetcarets(line, col, x)
	setcaret(self.caret, caret_zero)
	setcaret(self.endpos, caret_zero)
end

function editor:savefile(filename)
	local ok, msg = love.filesystem.write(filename, table.concat(self.buffer, "\n"))
	if not ok then print(msg) return end
	return true
end

function editor:loadfile(filename)
	local content, size = love.filesystem.read(filename)
	if not content then print(size) return end
	self:load(content)
	return true
end

function editor:clear()
	self:resetcarets()
	self.buffer = {""}
end

function editor:load(s)
	self:resetcarets()
	self.buffer = split(s)
end




function editor:setline(lineno, s)
	local buffer = self.buffer
	assert(lineno >= 1 and lineno <= #buffer, "lineno out of bounds")
	
	buffer[lineno] = s
end

function editor:replace_selection(caret, endpos, input, out)
	local s1, s2
	local font = self.font
	if caret.line ~= endpos.line then
		local ul, uc, ll, lc, ux --upper/lower line/col/x
		if caret.line < endpos.line then
			ux, ul, uc, ll, lc = caret.x, caret.line, caret.col, endpos.line, endpos.col
			ux = caret.x
		else
			ux, ul, uc, ll, lc = endpos.x, endpos.line, endpos.col, caret.line, caret.col
		end
		local utext, ltext = self.buffer[ul], self.buffer[ll]
		local o1, o2 = Caret.pos(utext, uc), Caret.pos(ltext, lc)
		s1 = utext:sub(1, o1) -- prefix of upper
		s2 = ltext:sub(o2 + 1) -- suffix of lower
		
		if out then
			table.insert(out, utext:sub(o1 + 1)) -- suffix of upper
			for i = ll - 1, ul + 1, - 1 do
				table.insert(out, table.remove(self.buffer, i))
			end
			table.insert(out, ltext:sub(1, o2)) -- prefix of lower
		else
			for i = ll - 1, ul + 1, - 1 do
				table.remove(self.buffer, i) -- remove fully selected lines
			end
		end
		
		if input == "\n" then
			self:setline(ul, s1)
			self:setline(ul + 1, s2)
			caret.col, caret.x, caret.line = 0, 0, ul + 1
			setcaret(endpos, caret)
			return out
		end
		
		caret.line = ul
		local inputtype = type(input)
		if inputtype == "table" and #input == 1 then
			inputtype, input = type(input[1]), input[1]
		end
		
		if inputtype == "string" and input ~= "" then
			s1 = s1 .. input
			caret.col, caret.x = uc + utf8.len(input), font:getWidth(s1)
			self:setline(ul, s1 .. s2)
			table.remove(self.buffer, ul + 1)
		elseif inputtype == "table" and #input > 1 then
			self:setline(caret.line, s1 .. input[1])
			for i = 2, #input - 1 do
				caret.line = caret.line + 1
				table.insert(self.buffer, caret.line, input[i])
			end
			caret.line = caret.line + 1
			self:setline(caret.line, input[#input] .. s2)
			caret.col, caret.x = utf8.len(input[#input]), font:getWidth(input[#input])
		else
			caret.col, caret.x = uc, ux
			self:setline(ul, s1 .. s2)
			table.remove(self.buffer, ul + 1)
		end
		setcaret(endpos, caret)
		return out
	end
	
	-- also if empty table.
	if caret.col == endpos.col and (not input or input == "") then
		print "avoided bogus case?"
		return
	end
	
	local o1, o2
	local currentline = self.buffer[caret.line]
	o1, o2, caret.col = Caret.selection_pos(currentline, caret.col, endpos.col)
	s1, s2 = currentline:sub(1, o1), currentline:sub(o2)
	
	if caret.col ~= endpos.col then
		if out then table.insert(out, currentline:sub(o1 + 1, o2 - 1)) end
		caret.x = math.min(caret.x, endpos.x)
	end
		
	if input == "\n" then
		self:setline(caret.line, s1)
		table.insert(self.buffer, caret.line + 1, s2)
		caret.col, caret.x, caret.line = 0, 0, caret.line + 1
		setcaret(endpos, caret)
		return out
	end
	
	local inputtype = type(input)
	if inputtype == "table" and #input == 1 then
		inputtype, input = type(input[1]), input[1]
	end
	
	if inputtype == "string" and input~= "" then
		s1 = s1 .. input
		caret.col, caret.x = caret.col + utf8.len(input), font:getWidth(s1)
		self:setline(caret.line, s1 .. s2)
	elseif inputtype == "table" and #input > 1 then
		self:setline(caret.line, s1 .. input[1])
		for i = 2, #input - 1 do
			caret.line = caret.line + 1
			table.insert(self.buffer, caret.line, input[i])
		end
		caret.line = caret.line + 1
		table.insert(self.buffer, caret.line, input[#input] .. s2)
		caret.col, caret.x = utf8.len(input[#input]), font:getWidth(input[#input])
	else
		self:setline(caret.line, s1 .. s2)
	end
	
	setcaret(endpos, caret)
	return out
end

function editor:draw()
	local font = self.font
	local fh = self.fh
	local caret, endpos = self.caret, self.endpos
	local ux, ul, lx, ll
	if caret.line > endpos.line then
		lx, ll, ux, ul = caret.x, caret.line, endpos.x, endpos.line
	elseif caret.line < endpos.line then
		ux, ul, lx, ll = caret.x, caret.line, endpos.x, endpos.line
	else
		ux, ul = math.min(caret.x, endpos.x), caret.line
		lx, ll = math.max(caret.x, endpos.x), ul
	end
	
	love.graphics.setFont(font)
	local carety = self.y + (caret.line - 1) * fh
	local endposy = self.y + (endpos.line - 1) * fh
	local textx = self.x + self.margin
	
	
	if ul ~= ll then
		love.graphics.setColor(0,0.7,1, 0.5)
		love.graphics.rectangle("fill", textx, self.y + (ll - 1) * fh, lx, self.fh)
		
		love.graphics.rectangle("fill", textx + ux, self.y + (ul - 1) * fh, font:getWidth(self.buffer[ul]) - ux, self.fh)
		for i = ll - 1, ul + 1, -1 do
			love.graphics.rectangle("fill", textx, self.y + (i - 1) * fh, font:getWidth(self.buffer[i]), self.fh)
		end
	elseif ux ~= lx then
		love.graphics.setColor(0,0.7,1, 0.5)
		love.graphics.rectangle("fill", textx + ux, carety, lx - ux, self.fh)
	end
	
	love.graphics.setColor(0,0,0)
	love.graphics.rectangle("fill", textx + caret.x, carety, 1, fh) -- caret
	love.graphics.rectangle("fill", textx + endpos.x, endposy - 2, 1, fh/2) -- caret
	for i, v in ipairs(self.buffer) do
		love.graphics.print(("%.3i"):format(i), self.x, self.y + fh * (i - 1))
		love.graphics.print(v, textx, self.y + fh * (i - 1))
	end

end

function editor:keypressed(key, scancode, isrepeat)
	local s1, s2
	local font = self.font
	local caret, endpos = self.caret, self.endpos
	local text = self.buffer[caret.line]
	local endtext = self.buffer[endpos.line]
	
	local multiline = caret.line ~= endpos.line
	local singleline = not multiline and caret.col ~= endpos.col
	local selected = multiline or singleline

	--local caretpos, endpos = caret.col, self.endpos
	--local caretx, endx = caret.x, endpos.x
	--local selected = (caretpos ~= endpos)
	
	if love.keyboard.isDown("lshift") then
		if key == "right" then
			local endlen = utf8.len(endtext)
			if endpos.col == endlen then
				if endpos.line == #self.buffer then return end
				endpos.col, endpos.x, endpos.line = 0, 0, endpos.line + 1
				return
			end
			s1, endpos.col = Caret.prefix(endtext, endpos.col + 1)
			endpos.x = font:getWidth(s1)
			return
		end
		
		if key == "left" then
			if endpos.col == 0 then
				if endpos.line == 1 then return end
				endpos.line = endpos.line - 1
				endtext = self.buffer[endpos.line]
				endpos.col, endpos.x = utf8.len(endtext), font:getWidth(endtext)
				return
			end
			s1, endpos.col = Caret.prefix(endtext, endpos.col - 1)
			endpos.x = font:getWidth(s1)
			return
		end
		
		if key == "home" then
			endpos.col, endpos.x = 0, 0
			return
		end
		
		if key == "end" then
			local len = utf8.len(text)
			if endpos.col ~= len then
				endpos.col, endpos.x = len, font:getWidth(text)
			end
			return
		end
		
		if key == "up" then
			if endpos.line > 1 then
				endpos.line = endpos.line - 1
			else
				endpos.line, endpos.col, endpos.x = 1, 0, 0
				return
			end
			if endpos.line == caret.line then
				setcaret(endpos, caret)
				return
			end
			text = self.buffer[endpos.line]
			endpos.col, endpos.x = utf8.len(text), font:getWidth(text)
			return
		end
		
		if key == "down" then
			if endpos.line < #self.buffer then
				endpos.line = endpos.line + 1
			end
			if endpos.line == caret.line then
				setcaret(endpos, caret)
				return
			end
			text = self.buffer[endpos.line]
			endpos.col, endpos.x = utf8.len(text), font:getWidth(text)
			return
		end
	end
	
	if love.keyboard.isDown("lctrl") then
		if isrepeat then return end
		
		if key == "a" then -- FIXME: doesn't work
			if caret.col > endpos.col then
				endpos.col, endpos.x = caret.col, caret.x
			end
			caret.col, caret.x = 0, 0
			local len = utf8.len(text)
			if endpos.col ~= len then
				endpos.col, endpos.x = len, font:getWidth(text)
			end
			return
		end
		if key == "v" then
			local input = love.system.getClipboardText()
			if input:match("\n") then
				input = split(input)
			end
			
			self:replace_selection(caret, endpos, input)
			return
		end
		if key == "x" then
			if not selected then return end -- nothing to cut
			local out = self:replace_selection(caret, endpos, nil, {})
			love.system.setClipboardText(table.concat(out, "\n"))
			return
		end
		if key == "c" then
			if not selected then return end -- nothing to copy
			local o1, o2
			if singleline then
				o1, o2 = Caret.selection_pos(text, caret.col, endpos.col)
				local selectedtext = text:sub(o1 + 1, o2 - 1)
				love.system.setClipboardText(selectedtext)
				return
			end
			
			local out = {}
			local ul, uc, ll, lc --upper/lower line/col
			if caret.line < endpos.line then
				ul, uc, ll, lc = caret.line, caret.col, endpos.line, endpos.col
			else
				ul, uc, ll, lc = endpos.line, endpos.col, caret.line, caret.col
			end
			local utext, ltext = self.buffer[ul], self.buffer[ll]
			local o1, o2 = Caret.pos(utext, uc), Caret.pos(ltext, lc)
			
			table.insert(out, utext:sub(o1 + 1)) -- suffix of upper
			for i = ll - 1, ul + 1, - 1 do
				table.insert(out, self.buffer[i])
			end
			table.insert(out, ltext:sub(1, o2)) -- prefix of lower
			love.system.setClipboardText(table.concat(out, "\n"))
			
			return
		end
	end
	
	if key == "right" then
		if selected then
			if caret.line < endpos.line then
				caret.line, caret.col, caret.x = endpos.line, endpos.col, endpos.x
			elseif caret.line == endpos.line then
				caret.col = math.max(caret.col, endpos.col)
				caret.x = math.max(caret.x, endpos.x)
			end
		else
			local len = utf8.len(text)
			if caret.col == len then
				if caret.line == #self.buffer then return end
				caret.col, caret.x, caret.line = 0, 0, caret.line + 1
			else
				s1, caret.col = Caret.prefix(text, caret.col + 1)
				caret.x = font:getWidth(s1)
			end
		end
		setcaret(endpos, caret)
		return
	end
	
	if key == "left" then
		if selected then
			if endpos.line < caret.line then
				caret.line, caret.col, caret.x = endpos.line, endpos.col, endpos.x
			elseif caret.line == endpos.line then
				caret.col = math.min(caret.col, endpos.col)
				caret.x = math.min(caret.x, endpos.x)
			end
		else
			if caret.col == 0 then
				if caret.line == 1 then return end
				caret.line = caret.line - 1
				text = self.buffer[caret.line]
				caret.col, caret.x = utf8.len(text), font:getWidth(text)
			else
				s1, caret.col = Caret.prefix(text, caret.col - 1)
				caret.x = font:getWidth(s1)
			end
		end
		setcaret(endpos, caret)
		return
	end

	if key == "delete" then
		if selected then
			self:replace_selection(caret, endpos)
			return
		end
		
		local len = utf8.len(text)
		if caret.col == len and caret.line < #self.buffer then
			local nextline = self.buffer[caret.line + 1]
			table.remove(self.buffer, caret.line + 1)
			self:setline(caret.line, text .. nextline)
			setcaret(endpos, caret)
			return
		end
		s1, s2, caret.col = Caret.delete(text, caret.col)
		caret.x = font:getWidth(s1)
		
		self:setline(caret.line, s1 .. s2)
		setcaret(endpos, caret)
		return
	end

	if key == "backspace" then
		if selected then
			self:replace_selection(caret, endpos)
			return
		end
		
		if caret.col == 0 and caret.line > 1 then
			local prevline = self.buffer[caret.line - 1]
			caret.col, caret.x = utf8.len(prevline), font:getWidth(prevline)
			table.remove(self.buffer, caret.line)
			caret.line = caret.line - 1
			self:setline(caret.line, prevline .. text)
			setcaret(endpos, caret)
			return
		end
		s1, s2, caret.col = Caret.backspace(text, caret.col)
		caret.x = font:getWidth(s1)
		
		self:setline(caret.line, s1 .. s2)
		setcaret(endpos, caret)
		return
	end
	
	if key == "home" then
		caret.col, caret.x = 0, 0
		setcaret(endpos, caret)
		return
	end
	
	if key == "end" then
		local len = utf8.len(text)
		if caret.col ~= len then 
			caret.col, caret.x = len, font:getWidth(text)
		end
		setcaret(endpos, caret)
		return
	end
	
	if key == "return" then
		if selected then
			self:replace_selection(caret, endpos, "\n")
			return
		end
		
		s1, s2 = Caret.split(text, caret.col)
		self:setline(caret.line, s1)
		table.insert(self.buffer, caret.line + 1, s2)
		caret.col, caret.x, caret.line = 0, 0, caret.line + 1
		setcaret(endpos, caret)
		return
	end
	
	if key == "up" then
		caret.line = math.max(caret.line - 1, 1)
		text = self.buffer[caret.line]
		caret.col = math.min(caret.col, utf8.len(text))
		caret.x = font:getWidth(Caret.prefix(text, caret.col))
		setcaret(endpos, caret)
		return
	end
	
	if key == "down" then
		caret.line = math.min(caret.line + 1, #self.buffer)
		text = self.buffer[caret.line]
		caret.col = math.min(caret.col, utf8.len(text))
		caret.x = font:getWidth(Caret.prefix(text, caret.col))
		setcaret(endpos, caret)
		return
	end
end


function editor:textinput(input)
	self:replace_selection(self.caret, self.endpos, input)
end


return M
