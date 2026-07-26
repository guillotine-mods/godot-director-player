on exitFrame
  global soundspath, effectspath, shelltoday, inexits, mirror, bath, sink, catgame, sodom, globalday, firsttalk, wreck, tlkpath, monk, guard, dubi, globalnight, meetings, foe, syz, whatodo, resizepip, nextroomdata, egozh, egozv, nof, ifmovie, objectxx, objectyy
  set the keyDownScript to "fromnow"
  if globalday = 2 then
    soundspath("days")
    tlkpath("s_day2")
    meetings = "morn2,hatday2,manday2,dtcday2,investig,divefigt,mirolo"
  else
    put "dead" into item 3 of inexits
    soundspath("days")
    tlkpath("s_day3")
    meetings = "morn3,hatday3,hatsikum,figtair,end1"
  end if
  firsttalk = "0,0,0,0,1,0"
  shelltoday = 10
  mirror = 0
  catgame = 1
  sodom = "ok"
  cursorfunk()
  puppetSprite(30, 1)
  sprite(7).visible = 1
  sprite(8).visible = 1
  sprite(9).visible = 1
  sprite(15).visible = 0
  sprite(33).visible = 0
  sprite(22).visible = 0
  if globalday = 2 then
    sprite(23).visible = 1
    sprite(22).visible = 0
  else
    sprite(22).visible = 1
    sprite(23).visible = 0
  end if
  nof = "roomb"
  egozh = 328
  egozv = 365
  syz = 7
  whatodo = "stand"
  puppetSprite(100, 1)
  resizepip = 0
  nextroomdata = "000"
  ifmovie = "0,0"
  repeat with i = 1 to 14
    put "1" into item i of field "jokefield"
  end repeat
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
  sprite(34).visible = 0
  sprite(35).visible = 0
  sprite(19).visible = 0
  sprite(32).visible = 0
  sprite(18).visible = 0
  repeat with i = 1 to the number of items in field "shellfield"
    put "0" into item i of field "shellfield"
  end repeat
end
