local utf8 = require "utf8"
local lexer = require "lexer"
local Caret = require "caret"


local _min, _max = math.min, math.max

-- START COLORS

 -- this assumes h:[0, 6] & s:[0, 1], l:[0, 1]
local hsl2rgb = function(h, s, l, a)
	if s <= 0 then return l, l, l, a end
	local c = 2 * s * ((l > 0.5) and (1 - l) or l)
	local r, g, b
	if     h < 1 then b, r, g = 0, c, c * h
	elseif h < 2 then b, g, r = 0, c, c * (2 - h)
	elseif h < 3 then r, g, b = 0, c, c * (h - 2)
	elseif h < 4 then r, b, g = 0, c, c * (4 - h)
	elseif h < 5 then g, b, r = 0, c, c * (h - 4)
	else              g, r, b = 0, c, c * (6 - h)
	end
	local m = l - c / 2
	return (r + m), (g + m), (b + m), a
end

local clamp = function(x, min, max) return _min(max, _max(min, x)) end

local hsl = function(H, S, L, A)
	local r, g, b = hsl2rgb((H % 360) / 60, clamp(S, 0, 100) / 100, clamp(L, 0, 100) / 100)
	if not A then return {r, g, b, 1} end
	return {r, g, b, clamp(A, 0, 100) / 100}
end

local colors = {
	fore = hsl(0, 0, 0), back = hsl(20, 100, 95), operator = hsl(200, 50, 15),
	keyword = hsl(150, 65, 35), string = hsl(340, 60, 30), comment = hsl(0, 0, 50),
	number = hsl(200, 80, 50), iden = hsl(200, 60, 25), --line = {1 , 0, 0},
	idenlovepre = hsl(340, 75, 60), idenlove = hsl(200, 50, 45),
}

colors.activeline = hsl(50, 100, 50)
colors.padding = hsl(200, 100, 93)

local operators = {'+', '-', '/', '*', '%', '=', '<', '>', '<=', '>=', '~=', '==', '#'}
for i, v in ipairs(operators) do operators[v] = true end

local colorize_line = function(text)
	local coloredline = {}
	local color
	for k, v in lexer.lua(text, {}, {}) do
		color = (operators[k] and colors.operator) or colors[k] or colors.fore
		table.insert(coloredline, color)
		table.insert(coloredline, v)
	end
	return coloredline
end
-- FINISH COLORS

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

-- base_col is for up/down movement as base column
local function caret_rebase(c)
	c.base_col = c.col
end

local function caret_zero(c)
	c.line, c.col, c.x = 1, 0, 0
	c.base_col = 0
end

local function caret_eq(dst, src)
	dst.line, dst.col, dst.x = src.line, src.col, src.x
	dst.base_col = src.base_col
end

local function caret_set(dst, src)
	dst.line, dst.col, dst.x = src.line, src.col, src.x
end

local function view_new(buffer)
	local view = {}
	for i, v in ipairs(buffer) do
		table.insert(view, colorize_line(v))
	end
	return view
end

M.new = function(data, highlight)
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
		buffer = buffer, highlight = highlight,
		pivot  = {}, endpos = {},
		x = 5, y = 5,
		font = font, fh = font:getHeight(),
		margin = font:getWidth("88888"),
	}
	if e.highlight then e.view = view_new(e.buffer) end
	
	caret_zero(e.pivot) caret_zero(e.endpos)
	return setmetatable(e, M.meta)
end

-- MODULE END

function editor:resetcarets(line, col, x)
	caret_zero(self.pivot)
	caret_zero(self.endpos)
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
	self.view = nil
	if self.highlight then self.view = view_new(self.buffer) end
end

function editor:load(s)
	self:resetcarets()
	self.buffer = split(s)
	self.view = nil
	if self.highlight then self.view = view_new(self.buffer) end
end


function editor:setline(lineno, s)
	local buffer = self.buffer
	assert(lineno >= 1 and lineno <= #buffer, "lineno out of bounds")
	
	buffer[lineno] = s
	if self.view then  self.view[lineno] = colorize_line(s) end
end

function editor:removeline(lineno)
	if self.view then table.remove(self.view, lineno) end
	return table.remove(self.buffer, lineno)
end

function editor:insertline(lineno, s)
	table.insert(self.buffer, lineno, s)
	if self.view then table.insert(self.view, lineno, colorize_line(s)) end
end


function editor:replace_selection(pivot, endpos, input, out)
	local s1, s2
	local font = self.font
	if pivot.line ~= endpos.line then
		local ul, uc, ll, lc, ux --upper/lower line/col/x
		if pivot.line < endpos.line then
			ux, ul, uc, ll, lc = pivot.x, pivot.line, pivot.col, endpos.line, endpos.col
		else
			ux, ul, uc, ll, lc = endpos.x, endpos.line, endpos.col, pivot.line, pivot.col
		end
		local utext, ltext = self.buffer[ul], self.buffer[ll]
		local o1, o2 = (Caret.pos(utext, uc)), (Caret.pos(ltext, lc))
		s1 = utext:sub(1, o1) -- prefix of upper
		s2 = ltext:sub(o2 + 1) -- suffix of lower
		
		if out then
			table.insert(out, utext:sub(o1 + 1)) -- suffix of upper
			for i = ll - 1, ul + 1, - 1 do
				table.insert(out, self:removeline(i))
			end
			table.insert(out, ltext:sub(1, o2)) -- prefix of lower
		else
			for i = ll - 1, ul + 1, - 1 do
				self:removeline(i) -- remove fully selected lines
			end
		end
		
		if input == "\n" then
			self:setline(ul, s1)
			self:setline(ul + 1, s2)
			endpos.col, endpos.x, endpos.line = 0, 0, ul + 1
			caret_rebase(endpos)
			caret_eq(pivot, endpos)
			return out
		end
		
		endpos.line = ul
		local inputtype = type(input)
		if inputtype == "table" and #input == 1 then
			inputtype, input = type(input[1]), input[1]
		end
		
		if inputtype == "string" and input ~= "" then
			s1 = s1 .. input
			endpos.col, endpos.x = uc + utf8.len(input), font:getWidth(s1)
			self:setline(ul, s1 .. s2)
			self:removeline(ul + 1)
		elseif inputtype == "table" and #input > 1 then
			self:setline(endpos.line, s1 .. input[1])
			for i = 2, #input - 1 do
				endpos.line = endpos.line + 1
				self:insertline(endpos.line, input[i])
			end
			endpos.line = endpos.line + 1
			self:setline(endpos.line, input[#input] .. s2)
			endpos.col, endpos.x = utf8.len(input[#input]), font:getWidth(input[#input])
		else
			endpos.col, endpos.x = uc, ux
			self:setline(ul, s1 .. s2)
			self:removeline(ul + 1)
		end
		caret_rebase(endpos)
		caret_eq(pivot, endpos)
		return out
	end
	
	local selected = (pivot.col ~= endpos.col)
	-- also if empty table.
	if not selected and (not input or input == "") then
		print "avoided bogus case?"
		return
	end
	
	local o1, o2
	local currentline = self.buffer[endpos.line]
	o1, o2, endpos.col = Caret.selection_pos(currentline, pivot.col, endpos.col)
	s1, s2 = currentline:sub(1, o1), currentline:sub(o2)
	
	if selected then
		if out then table.insert(out, currentline:sub(o1 + 1, o2 - 1)) end
		endpos.x = math.min(pivot.x, endpos.x)
	end
		
	if input == "\n" then
		self:setline(endpos.line, s1)
		self:insertline(endpos.line + 1, s2)
		endpos.col, endpos.x, endpos.line = 0, 0, endpos.line + 1
		caret_rebase(endpos)
		caret_eq(pivot, endpos)
		return out
	end
	
	local inputtype = type(input)
	if inputtype == "table" and #input == 1 then
		inputtype, input = type(input[1]), input[1]
	end
	
	if inputtype == "string" and input~= "" then
		s1 = s1 .. input
		endpos.col, endpos.x = endpos.col + utf8.len(input), font:getWidth(s1)
		self:setline(endpos.line, s1 .. s2)
	elseif inputtype == "table" and #input > 1 then
		self:setline(endpos.line, s1 .. input[1])
		for i = 2, #input - 1 do
			endpos.line = endpos.line + 1
			self:insertline(endpos.line, input[i])
		end
		endpos.line = endpos.line + 1
		self:insertline(endpos.line, input[#input] .. s2)
		endpos.col, endpos.x = utf8.len(input[#input]), font:getWidth(input[#input])
	else
		self:setline(endpos.line, s1 .. s2)
	end
	
	caret_rebase(endpos)
	caret_eq(pivot, endpos)
	return out
end

function editor:draw()
	local font = self.font
	local fh = self.fh
	local pivot, endpos = self.pivot, self.endpos
	local ux, ul, lx, ll
	if pivot.line > endpos.line then
		lx, ll, ux, ul = pivot.x, pivot.line, endpos.x, endpos.line
	elseif pivot.line < endpos.line then
		ux, ul, lx, ll = pivot.x, pivot.line, endpos.x, endpos.line
	else
		ux, ul = math.min(pivot.x, endpos.x), pivot.line
		lx, ll = math.max(pivot.x, endpos.x), ul
	end
	
	love.graphics.setFont(font)
	local pivoty = self.y + (pivot.line - 1) * fh
	local endposy = self.y + (endpos.line - 1) * fh
	local textx = self.x + self.margin
	
	
	if ul ~= ll then
		love.graphics.setColor(0, 0.7, 1, 0.15)
		love.graphics.rectangle("fill", textx, self.y + (ll - 1) * fh, lx, self.fh)
		
		love.graphics.rectangle("fill", textx + ux, self.y + (ul - 1) * fh, font:getWidth(self.buffer[ul]) - ux, self.fh)
		for i = ll - 1, ul + 1, -1 do
			love.graphics.rectangle("fill", textx, self.y + (i - 1) * fh, font:getWidth(self.buffer[i]), self.fh)
		end
	elseif ux ~= lx then
		love.graphics.setColor(0, 0.7, 1, 0.15)
		love.graphics.rectangle("fill", textx + ux, pivoty, lx - ux, self.fh)
	end
	
	love.graphics.setColor(0,0,0)
	--love.graphics.rectangle("fill", textx + pivot.x, pivoty - 2, 1, fh / 2) -- pivot
	--if math.floor(love.timer.getTime() * 10) % 10 < 5 then
		love.graphics.rectangle("fill", textx + endpos.x, endposy, 1, fh) -- endpos
	--end
	love.graphics.setColor(colors.comment)
	for i = 1, #self.buffer do
		love.graphics.print(("%.3i"):format(i), self.x, self.y + fh * (i - 1))
	end
	
	local lines
	if self.view then lines = self.view; love.graphics.setColor(1,1,1)
	else lines = self.buffer; love.graphics.setColor(colors.fore) end
	for i, v in ipairs(lines) do
		love.graphics.print(v, textx, self.y + fh * (i - 1))
	end

end

function editor:keypressed(key, scancode, isrepeat)
	local s1, s2
	local font = self.font
	local pivot, endpos = self.pivot, self.endpos
	local text = self.buffer[pivot.line]
	local endtext = self.buffer[endpos.line]
	
	local multiline = pivot.line ~= endpos.line
	local singleline = not multiline and pivot.col ~= endpos.col
	local selected = multiline or singleline

	--local caretpos, endpos = pivot.col, self.endpos
	--local caretx, endx = pivot.x, endpos.x
	--local selected = (caretpos ~= endpos)
	
	if love.keyboard.isDown("lshift") then
		if key == "right" then
			local endlen = utf8.len(endtext)
			if endpos.col == endlen then
				if endpos.line < #self.buffer then
					endpos.col, endpos.x, endpos.line = 0, 0, endpos.line + 1
				end
			else
				s1, endpos.col = Caret.prefix(endtext, endpos.col + 1)
				endpos.x = font:getWidth(s1)
			end
			caret_rebase(endpos)
			return
		end
		
		if key == "left" then
			if endpos.col == 0 then
				if endpos.line > 1 then
					endpos.line = endpos.line - 1
					endtext = self.buffer[endpos.line]
					endpos.col, endpos.x = utf8.len(endtext), font:getWidth(endtext)
				end
			else
				s1, endpos.col = Caret.prefix(endtext, endpos.col - 1)
				endpos.x = font:getWidth(s1)
			end
			caret_rebase(endpos)
			return
		end
		
		if key == "home" then
			endpos.col, endpos.x = 0, 0
			caret_rebase(endpos)
			return
		end
		
		if key == "end" then
			local len = utf8.len(text)
			if endpos.col ~= len then
				endpos.col, endpos.x = len, font:getWidth(text)
			end
			caret_rebase(endpos)
			return
		end
		
		if key == "up" then
			if endpos.line <= 1 then
				endpos.line, endpos.col, endpos.x = 1, 0, 0
				return
			end
			
			endpos.line = endpos.line - 1
			text = self.buffer[endpos.line]
			endpos.col = math.min(endpos.base_col, utf8.len(text))
			endpos.x = font:getWidth(Caret.prefix(text, endpos.col))
			return
		end
		
		if key == "down" then
			if endpos.line >= #self.buffer then
				endpos.line = #self.buffer
				text = self.buffer[endpos.line]
				endpos.col, endpos.x = utf8.len(text), font:getWidth(text)
				return
			end
			
			endpos.line = endpos.line + 1
			text = self.buffer[endpos.line]
			endpos.col = math.min(endpos.base_col, utf8.len(text))
			endpos.x = font:getWidth(Caret.prefix(text, endpos.col))
			return
		end
	end
	
	if love.keyboard.isDown("lctrl") then
		if isrepeat then return end
		
		if key == "a" then
			endpos.line, endpos.col, endpos.x = 1, 0, 0
			pivot.line = #self.buffer
			text = self.buffer[pivot.line]
			pivot.col, pivot.x = utf8.len(text), font:getWidth(text)
			return
		end
		
		if key == "v" then
			local input = love.system.getClipboardText()
			if input:match("\n") then
				input = split(input)
			end
			
			self:replace_selection(pivot, endpos, input)
			return
		end
		if key == "x" then
			if not selected then return end -- nothing to cut
			local out = self:replace_selection(pivot, endpos, nil, {})
			love.system.setClipboardText(table.concat(out, "\n"))
			return
		end
		if key == "c" then
			if not selected then return end -- nothing to copy
			local o1, o2
			if singleline then
				o1, o2 = Caret.selection_pos(text, pivot.col, endpos.col)
				local selectedtext = text:sub(o1 + 1, o2 - 1)
				love.system.setClipboardText(selectedtext)
				return
			end
			
			local out = {}
			local ul, uc, ll, lc --upper/lower line/col
			if pivot.line < endpos.line then
				ul, uc, ll, lc = pivot.line, pivot.col, endpos.line, endpos.col
			else
				ul, uc, ll, lc = endpos.line, endpos.col, pivot.line, pivot.col
			end
			local utext, ltext = self.buffer[ul], self.buffer[ll]
			local o1, o2 = (Caret.pos(utext, uc)), (Caret.pos(ltext, lc))
			
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
			if pivot.line > endpos.line then
				endpos.line, endpos.col, endpos.x = pivot.line, pivot.col, pivot.x
			elseif pivot.line == endpos.line then
				endpos.col = math.max(pivot.col, endpos.col)
				endpos.x = math.max(pivot.x, endpos.x)
			end
		else
			local len = utf8.len(text)
			if endpos.col == len then
				if endpos.line == #self.buffer then return end
				endpos.col, endpos.x, endpos.line = 0, 0, endpos.line + 1
			else
				s1, endpos.col = Caret.prefix(text, endpos.col + 1)
				endpos.x = font:getWidth(s1)
			end
		end
		caret_rebase(endpos)
		caret_eq(pivot, endpos)
		return
	end
	
	if key == "left" then
		if selected then
			if pivot.line < endpos.line then
				endpos.line, endpos.col, endpos.x = pivot.line, pivot.col, pivot.x
			elseif pivot.line == endpos.line then
				endpos.col = math.min(pivot.col, endpos.col)
				endpos.x = math.min(pivot.x, endpos.x)
			end
		else
			if endpos.col == 0 then
				if endpos.line == 1 then return end
				endpos.line = endpos.line - 1
				text = self.buffer[endpos.line]
				endpos.col, endpos.x = utf8.len(text), font:getWidth(text)
			else
				s1, endpos.col = Caret.prefix(text, endpos.col - 1)
				endpos.x = font:getWidth(s1)
			end
		end
		caret_rebase(endpos)
		caret_eq(pivot, endpos)
		return
	end
	
	if key == "home" then
		endpos.col, endpos.x = 0, 0
		caret_rebase(endpos)
		caret_eq(pivot, endpos)
		return
	end
	
	if key == "end" then
		local len = utf8.len(text)
		if endpos.col ~= len then 
			endpos.col, endpos.x = len, font:getWidth(text)
		end
		caret_rebase(endpos)
		caret_eq(pivot, endpos)
		return
	end
	
	if key == "up" then
		if endpos.line <= 1 then
			--assert(endpos.line == 1, "endpos overflow up")
			endpos.col, endpos.x = 0, 0
		else
			endpos.line = endpos.line - 1
			text = self.buffer[endpos.line]
			endpos.col = math.min(endpos.base_col, utf8.len(text))
			endpos.x = font:getWidth(Caret.prefix(text, endpos.col))
		end
		caret_eq(pivot, endpos)
		return
	end
	
	if key == "down" then
		if endpos.line >= #self.buffer then
			--assert(endpos.line == #self.buffer, "endpos overflow down")
			text = self.buffer[endpos.line]
			local len = utf8.len(text)
			if endpos.col ~= len then
				endpos.col, endpos.x = len, font:getWidth(text)
			end
		else
			endpos.line = endpos.line + 1
			text = self.buffer[endpos.line]
			endpos.col = math.min(endpos.base_col, utf8.len(text))
			endpos.x = font:getWidth(Caret.prefix(text, endpos.col))
		end
		caret_eq(pivot, endpos)
		return
	end
	
	if key == "delete" then
		if selected then
			self:replace_selection(pivot, endpos)
			return
		end
		
		local len = utf8.len(text)
		if endpos.col == len and endpos.line < #self.buffer then
			local nextline = self.buffer[endpos.line + 1]
			self:removeline(endpos.line + 1)
			self:setline(endpos.line, text .. nextline)
			caret_rebase(endpos)
			caret_eq(pivot, endpos)
			return
		end
		s1, s2, endpos.col = Caret.delete(text, endpos.col)
		endpos.x = font:getWidth(s1)
		
		self:setline(endpos.line, s1 .. s2)
		caret_rebase(endpos)
		caret_eq(pivot, endpos)
		return
	end

	if key == "backspace" then
		if selected then
			self:replace_selection(pivot, endpos)
			return
		end
		
		if endpos.col == 0 and endpos.line > 1 then
			local prevline = self.buffer[endpos.line - 1]
			endpos.col, endpos.x = utf8.len(prevline), font:getWidth(prevline)
			self:removeline(endpos.line)
			endpos.line = endpos.line - 1
			self:setline(endpos.line, prevline .. text)
			caret_rebase(endpos)
			caret_eq(pivot, endpos)
			return
		end
		s1, s2, endpos.col = Caret.backspace(text, endpos.col)
		endpos.x = font:getWidth(s1)
		
		self:setline(endpos.line, s1 .. s2)
		caret_rebase(endpos)
		caret_eq(pivot, endpos)
		return
	end
	
	if key == "return" then
		self:replace_selection(pivot, endpos, "\n")
		return
	end
end


function editor:textinput(input)
	self:replace_selection(self.pivot, self.endpos, input)
end

M.colors = colors
return M
