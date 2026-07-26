on exitFrame
  global catgame, soundspath, egozh, egozv, newsyz, nextroomdata
  sound playFile 1, soundspath & "r" & catgame & ".aif"
  play frame "righttalk"
  if catgame contains "win" then
    sound playFile 1, soundspath & "heziwin" & random(3) & ".aif"
    play frame "heztalk"
    sound playFile 1, soundspath & "leftin" & random(2) & ".aif"
    play frame "lefttalk"
    go("insidefort")
  else
    if catgame contains "los" then
      sound playFile 1, soundspath & "hezilos" & random(3) & ".aif"
      play frame "heztalk"
      set the visible of sprite 30 to 1
      newsyz = 9
      egozh = the locH of sprite 30
      egozv = the locV of sprite 30
      nextroomdata = "000"
      go("fort")
    else
      sound playFile 1, soundspath & "hezrnd2" & random(3) & ".aif"
      play frame "heztalk"
      go("choose22")
    end if
  end if
end
