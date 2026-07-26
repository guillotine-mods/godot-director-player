on exitFrame
  global globalnight, globalday
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
