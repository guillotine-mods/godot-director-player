on exitFrame
  global gWinDriveLetter, soundspathstart, cdsavepath
  the searchPath = ["n:\sounds\strtgame\"]
  x = getAt(the searchPath, 1)
  sound playFile 1, x & "egozcold.aif"
  if soundBusy(1) then
    alfred = x
    gWinDriveLetter = char 1 of line 1 of alfred
    soundspathstart = gWinDriveLetter & ":\sounds\"
    cdsavepath = gWinDriveLetter & ":\pip2data\"
  else
    go("option13")
  end if
end
