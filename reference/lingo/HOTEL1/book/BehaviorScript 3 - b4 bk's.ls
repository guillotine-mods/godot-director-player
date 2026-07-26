on enterFrame
  global whatodo, egozh, egozv, whereami, nof, effectspath2
  nof = member(the castNum of sprite 1).name
  whereami = label(0)
  set the locH of sprite 30 to egozh
  set the locV of sprite 30 to egozv
  sprite(15).visible = 0
  sprite(17).visible = 0
  sprite(33).visible = 0
  updateStage()
  whatodo = "stand"
end
