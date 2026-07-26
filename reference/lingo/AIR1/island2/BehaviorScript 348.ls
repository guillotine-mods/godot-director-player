on exitFrame
  global catgame, soundspath, whichsnd, egozh, egozv, newsyz, nextroomdata
  sound playFile 1, soundspath & "l" & catgame & ".aif"
  play frame "lefttalk"
  if catgame contains "win" then
    sound playFile 1, soundspath & "heziwin" & random(3) & ".aif"
    play frame "heztalk"
    sound playFile 1, soundspath & "rightin" & random(2) & ".aif"
    play frame "righttalk"
    go("insidefort")
  else
    if catgame contains "los" then
      sound playFile 1, soundspath & "hezilos" & random(3) & ".aif"
      play frame "heztalk"
      sprite(30).visible = 1
      newsyz = 9
      egozh = the locH of sprite 30
      egozv = the locV of sprite 30
      nextroomdata = "000"
      whichsnd = "cats"
      go("fort")
    else
      sound playFile 1, soundspath & "hezrnd2" & random(3) & ".aif"
      play frame "heztalk"
      go("choose21")
    end if
  end if
end
