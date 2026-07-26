on enterFrame
  if item 5 of line 3 of field "Dprocess" = "done" then
    sprite(23).visible = 0
  else
    sprite(23).visible = 1
  end if
end
