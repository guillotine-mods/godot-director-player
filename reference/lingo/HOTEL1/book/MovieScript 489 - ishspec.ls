on ishspec
  vvv = 0
  monn = 0
  x = "no"
  repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
    if (line i of field "objectsfield" of castLib "master" = "chairs") and (x = "no") then
      x = "stop"
    end if
  end repeat
  if x = "no" then
    if item 1 of line 6 of field "dprocess" = "done" then
      x = "stop"
    end if
  end if
  if x = "no" then
    y = "continue"
    repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
      if (line i of field "objectsfield" of castLib "master" = "empty") and (y = "continue") then
        put "chairs" into line i of field "objectsfield" of castLib "master"
        y = "stop"
      end if
    end repeat
    y = "continue"
    repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
      if (line i of field "objectsfield" of castLib "master" = "empty") and (y = "continue") then
        put "chair2" into line i of field "objectsfield" of castLib "master"
        y = "stop"
      end if
    end repeat
    vvv = "money1"
    monn = "pay"
    put "done" into item 1 of line 6 of field "Dprocess" of castLib "master"
    x = value(the text of field "points" of castLib "master")
    x = x + 1
    if x < 10 then
      put "00" & x into field "points" of castLib "master"
    else
      put "0" & x into field "points" of castLib "master"
    end if
    displayobject()
  else
    x = "no"
    repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
      if (line i of field "objectsfield" of castLib "master" = "wine") and (x = "no") then
        x = "stop"
        vvv = "money4"
      end if
    end repeat
    if x = "no" then
      if item 8 of line 6 of field "dprocess" = "done" then
        x = "stop"
        vvv = "money4"
      end if
    end if
    if x = "no" then
      y = "continue"
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if (line i of field "objectsfield" of castLib "master" = "empty") and (y = "continue") then
          put "wine" into line i of field "objectsfield" of castLib "master"
          y = "stop"
        end if
      end repeat
      if item 8 of line 6 of field "Dprocess" of castLib "master" = "taken" then
        vvv = "money3"
      else
        vvv = "money2"
      end if
      monn = "pay"
      put "done" into item 2 of line 6 of field "Dprocess" of castLib "master"
      x = value(the text of field "points" of castLib "master")
      x = x + 1
      if x < 10 then
        put "00" & x into field "points" of castLib "master"
      else
        put "0" & x into field "points" of castLib "master"
      end if
      displayobject()
    end if
  end if
  if monn = "pay" then
    objplc = 0
    repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
      if line i of field "objectsfield" of castLib "master" = "money1" then
        objplc = i
      end if
    end repeat
    if objplc = 0 then
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if line i of field "objectsfield" of castLib "master" = "money2" then
          objplc = i
        end if
      end repeat
    end if
    repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
      put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
    end repeat
    put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
    displayobject()
  else
  end if
  objecttalktime(vvv)
end
