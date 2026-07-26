on exitFrame
  global catgame, soundspath
  sound stop 2
  if catgame = 0 then
    sound playFile 1, soundspath & "cats1.aif"
    play frame "bothtalk"
    sound playFile 1, soundspath & "cats2.aif"
    play frame "heztalk"
    sound playFile 1, soundspath & "cats3.aif"
    play frame "righttalk"
    sound playFile 1, soundspath & "cats4.aif"
    play frame "heztalk"
    sound playFile 1, soundspath & "cats5.aif"
    play frame "lefttalk"
    sound playFile 1, soundspath & "cats6.aif"
    play frame "righttalk"
    sound playFile 1, soundspath & "cats7.aif"
    play frame "lefttalk"
    sound playFile 1, soundspath & "cats8.aif"
    play frame "righttalk"
    sound playFile 1, soundspath & "cats9.aif"
    play frame "heztalk"
    sound playFile 1, soundspath & "cats10.aif"
    play frame "bothtalk"
    catgame = "nomore"
    go("choose1")
  else
    x = random(10)
    sound playFile 1, soundspath & "catply" & x & ".aif"
    if x < 6 then
      play frame "lefttalk"
    else
      play frame "righttalk"
    end if
    go("choose1")
  end if
end
