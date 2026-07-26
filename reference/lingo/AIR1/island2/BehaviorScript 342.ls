on exitFrame
  global catgame, soundspath, whichsnd, egozh, egozv, newsyz, nextroomdata
  if catgame = "hezlost" then
    sound playFile 1, soundspath & "hezlost.aif"
    play frame "bothtalk"
    sound playFile 1, soundspath & "hezlost2.aif"
    play frame "heztalk"
    sprite(30).visible = 1
    newsyz = 9
    egozh = the locH of sprite 30
    egozv = the locV of sprite 30
    nextroomdata = "000"
    whichsnd = "cats"
    go("fort")
  else
    if catgame = "anotherround" then
      sound playFile 1, soundspath & "catagin.aif"
      play frame "bothtalk"
      sound playFile 1, soundspath & "catagin2aif"
      play frame "heztalk"
      go("choose1")
    else
      if catgame = "hezwinleft" then
        t = random(3)
        sound playFile 1, soundspath & "rcatlst6.aif"
        play frame "heztalk"
        go("choose21")
      else
        t = random(3)
        sound playFile 1, soundspath & "lcatlst" & t & ".aif"
        play frame "lefttalk"
        sound playFile 1, soundspath & "lcatlst7.aif"
        play frame "righttalk"
        go("choose22")
      end if
    end if
  end if
end
