on exitFrame
  global soundspath, effectspath, shelltoday, inexits, mirror, bath, sink, catgame, globalday, meetings, syz, whatodo, resizepip, nextroomdata, egozh, egozv, nof, ifmovie, newsyz, objectxx, objectyy, globalnight
  if globalday = 1 then
    tlkpath("s_night1")
    meetings = "nite1,sabmon1,figtnigt,igul,zara,bigel,panter,psik"
  else
    if globalday = 2 then
      tlkpath("s_night2")
      meetings = "done,samnight,sabmon2,fugel,dagi,jo,karoz,gardug"
    end if
  end if
  soundspath("nights")
  cursorfunk()
  puppetSprite(30, 1)
  sprite(15).visible = 0
  sprite(33).visible = 0
  nof = "path5"
  egozh = 502
  egozv = 214
  syz = 6
  newsyz = 6
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
  if (item 3 of globalnight = "0") and (globalday = 2) then
    sprite(15).visible = 1
  else
    sprite(15).visible = 0
  end if
  go("path5")
  nof = "path5"
  sprite(30).visible = 1
end
