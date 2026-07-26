on enterFrame
  global soundspath, effectspath, shelltoday, inexits, catgame, monk, guard, syz, whatodo, resizepip, nextroomdata, egozh, egozv, nof, ifmovie, objectxx, objectyy
  inexits = "0,0,0,0,0,0,0,0"
  shelltoday = 10
  soundspath = the moviePath & "sounds:days:"
  effectspath = the moviePath & "effects:"
  repeat with i = 1 to 10
    put "1" into item i of field "jokefield"
  end repeat
  repeat with i = 1 to 40
    put "0" into item i of field "shellfield" of castLib "master"
  end repeat
  catgame = 0
  monk = 0
  guard = 0
  put "recept" into item 1 of nextroomdata
  peoplefunk()
  cursorfunk()
  puppetSprite(30, 1)
  set the visible of sprite 15 to 0
  set the visible of sprite 33 to 0
  nof = "recept"
  egozh = 58
  egozv = 328
  syz = 9
  whatodo = "stand"
  puppetSprite(100, 1)
  resizepip = 0
  nextroomdata = "000"
  ifmovie = "0,0"
  set the visible of sprite 17 to 1
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
    set the visible of sprite i to 0
  end repeat
  go("rachdown")
end
