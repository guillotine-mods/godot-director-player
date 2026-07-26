on exitFrame
  global soundspath
  oneortwo = 0
  moneycount = 0
  x = "continue"
  repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
    if line i of field "objectsfield" of castLib "master" contains "money" then
      oneortwo = line i of field "objectsfield" of castLib "master"
      moneycount = moneycount + 1
    end if
  end repeat
  if moneycount > 1 then
    sound playFile 1, soundspath & "nomony.aif"
  else
    if (oneortwo = "money2") or (oneortwo = 0) then
      x = "continue"
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
          put "money1" into line i of field "objectsfield" of castLib "master"
          x = "stop"
        end if
      end repeat
      sound playFile 1, soundspath & "pfmoney1.aif"
    else
      x = "continue"
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
          put "money2" into line i of field "objectsfield" of castLib "master"
          x = "stop"
        end if
      end repeat
      sound playFile 1, soundspath & "pfmoney2.aif"
    end if
  end if
end
