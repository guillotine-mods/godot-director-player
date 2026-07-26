on exitFrame
  global soundspath, effectspath, globalnight, globalday
  sound playFile 1, soundspath & "brokdor.aif"
  sound playFile 2, effectspath & "lilopen.aif"
  if (globalday = 2) and (item 2 of globalnight = "0") then
    x = value(the text of field "points" of castLib "master")
    x = x + 1
    if x < 10 then
      put "00" & x into field "points" of castLib "master"
    else
      put "0" & x into field "points" of castLib "master"
    end if
  end if
end
