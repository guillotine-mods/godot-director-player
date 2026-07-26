on exitFrame
  global meetings, tlkpath, optcounter
  sound stop 2
  repeat with i = 2 to 40
    sprite(i).visible = 1
    puppetSprite(i, 0)
  end repeat
  repeat with i = 100 to 110
    puppetSprite(i, 0)
  end repeat
  put "done" into item 7 of meetings
  tlkpath("s_night2")
  soundspath("nights")
  sound playFile 1, tlkpath & "man1.aif"
  optcounter = 0
end
