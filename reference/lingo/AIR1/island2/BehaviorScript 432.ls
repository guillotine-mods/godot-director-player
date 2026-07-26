on exitFrame
  global nextroomdata, effectspath
  go(item 1 of nextroomdata)
  puppetSprite(30, 1)
  set the memberNum of sprite 30 to the number of member "standright5"
  updateStage()
  sound playFile 1, effectspath & "doorshut.aif"
  set the volume of sound 2 to 130
  sprite(30).visible = 1
  nextroomdata = "000"
end
