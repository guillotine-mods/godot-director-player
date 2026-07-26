on exitFrame
  global soundspath, effectspath, shelltoday, inexits, mirror, bath, sink, catgame, afganicnt, globalday, firsttalk, wreck, tlkpath, monk, guard, dubi, globalnight, meetings, foe, syz, whatodo, resizepip, nextroomdata, egozh, egozv, nof, ifmovie, objectxx, objectyy
  set the keyDownScript to "mainkey"
  foe = "3,2,man"
  if globalday = 1 then
    soundspath("days")
    tlkpath("s_day1")
    set the keyDownScript to "fromnow"
    meetings = "murder1,hatday1,mrfday1,ishday1,patpip1,tofircpt,allin,goldodead"
  end if
  repeat with i = 2 to the number of lines in field "clickoncharacter" of castLib "master"
    put "0" into item 2 of line i of field "clickoncharacter" of castLib "master"
  end repeat
  catgame = 0
  monk = 0
  guard = 0
  afganicnt = 0
  sink = 1
  put the text of field "Dprocessinit" into field "Dprocess"
  put "000" into field "points"
  globalnight = "0,0,0,0,0,0,0,0,0,0,0,0,0,0"
  dubi = 0
  bath = 1
  inexits = "0,0,0,0,0,0,0,0,0,0"
  wreck = "0,0,0,0,0,0,0,0,0,0,0,0,0,0,0"
  firsttalk = "0,0,0,0,0,0"
  shelltoday = 10
  mirror = 0
  cursorfunk()
  puppetSprite(30, 1)
  sprite(23).visible = 1
  sprite(15).visible = 0
  sprite(33).visible = 0
  sprite(6).visible = 0
  nof = "shore2"
  egozh = 600
  egozv = 325
  syz = 7
  whatodo = "stand"
  puppetSprite(100, 1)
  resizepip = 0
  nextroomdata = "000"
  ifmovie = "0,0"
  repeat with i = 1 to 13
    put "1" into item i of field "jokefield"
  end repeat
  repeat with i = 1 to 40
    put "0" into item i of field "shellfield" of castLib "master"
  end repeat
  repeat with i = 1 to 10
    put "empty" into line i of field "plane" of castLib "master"
  end repeat
  repeat with i = 1 to 30
    put "empty" into line i of field "objectsfield" of castLib "master"
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
  go("shore2")
end
