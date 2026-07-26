on enterFrame
  global whatodo, egozh, egozv, whereami, nof, effectspath2, wreck
  nof = member(the castNum of sprite 1).name
  whereami = label(0)
  puppetSprite(30, 1)
  if (item 7 of wreck = "found") or (item 7 of wreck = "stick") then
    set the cursor of sprite 12 to [1, 1]
    sprite(12).visible = 0
  else
    set the cursor of sprite 12 to [member("hndcur1").memberNum, member("hndcur2").memberNum]
    sprite(12).visible = 1
  end if
  set the locH of sprite 30 to egozh
  set the locV of sprite 30 to egozv
  if item 3 of wreck = "found" then
    sprite(6).visible = 0
  else
    sprite(6).visible = 1
  end if
  set the cursor of sprite 6 to [1, 1]
  sprite(15).visible = 1
  sprite(17).visible = 1
  sprite(33).visible = 1
  sprite(34).visible = 1
  sprite(35).visible = 1
  sprite(36).visible = 1
  sprite(30).visible = 1
  updateStage()
  whatodo = "stand"
end
