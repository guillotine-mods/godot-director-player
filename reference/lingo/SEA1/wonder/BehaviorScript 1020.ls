on mouseUp
  global wreck, soundspath, egozh, egozv, whatodo
  if item 10 of wreck = "0" then
    if (egozv <> 333) and (egozh <> 432) then
      egozv = 333
      egozh = 432
      walkonby()
    else
      if whatodo = "stand" then
        set the volume of sound 2 to 80
        sound playFile 1, soundspath & "pilot1.aif"
        play frame "pilotspk"
        sprite(30).visible = 0
        sound playFile 1, soundspath & "pilot2.aif"
        play frame "hezipilotspk"
        sprite(30).visible = 1
        sound playFile 1, soundspath & "pilot3.aif"
        play frame "get"
        sprite(30).visible = 0
        sound playFile 1, soundspath & "pilot4.aif"
        play frame "hezipilotspk"
        sprite(30).visible = 1
        sound playFile 1, soundspath & "pilot5.aif"
        play frame "introducepilot"
        set the volume of sound 2 to 130
        put "1" into item 10 of wreck
      end if
    end if
  else
    set the volume of sound 2 to 80
    sound playFile 1, soundspath & "pilot" & random(4) + 5 & ".aif"
    play frame "pilotspk"
    set the volume of sound 2 to 130
  end if
end
