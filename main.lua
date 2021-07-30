local SAVEFILE = "saved.lua"

local Editor = require "editor"
local Runner = require "runner"

love.keyboard.setKeyRepeat(true)
love.graphics.setBackgroundColor(Editor.colors.back)

local editor = Editor.new(nil, true)

editor:loadfile(SAVEFILE)


love.quit = function()
	print("quit")
	editor:savefile(SAVEFILE)
	return false
end


love.draw = function()
	editor:draw()
end

love.keypressed = function(k, sc, rpt)
	if love.keyboard.isDown("lctrl") and not rpt then
		if k == "s" then editor:savefile(SAVEFILE) return end
		if k == "r" then
			editor:savefile(SAVEFILE)
			Runner.run(SAVEFILE)
		end
	end
	editor:keypressed(k, sc, rpt)
end

love.textinput = function(input)
	editor:textinput(input)
end