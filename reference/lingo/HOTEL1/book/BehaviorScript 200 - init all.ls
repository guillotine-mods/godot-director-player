on exitFrame
  global soundspath, effectspath, shelltoday, inexits, globalday, syz, whatodo, resizepip, nextroomdata, egozh, egozv, nof, ifmovie, objectxx, objectyy
  if globalday = 2 then
    repeat with i = 1 to 10
      put "1" into item i of field "jokefield"
    end repeat
    meetings = "morn2,hatday2,manday2,dtcday2,investig,mirolo"
  else
    repeat with i = 1 to 10
      put "1" into item i of field "jokefield"
    end repeat
    meetings = "morn3,hatday3,hatsikum,end"
  end if
  put "recept" into item 1 of nextroomdata
  peoplefunk()
  cursorfunk()
  puppetSprite(30, 1)
  sprite(15).visible = 0
  sprite(33).visible = 0
  sprite(22).visible = 0
  sprite(23).visible = 0
  nof = "recept"
  egozh = 289
  egozv = 388
  syz = 9
  whatodo = "stand"
  puppetSprite(100, 1)
  resizepip = 0
  nextroomdata = "000"
  ifmovie = "0,0"
  sprite(17).visible = 1
  objectxx = 322
  objectyy = 441
  repeat with i = 103 to 110
    puppetSprite(i, 1)
    if line i - 102 of field "objectsfield" of castLib "master" <> "empty" then
      set the memberNum of sprite i to the number of member line i - 102 of field "objectsfield"
      set the moveableSprite of sprite i to 1
      set the cursor of sprite i to [the number of member "hand1", the number of member "hand2"]
      next repeat
    end if
    set the memberNum of sprite i to the number of member "object0" of castLib "master"
  end repeat
end
