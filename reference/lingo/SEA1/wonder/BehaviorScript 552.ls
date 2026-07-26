on enterFrame
  global whatodo, egozh, egozv, whereami, nof, effectspath2
  nof = member(the castNum of sprite 1).name
  whereami = label(0)
  puppetSprite(30, 1)
  puppetSprite(31, 1)
  set the locH of sprite 30 to egozh
  set the locV of sprite 30 to egozv
  set the locH of sprite 31 to egozh
  set the locV of sprite 31 to egozv - 250
  set the visible of sprite 15 to 1
  set the visible of sprite 17 to 1
  set the visible of sprite 33 to 1
  set the visible of sprite 30 to 1
  updateStage()
  whatodo = "stand"
end
