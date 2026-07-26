on stonecold
  global soundspathstart, gWinDriveLetter, Whichins2, Whichins, savepath, cdsavepath
  savepath = the moviePath
  if the machineType = 256 then
    soundspathstart = the moviePath & "sounds\"
    Whichins = "smallins"
    cdsavepath = the moviePath & "pip2data\"
    Whichins2 = the moviePath
  else
    getMacDiscInfo()
  end if
end

on getWinInfo
end

on getMacDiscInfo
  global soundspathstart, Whichins, Whichins2, savepath, cdsavepath
  savepath = the moviePath
  soundspathstart = the moviePath & "sounds:"
  cdsavepath = the moviePath & "pip2data:"
  Whichins = "smallins"
  Whichins2 = the moviePath
end
