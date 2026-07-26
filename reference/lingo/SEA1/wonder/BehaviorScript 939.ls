on exitFrame
  global whatodo, egozh, egozv, whereami, nof, effectspath2, newsyz, syz
  nof = member(the castNum of sprite 1).name
  whereami = label(0)
  egozh = 432
  egozv = 333
  puppetSprite(30, 1)
  set the visible of sprite 31 to 1
  set the visible of sprite 30 to 1
  set the locH of sprite 30 to egozh
  set the locV of sprite 30 to egozv
  newsyz = 5
  syz = 5
  set the visible of sprite 12 to 1
  set the visible of sprite 15 to 1
  set the visible of sprite 17 to 1
  set the visible of sprite 33 to 1
  set the visible of sprite 30 to 1
  updateStage()
  whatodo = "stand"
  updateStage()
end
