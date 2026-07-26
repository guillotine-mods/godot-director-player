on enterFrame
  global soundspath, effectspath, shelltoday, inexits, catgame, monk, guard, syz, whatodo, resizepip, nextroomdata, egozh, egozv, nof, ifmovie, objectxx, objectyy
  put "rachdown" into item 1 of nextroomdata
  peoplefunk()
  cursorfunk()
  soundspath("air")
  puppetSprite(30, 1)
  sprite(15).visible = 0
  sprite(33).visible = 0
  nof = "rachdown"
  egozh = 58
  egozv = 328
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
  repeat with i = 40 to 49
    sprite(i).visible = 0
  end repeat
  go("rachdown")
end
