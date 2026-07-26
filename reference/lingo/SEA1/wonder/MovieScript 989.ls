on objecttalktime x
  global syz, egozv, egozh, usfultalking, usfulobject
  if member(the memberNum of sprite 30).name contains "stand" then
  else
    if member(the memberNum of sprite 30).name contains "right" then
      set the memberNum of sprite 30 to the number of member ("standright" & syz)
    else
      set the memberNum of sprite 30 to the number of member ("standleft" & syz)
    end if
    set the locV of sprite 30 to egozv
    set the locH of sprite 30 to egozh
  end if
  usfultalking = 1
  usfulobject = x
  if marker(0) = label("shore1go") then
    go("instruct")
  end if
end

on talkproc init, fieldname, lastmark
  global usfultalking, usfulline, usfulobject, soundspath, egozv, egozh, syz
  if usfultalking = 1 then
    r = "not"
    i = 1
    repeat while (i < (the number of lines in field fieldname of castLib "master" + 1)) and (r = "not")
      if item 1 of line i of field fieldname = usfulobject then
        r = i
      end if
      i = i + 1
    end repeat
    if r <> "not" then
      usfulline = r
      egozh = the locH of sprite 30
      egozv = the locV of sprite 30
      sound playFile 1, soundspath & usfulobject & init & usfultalking & ".aif"
      usfultalking = usfultalking + 1
    end if
  else
    if (the number of items in line usfulline of field fieldname of castLib "master" - 1) >= usfultalking then
      sound playFile 1, soundspath & usfulobject & init & usfultalking & ".aif"
      usfultalking = usfultalking + 1
    else
      if member(the memberNum of sprite 30).name contains "right" then
        set the memberNum of sprite 30 to the number of member ("standright" & syz)
      else
        set the memberNum of sprite 30 to the number of member ("standleft" & syz)
      end if
      set the locV of sprite 30 to egozv
      set the locH of sprite 30 to egozh
      if sprite(19).visible = 1 then
        sprite(14).visible = 0
      end if
      set the volume of sound 2 to 130
      go(lastmark)
    end if
  end if
end
