on exitFrame
  global soundspath
  x = "continue"
  repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
    if (line i of field "objectsfield" of castLib "master" = "empty") and (x = "continue") then
      put "fakbok" into line i of field "objectsfield" of castLib "master"
      x = "stop"
    end if
  end repeat
  displayobject()
  play done
end
