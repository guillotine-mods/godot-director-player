on mouseUp
  global effectspath
  sound playFile 1, effectspath & "clik1.aif"
  i = 1
  repeat while (i < (the number of lines in field "objectsfield" of castLib "master" - 1)) and (line i of field "objectsfield" of castLib "master" <> "empty")
    theobj = line i of field "objectsfield" of castLib "master"
    y = i + 1
    repeat while (y < the number of lines in field "objectsfield" of castLib "master") and (line y of field "objectsfield" of castLib "master" <> "empty")
      if theobj = line y of field "objectsfield" of castLib "master" then
        repeat with z = y + 1 to the number of lines in field "objectsfield" of castLib "master"
          put line z of field "objectsfield" of castLib "master" into line z - 1 of field "objectsfield" of castLib "master"
        end repeat
        put "empty" into line the number of lines in field "objectsfield" of castLib "master" of field "objectsfield" of castLib "master"
        put 
        next repeat
      end if
      y = y + 1
    end repeat
    i = i + 1
  end repeat
  tell the stage
    displayobject()
  end tell
end
