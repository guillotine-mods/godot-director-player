on enterFrame
  global whatodo, egozh, egozv, whereami, nof, effectspath2
  nof = member(the castNum of sprite 1).name
  whereami = label(0)
  set the locH of sprite 30 to egozh
  set the locV of sprite 30 to egozv
  set the visible of sprite 15 to 0
  set the visible of sprite 17 to 0
  set the visible of sprite 33 to 0
  updateStage()
  whatodo = "stand"
end
