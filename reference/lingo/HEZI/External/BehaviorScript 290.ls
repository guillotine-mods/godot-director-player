on exitFrame
  global firsttalk, effectspath
  soundspath("games")
  if item 5 of firsttalk = "0" then
    put 1 into item 5 of firsttalk
    go("firsttalk")
  else
    go("rilstrt")
  end if
  repeat with i = 50 to 62
    sprite(i).visible = 1
  end repeat
  sound playFile 1, effectspath & "jos.aif"
end
