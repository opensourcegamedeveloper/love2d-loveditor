local printf = function(fmt, ...) print(fmt:format(...)) end

local errhand = love.errhand

local M = {}

local callbacks = {
	"draw",
	"errhand",
	"errorhandler",
	"load",
	"lowmemory",
	"quit",
	"run",
	"threaderror",
	"update",

	"directorydropped",
	"filedropped",
	"focus",
	"mousefocus",
	"resize",
	"visible",

	"keypressed",
	"keyreleased",
	"textedited",
	"textinput",

	"mousemoved",
	"mousepressed",
	"mousereleased",
	"wheelmoved",

	"gamepadaxis",
	"gamepadpressed",
	"gamepadreleased",
	"joystickadded",
	"joystickaxis",
	"joystickhat",
	"joystickpressed",
	"joystickreleased",
	"joystickremoved",

	"touchmoved",
	"touchpressed",
	"touchreleased",
}

local clearCallbacks = function()
	for k,v in ipairs(callbacks) do love[v] = nil end
end

local restart = function()
	setmetatable(love, nil)
	love.quit = nil
	love.event.quit("restart")
end

local quitHook = function(quitf)
	return function()
		if quitf then quitf() end
		restart()
		return true
	end
end

local onError = function() return "restart" end
local errorHandler = function(msg)
	printf("Error: %s", msg)
	return onError
end

local keypressedHook = function(keypressedf)
	return function(k, sc, rpt)
		if k == "escape" then restart()
		elseif keypressedf then keypressedf(k, sc, rpt) end
	end
end


local avReset = function()
	love.audio.stop()
	love.mouse.setCursor()
	love.mouse.setVisible(true)
	love.mouse.setGrabbed(false)
	love.mouse.setRelativeMode(false)
	love.keyboard.setKeyRepeat(false)
	love.graphics.reset()
end

M.run = function(file, ...)
	if not love.filesystem.getInfo(file) then
		printf("File '%s' does not exit", file)
		return
	end
	
	local ok, result = pcall(love.filesystem.load, file)
	if not ok then
		printf("(Load) %s", result)
		return
	end
	
	local protected = {}
	protected.keypressed = keypressedHook()
	protected.quit = quitHook()
	protected.errhand = errhand
	protected.errorhandler = errorHandler
	
	setmetatable(love, {
		__index = protected,
		__newindex = function(t, k, v)
			if not protected[k] then rawset(t, k, v) return end
			
			if k == "keypressed" then protected[k] = keypressedHook(v) return end
			if k == "quit" then protected[k] = quitHook(v) return end
		end
	})
	
	clearCallbacks()
	
	ok, result = pcall(result, file, ...)
	if not ok then
		printf("(Run) %s", result)
		restart()
		return
	end

	avReset()
	
	love.window.setTitle(file)
	if love.load then love.load() end
	return true
end

return M

