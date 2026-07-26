on mouseUp
  global effectspath
  x = the memberNum of sprite 103
  x = member(x, "master").name
  i = 1
  repeat while i <= 30
    if line i of field "objectsfield" of castLib "master" = x then
      y = i
    end if
    i = 1 + i
  end repeat
  if y > 1 then
    sound playFile 1, effectspath & "moveinv.aif"
    y = y - 1
    i = 103
    repeat while i <= 110
      set the memberNum of sprite i to the number of member line y of field "objectsfield" of castLib "master"
      set the moveableSprite of sprite i to 1
      set the cursor of sprite i to [the number of member "hand1", the number of member "hand2"]
      y = y + 1
      i = 1 + i
    end repeat
  else
    sound playFile 1, effectspath & "stukinv.aif"
  end if
end
