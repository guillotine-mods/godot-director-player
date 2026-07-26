on exitFrame
  global whatodo, egozh, egozv, whereami, nof, effectspath2, globalnight, globalday
  nof = member(the castNum of sprite 1).name
  whereami = label(0)
  set the locH of sprite 30 to egozh
  set the locV of sprite 30 to egozv
  if (globalday = 1) or (item 3 of globalnight <> "0") then
    sprite(15).visible = 0
  else
    sprite(15).visible = 1
  end if
  sprite(33).visible = 0
  updateStage()
  whatodo = "stand"
end
