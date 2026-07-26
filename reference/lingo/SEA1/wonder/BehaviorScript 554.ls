on enterFrame
  global whatodo, egozh, egozv, whereami, nof, effectspath2, wreck
  nof = member(the castNum of sprite 1).name
  whereami = label(0)
  puppetSprite(30, 1)
  puppetSprite(31, 1)
  set the locH of sprite 30 to egozh
  set the locV of sprite 30 to egozv
  set the locH of sprite 31 to egozh
  set the locV of sprite 31 to egozv - 250
  if item 2 of wreck = "0" then
    sprite(6).visible = 1
    sprite(34).visible = 1
    sprite(38).visible = 0
  else
    sprite(6).visible = 0
    sprite(34).visible = 0
    sprite(38).visible = 1
  end if
  sprite(15).visible = 1
  sprite(17).visible = 1
  sprite(33).visible = 1
  sprite(30).visible = 1
  updateStage()
  whatodo = "stand"
  set the cursor of sprite 6 to [member("hand1").memberNum, member(member("hand2").memberNum)]
  set the cursor of sprite 32 to [member("magni1").memberNum, member(member("magni2").memberNum)]
  set the cursor of sprite 34 to [member("magni1").memberNum, member(member("magni2").memberNum)]
end
