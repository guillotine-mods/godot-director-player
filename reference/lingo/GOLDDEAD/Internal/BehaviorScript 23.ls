on exitFrame
  global tlkpath
  repeat with i = 3 to 30
    sprite(i).visible = 1
    puppetSprite(i, 0)
  end repeat
  repeat with i = 100 to 110
    puppetSprite(i, 0)
  end repeat
  if the freeBlock < (100 * 1024) then
    unloadMovie(the moviePath & "day1.dxr")
  end if
  sound playFile 1, tlkpath & "hez76.aif"
  sound stop 2
end
