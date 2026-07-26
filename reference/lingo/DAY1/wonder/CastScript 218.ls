on mouseUp
  global egozh, egozv, nextroomdata, whatodo, effectspath, soundspath
  nextroomdata = "000"
  if (egozv <> 276) and (egozh <> 145) then
    egozv = 276
    egozh = 145
    walkonby()
  else
    if whatodo = "stand" then
      x = "show"
      repeat with i = 1 to the number of lines in field "objectsfield" of castLib "master"
        if line i of field "objectsfield" of castLib "master" = "sciser" then
          x = "washere"
        end if
      end repeat
      if x = "show" then
        set the visible of sprite 15 to 1
        set the visible of sprite 17 to 1
        sound playFile 1, effectspath & "found.aif"
      else
        sound playFile 1, soundspath & "pbag.aif"
      end if
    end if
  end if
end
