on exitFrame
  global meetings, tlkpath
  repeat with i = 2 to 40
    sprite(i).visible = 1
    puppetSprite(i, 0)
  end repeat
  put "done" into item 5 of meetings
  tlkpath("s_night3")
  sound playFile 1, tlkpath & "hez1.aif"
end
