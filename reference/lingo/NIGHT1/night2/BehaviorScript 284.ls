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
end
