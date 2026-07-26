on enterFrame
  global whatodo, egozh, egozv, whereami, nof, effectspath2, wreck
  nof = member(the castNum of sprite 1).name
  whereami = label(0)
  puppetSprite(30, 1)
  puppetSprite(31, 1)
  set the visible of sprite 28 to 1
  set the visible of sprite 29 to 1
  set the locH of sprite 30 to egozh
  set the locV of sprite 30 to egozv
  set the locH of sprite 31 to egozh
  set the locV of sprite 31 to egozv - 250
  if item 1 of wreck = "found" then
    set the visible of sprite 15 to 0
  else
    set the visible of sprite 15 to 1
  end if
  set the visible of sprite 14 to 1
  set the visible of sprite 38 to 1
  set the visible of sprite 34 to 1
  set the visible of sprite 30 to 1
  updateStage()
  whatodo = "stand"
end
