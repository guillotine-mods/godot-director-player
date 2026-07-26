on mouseUp
  sprite(93).visible = 0
  sprite(100).visible = 0
  repeat with i = 103 to 110
    sprite(i).visible = 0
  end repeat
  if item 10 of line 1 of field "Dprocess" <> "done" then
    put "done" into item 10 of line 1 of field "Dprocess"
    x = value(the text of field "points" of castLib "master")
    x = x + 1
    if x < 10 then
      put "00" & x into field "points" of castLib "master"
    else
      put "0" & x into field "points" of castLib "master"
    end if
  end if
  go("book4")
end
