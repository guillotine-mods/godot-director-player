on exitFrame
  global saveNum, saveD, saveC, GlobalHour, GlobalSecond, saveE, saveF, saveB, saveG, saveH, savei, egozh, egozv, ifmovie, effectspath, soundspath, grrr, globalnight, globalday, cdsavepath, nextroomdata, newsyz, syz, nof, DorN
  puppetSprite(56, 1)
  if the movieName contains "night" then
    set the memberNum of sprite 56 to the number of member ("night" & globalday)
  else
    set the memberNum of sprite 56 to the number of member ("day" & globalday)
  end if
  put saveB into field "clickoncharacter" of castLib "master"
  put saveC into field "objectsfield" of castLib "master"
  put saveG into field "jokefield" of castLib "master"
  put saveF into field "points" of castLib "master"
  put saveE into field "plane" of castLib "master"
  put saveD into field "shellfield" of castLib "master"
  put saveH into field "Dprocess" of castLib "master"
  egozh = value(item 1 of savei)
  egozv = value(item 2 of savei)
  syz = value(item 3 of savei)
  repeat with i = 15 to 30
    sprite(i).visible = 1
  end repeat
  if globalday = 0 then
    tlkpath("strtgame")
    tell the stage
      go(1, cdsavepath & "exodus.dxr")
    end tell
    forget(window(cdsavepath & "saveload.dxr"))
  else
    tell the stage
      ccc = the movieName
    end tell
    if ccc contains "strtgame" then
      newsyz = syz
      nextroomdata = nof & "," & egozh & "," & egozv
      if DorN contains "night1" then
        tell the stage
          go(nof, cdsavepath & "night1.dxr")
        end tell
        if nof = ("path5" & (item 3 of globalnight = "done") or (globalday = 1)) then
          sprite(15).visible = 0
        end if
      else
        tell the stage
          go(nof, cdsavepath & "day1.dxr")
        end tell
      end if
      tell the stage
        puppetSprite(30, 1)
      end tell
      if (nof = "shore2") and (globalday = 1) then
        tell the stage
          sprite(6).visible = 0
        end tell
      end if
      tell the stage
        set the memberNum of sprite 30 to the number of member ("standright" & syz)
      end tell
      tell the stage
        updateStage()
      end tell
      tell the stage
        sprite(30).visible = 1
      end tell
      tell the stage
        peoplefunk()
      end tell
      tell the stage
        displayobject()
      end tell
      tell the stage
        cursorfunk()
      end tell
      tell the stage
        put the text of field "points" into field "points"
      end tell
      forget(window(cdsavepath & "saveload.dxr"))
      ifmovie = "0,0"
    else
      newsyz = syz
      nextroomdata = nof & "," & egozh & "," & egozv
      tell the stage
        ccc = the movieName
      end tell
      if DorN = ccc then
        tell the stage
          go(nof)
        end tell
      else
        tell the stage
          go(nof, DorN)
        end tell
      end if
      tell the stage
        puppetSprite(30, 1)
      end tell
      if (nof = "shore2") and (globalday = 1) then
        tell the stage
          sprite(6).visible = 0
        end tell
      end if
      tell the stage
        set the memberNum of sprite 30 to the number of member ("standright" & syz)
      end tell
      tell the stage
        updateStage()
      end tell
      tell the stage
        sprite(30).visible = 1
      end tell
      tell the stage
        peoplefunk()
      end tell
      tell the stage
        displayobject()
      end tell
      tell the stage
        cursorfunk()
      end tell
      tell the stage
        put the text of field "points" into field "points"
      end tell
      forget(window(cdsavepath & "saveload.dxr"))
      ifmovie = "0,0"
    end if
  end if
end
