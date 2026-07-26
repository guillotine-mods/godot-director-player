on enterFrame
  global whatodo, egozh, egozv, whereami, nof, effectspath2, ifmovie, nextroomdata, wreck
  nof = member(the castNum of sprite 1).name
  whereami = label(0)
  puppetSprite(30, 1)
  puppetSprite(31, 1)
  if item 4 of wreck = "done" then
    set the visible of sprite 22 to 1
    set the visible of sprite 23 to 1
    set the visible of sprite 24 to 1
    set the visible of sprite 29 to 0
  else
    set the visible of sprite 22 to 0
    set the visible of sprite 23 to 0
    set the visible of sprite 24 to 0
    set the visible of sprite 29 to 1
  end if
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
