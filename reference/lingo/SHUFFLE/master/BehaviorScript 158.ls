on exitFrame
  set the visible of sprite 102 to 1
  repeat with i = 1 to 20
    puppetSprite(i, 0)
  end repeat
  go("mainmenu")
  set the visible of sprite 100 to 1
  set the locH of sprite 4 to 197
  set the locV of sprite 4 to 360
  set the locH of sprite 11 to 197
  set the locV of sprite 11 to 360
  put the locH of sprite 4 into item 1 of sfl2
  put the locV of sprite 4 into item 2 of sfl2
  put 0 into item 3 of sfl
  updateStage()
end
