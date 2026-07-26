on exitFrame
  repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
    if line i of field "objectsfield" of castLib "master" = "pirats" then
      objplc = i
    end if
  end repeat
  repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
    put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
  end repeat
  put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
  displayobject()
  put "done" into item 9 of line 2 of field "Dprocess" of castLib "master"
  x = value(the text of field "points" of castLib "master")
  x = x + 1
  if x < 10 then
    put "00" & x into field "points" of castLib "master"
  else
    put "0" & x into field "points" of castLib "master"
  end if
end
