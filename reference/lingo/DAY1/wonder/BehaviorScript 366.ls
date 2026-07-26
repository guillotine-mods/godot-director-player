on exitFrame
  global whatodo, egozh, egozv, whereami, nof, effectspath2
  nof = member(the castNum of sprite 1).name
  whereami = label(0)
  set the locH of sprite 30 to egozh
  set the locV of sprite 30 to egozv
  sprite(15).visible = 0
  sprite(17).visible = 0
  if item 5 of line 3 of field "Dprocess" = "done" then
    sprite(23).visible = 0
  else
    sprite(23).visible = 1
  end if
  sprite(33).visible = 0
  updateStage()
  whatodo = "stand"
end
