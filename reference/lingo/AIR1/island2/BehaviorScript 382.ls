on exitFrame
  global monk, soundspath, effectspath, whichsnd
  puppetSprite(9, 1)
  if monk = "0" then
    sprite(9).visible = 0
    sound playFile 1, soundspath & "monk1.aif"
    play frame "speakright"
    sprite(9).visible = 1
    sound playFile 1, soundspath & "monk2.aif"
    sprite(30).visible = 0
    play frame "hezimonkspk"
    sprite(30).visible = 1
    sprite(9).visible = 0
    sound playFile 1, soundspath & "monk3.aif"
    play frame "speakright"
    sprite(9).visible = 1
    put "done" into item 8 of line 1 of field "Dprocess" of castLib "master"
    x = value(the text of field "points" of castLib "master")
    x = x + 1
    if x < 10 then
      put "00" & x into field "points" of castLib "master"
    else
      put "0" & x into field "points" of castLib "master"
    end if
    monk = 1
  else
    sprite(9).visible = 0
    sound playFile 1, soundspath & "monk1" & random(3) & ".aif"
    play frame "speakright"
    sprite(9).visible = 1
  end if
  if not soundBusy(2) or (whichsnd <> "monks") then
    sound playFile 2, effectspath & "church.aif"
    whichsnd = "monks"
  end if
end
