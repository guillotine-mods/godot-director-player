on fillnames
  global SaveNames, Whichins, Whichins2, cdsavepath
  i = 1
  repeat while i <= 8
    put field("gamename" & i) into item i of SaveNames
    i = 1 + i
  end repeat
  go("savegame2", cdsavepath & "saveload.dxr")
end
