on exitFrame
  global gWinDriveLetter, soundspathstart
  the searchPath = ["a:\sounds\strtgame\"]
  x = getAt(the searchPath, 1)
  sound playFile 1, x & "egozcold.aif"
  if soundBusy(1) then
    alfred = x
    gWinDriveLetter = char 1 of line 1 of alfred
    soundspathstart = gWinDriveLetter & ":\sounds\"
  else
    go("option26")
  end if
end
