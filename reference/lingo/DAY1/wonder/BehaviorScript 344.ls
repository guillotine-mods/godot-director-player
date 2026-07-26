on exitFrame
  repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
    if line i of field "objectsfield" of castLib "master" = "wine" then
      objplc = i
    end if
  end repeat
  repeat with i = objplc + 1 to the number of lines in field "objectsfield" of castLib "master"
    put line i of field "objectsfield" of castLib "master" into line i - 1 of field "objectsfield" of castLib "master"
  end repeat
  put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
  x = value(the text of field "points" of castLib "master")
  x = x - 1
  if x < 10 then
    put "00" & x into field "points" of castLib "master"
  else
    put "0" & x into field "points" of castLib "master"
  end if
  put "taken" into item 8 of line 6 of field "Dprocess" of castLib "master"
  displayobject()
  play done
end
