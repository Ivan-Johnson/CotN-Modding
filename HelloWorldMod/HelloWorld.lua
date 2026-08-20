print("Hello world from Hello World Mod!")

event.gameStateLevel.add("helloWorldOnLevelStart", "config", function ()
	print("Hello world from a level start event!")
end)
