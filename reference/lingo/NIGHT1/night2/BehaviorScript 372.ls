on exitFrame
  global soundspath, globalnight
  repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
    if line i of field "objectsfield" of castLib "master" = "fakbok" then
      objplc = i
    end if
  end repeat
  repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
    put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
  end repeat
  put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
  displayobject()
  x = "continue"
  repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
    if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
      put "orgbok" into line i of field "objectsfield" of castLib "master"
      x = "stop"
    end if
  end repeat
  put "done" into item 2 of line 5 of field "Dprocess" of castLib "master"
  x = value(the text of field "points" of castLib "master")
  x = x + 1
  if x < 10 then
    put "00" & x into field "points" of castLib "master"
  else
    put "0" & x into field "points" of castLib "master"
  end if
  displayobject()
  sound playFile 1, soundspath & "pforgbok.aif"
  put 1 into item 2 of globalnight
  sprite(17).visible = 1
  sprite(30).visible = 1
  go("inside")
end
